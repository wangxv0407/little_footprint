import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../db/app_database.dart';
import '../models/growth_metric.dart';
import '../models/growth_record.dart';
import '../models/media_item.dart';
import '../models/sync_log.dart';
import 'media_service.dart';

/// 同步事件，回调给 UI 进度日志
class SyncEvent {
  final String message;
  final int type; // 0 信息, 1 成功, 2 警告
  SyncEvent(this.message, [this.type = 0]);
}

/// 同步结果
class SyncResult {
  final int added;
  final int updated;
  final int conflicts;
  final String peerIp;
  const SyncResult({
    required this.added,
    required this.updated,
    required this.conflicts,
    required this.peerIp,
  });
}

/// 局域网 TCP 同步服务：增量双向合并，端口 58888
/// 协议：JSON 行报文（UTF-8，\n 结尾）+ 二进制文件流
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  static const int port = 58888;

  ServerSocket? _server;
  Socket? _socket;
  bool _running = false;
  final _events = StreamController<SyncEvent>.broadcast();
  Stream<SyncEvent> get events => _events.stream;

  bool get isListening => _server != null;

  // ---------- 服务端：开启同步服务 ----------
  Future<void> startServer() async {
    if (_server != null) return;
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      _running = true;
      _emit('已开启同步服务，监听端口 $port');
      _server!.listen(_onIncoming, onError: (e) => _emit('监听错误: $e', 2));
    } catch (e) {
      _emit('无法开启同步服务（端口可能被占用）: $e', 2);
      rethrow;
    }
  }

  Future<void> stopServer() async {
    await _server?.close();
    _server = null;
    _running = false;
    _emit('已关闭同步服务');
  }

  Future<void> _onIncoming(Socket socket) async {
    _emit('检测到设备连接: ${socket.remoteAddress.address}');
    _socket = socket;
    try {
      await _runSync(socket);
    } catch (e) {
      _emit('同步中断: $e', 2);
    } finally {
      await socket.close();
      _socket = null;
    }
  }

  // ---------- 客户端：主动连接 ----------
  Future<void> connectAndSync(String ip) async {
    try {
      final socket = await Socket.connect(ip, port,
          timeout: const Duration(seconds: 8));
      _socket = socket;
      _emit('已连接到 ${socket.remoteAddress.address}');
      await _runSync(socket);
      _emit('同步会话结束，连接已断开');
    } catch (e) {
      _emit('连接失败: $e', 2);
      rethrow;
    } finally {
      _socket?.destroy();
      _socket = null;
    }
  }

  // ---------- 主同步流程 ----------
  Future<void> _runSync(Socket socket) async {
    final channel = _Channel(socket);
    final db = AppDatabase.instance;
    final lastSyncTs = await db.getLastSyncTs();

    // 阶段1：hello
    await channel.send({'type': 'hello', 'role': 'sync', 'ok': true});

    // 阶段2：交换 changeset（增量）
    final myRecords = await db.getRecordsChangedSince(lastSyncTs);
    final myMetrics = await db.getMetricsChangedSince(lastSyncTs);
    final changeset = {
      'type': 'changeset',
      'last_sync_ts': lastSyncTs,
      'records': myRecords
          .map((r) => {'uuid': r.uuid, 'ts': r.lastModifyTs, 'del': r.isDeleted})
          .toList(),
      'metrics': myMetrics
          .map((m) => {'uuid': m.uuid, 'ts': m.lastModifyTs, 'del': m.isDeleted})
          .toList(),
    };
    await channel.send(changeset);
    final peerChangeset = await channel.receive();

    // 阶段3：对比，确定需要从对方获取的数据
    final needRecords = _computeNeedRecords(peerChangeset, myRecords, lastSyncTs);
    final needMetrics = _computeNeedMetrics(peerChangeset, myMetrics, lastSyncTs);

    // 阶段4：对称双向交换。
    // 第一轮：本方作为拉取方（发 need，收对方数据）
    // 第二轮：本方作为响应方（收对方 need，发数据）
    // 客户端与服务端行为完全对称，由调用顺序保证不会双方同时向对方拉取。
    await _exchange(channel, db, needRecords: needRecords, needMetrics: needMetrics, isPuller: true);
    await _exchange(channel, db, needRecords: needRecords, needMetrics: needMetrics, isPuller: false);

    // 阶段5：完成，记录同步时间
    final now = DateTime.now().millisecondsSinceEpoch;
    final result = _lastResult;
    await db.insertSyncLog(SyncLog(
      id: 0,
      peerIp: socket.remoteAddress.address,
      syncTs: now,
      summary: '新增${result?.added ?? 0}，更新${result?.updated ?? 0}，冲突${result?.conflicts ?? 0}',
    ));
    await channel.send({'type': 'done'});
    _emit('同步完成');
  }

  SyncResult? _lastResult;

  // 计算需要从对方拉取的记录 uuid 列表
  List<String> _computeNeedRecords(Map<String, dynamic> peer,
      List<GrowthRecord> myRecords, int lastSyncTs) {
    final need = <String>[];
    final peerList = (peer['records'] as List? ?? []);
    for (final item in peerList) {
      final uuid = item['uuid'] as String;
      final peerTs = item['ts'] as int? ?? 0;
      final peerDel = item['del'] as int? ?? 0;
      GrowthRecord? mine;
      for (final r in myRecords) {
        if (r.uuid == uuid) {
          mine = r;
          break;
        }
      }
      if (mine == null) {
        // 对方有，我没有
        if (peerDel == 1) continue; // 删除的不用拉
        need.add(uuid);
      } else if (peerTs > mine.lastModifyTs) {
        need.add(uuid);
      }
    }
    return need;
  }

  List<String> _computeNeedMetrics(Map<String, dynamic> peer,
      List<GrowthMetric> myMetrics, int lastSyncTs) {
    final need = <String>[];
    final peerList = (peer['metrics'] as List? ?? []);
    for (final item in peerList) {
      final uuid = item['uuid'] as String;
      final peerTs = item['ts'] as int? ?? 0;
      final peerDel = item['del'] as int? ?? 0;
      GrowthMetric? mine;
      for (final m in myMetrics) {
        if (m.uuid == uuid) {
          mine = m;
          break;
        }
      }
      if (mine == null) {
        if (peerDel == 1) continue;
        need.add(uuid);
      } else if (peerTs > mine.lastModifyTs) {
        need.add(uuid);
      }
    }
    return need;
  }

  /// 双向交换数据：isPuller=true 表示本方发送 need 并接收对方数据
  /// isPuller=false 表示本方接收对方 need 并发送数据
  Future<void> _exchange(_Channel channel, AppDatabase db,
      {required List<String> needRecords,
      required List<String> needMetrics,
      required bool isPuller}) async {
    var added = 0, updated = 0, conflicts = 0;

    if (isPuller) {
      // 本方请求
      await channel.send({
        'type': 'need_records',
        'uuids': needRecords,
        'last_sync_ts': await db.getLastSyncTs(),
      });
      for (final uuid in needRecords) {
        final rec = await _receiveRecord(channel);
        if (rec != null) {
          final existing = await db.getGrowthRecord(uuid);
          if (existing == null) {
            added++;
          } else {
            updated++;
            if (existing.lastModifyTs > 0 && rec.lastModifyTs < existing.lastModifyTs) {
              conflicts++;
            }
          }
          await db.upsertGrowthRecord(rec);
          // 接收对应压缩媒体
          await _receiveMediaForRecord(channel, db, uuid);
        }
      }
      await channel.send({'type': 'need_metrics', 'uuids': needMetrics});
      for (final uuid in needMetrics) {
        final m = await _receiveMetric(channel);
        if (m != null) {
          await db.upsertGrowthMetric(m);
        }
      }
    } else {
      // 本方响应：接收对方 need 并发送数据
      final needRec = await channel.receive();
      if (needRec['type'] == 'need_records') {
        final uuids = (needRec['uuids'] as List? ?? []).cast<String>();
        for (final uuid in uuids) {
          final rec = await db.getGrowthRecord(uuid);
          if (rec == null) {
            // 占位响应，避免拉取方在等待 media_done 时卡死
            await channel.send({'type': 'record_data', 'data': null});
            continue;
          }
          await channel.send({
            'type': 'record_data',
            'data': rec.toMap(),
          });
          // 发送该记录的压缩媒体
          final medias = await db.getMediaForRecord(uuid, onlySyncable: true);
          for (final m in medias) {
            await _sendMedia(channel, db, m);
          }
          await channel.send({'type': 'media_done', 'record_uuid': uuid});
        }
      }
      final needMet = await channel.receive();
      if (needMet['type'] == 'need_metrics') {
        final uuids = (needMet['uuids'] as List? ?? []).cast<String>();
        for (final uuid in uuids) {
          final metrics = await db.getMetrics();
          GrowthMetric? m;
          for (final x in metrics) {
            if (x.uuid == uuid) {
              m = x;
              break;
            }
          }
          if (m == null) continue;
          await channel.send({'type': 'metric_data', 'data': m.toMap()});
        }
      }
    }

    _lastResult = SyncResult(
        added: added, updated: updated, conflicts: conflicts, peerIp: '');
  }

  // ---------- 媒体文件发送 / 接收 ----------
  Future<void> _sendMedia(_Channel channel, AppDatabase db, MediaItem m) async {
    final absPath = await MediaService.instance.absolutePathOf(m.localRelativePath);
    if (!await File(absPath).exists()) return;
    final bytes = await File(absPath).readAsBytes();
    await channel.send({
      'type': 'file_header',
      'record_uuid': m.recordUuid,
      'file_name': m.fileName,
      'file_type': m.fileType,
      'file_size': bytes.length,
      'file_md5': m.fileMd5,
      'is_origin': m.isOrigin,
    });
    await channel.sendBytes(bytes);
    await channel.receive(); // 等待 file_ack
  }

  Future<void> _receiveMediaForRecord(
      _Channel channel, AppDatabase db, String recordUuid) async {
    // 接收一系列文件，直到 media_done
    while (true) {
      final msg = await channel.receive();
      if (msg == null) return;
      if (msg['type'] == 'media_done') {
        if (msg['record_uuid'] == recordUuid) return;
        continue;
      }
      if (msg['type'] == 'file_header') {
        final fileName = msg['file_name'] as String;
        final size = msg['file_size'] as int? ?? 0;
        final md5 = msg['file_md5'] as String? ?? '';
        final fileType = msg['file_type'] as String? ?? 'image';
        final bytes = await channel.receiveBytes(size);
        if (bytes == null || bytes.length != size) {
          _emit('文件接收失败: $fileName', 2);
          await channel.send({'type': 'file_ack', 'file_name': fileName, 'ok': false});
          continue;
        }
        final dir = await MediaService.instance.compressedDir;
        final target = File(p.join(dir.path, fileName));
        await target.writeAsBytes(bytes);
        final rel = p.relative(target.path, from: (await MediaService.instance.recordsRoot).path);
        await db.insertMedia(MediaItem(
          id: 0,
          recordUuid: recordUuid,
          fileName: fileName,
          fileType: fileType,
          localRelativePath: rel,
          fileMd5: md5,
          fileSize: size,
          isOrigin: 0,
        ));
        _emit('收到文件: $fileName');
        await channel.send({'type': 'file_ack', 'file_name': fileName, 'ok': true});
      }
    }
  }

  // 接收单条记录数据（配合传输完媒体后返回）
  // 若对端缺失该记录（data 为 null），返回 null 且不接收媒体。
  Future<GrowthRecord?> _receiveRecord(_Channel channel) async {
    final msg = await channel.receive();
    if (msg == null || msg['type'] != 'record_data') return null;
    final data = msg['data'];
    if (data == null) return null;
    return GrowthRecord.fromMap(Map<String, dynamic>.from(data as Map));
  }

  Future<GrowthMetric?> _receiveMetric(_Channel channel) async {
    final msg = await channel.receive();
    if (msg == null || msg['type'] != 'metric_data') return null;
    final data = msg['data'];
    if (data == null) return null;
    return GrowthMetric.fromMap(Map<String, dynamic>.from(data as Map));
  }

  void _emit(String msg, [int type = 0]) {
    _events.add(SyncEvent(msg, type));
  }

  void dispose() {
    _events.close();
    _socket?.destroy();
    _server?.close();
  }
}

/// 简单 JSON 行 + 二进制传输通道
class _Channel {
  final Socket _socket;
  final _buffer = BytesBuilder(copy: false);
  String _lineBuf = '';

  _Channel(this._socket);

  Future<void> send(Map<String, dynamic> json) async {
    final line = '${jsonEncode(json)}\n';
    _socket.add(utf8.encode(line));
    await _socket.flush();
  }

  Future<void> sendBytes(List<int> bytes) async {
    _socket.add(bytes);
    await _socket.flush();
  }

  Future<Map<String, dynamic>?> receive() async {
    final line = await _readLine();
    if (line == null) return null;
    return jsonDecode(line) as Map<String, dynamic>;
  }

  Future<String?> _readLine() async {
    while (true) {
      final nl = _lineBuf.indexOf('\n');
      if (nl >= 0) {
        final line = _lineBuf.substring(0, nl);
        _lineBuf = _lineBuf.substring(nl + 1);
        return line;
      }
      final data = await _readOnce();
      if (data == null) return _lineBuf.isEmpty ? null : _lineBuf;
      _lineBuf += utf8.decode(data, allowMalformed: true);
    }
  }

  Future<Uint8List?> receiveBytes(int length) async {
    while (_buffer.length < length) {
      final data = await _readOnce();
      if (data == null) return null;
      _buffer.add(data);
    }
    final out = _buffer.takeBytes();
    if (out.length > length) {
      // 多读的部分保留到 lineBuf（转 utf8 宽松）
      final extra = out.sublist(length);
      _lineBuf = utf8.decode(extra, allowMalformed: true) + _lineBuf;
    }
    return Uint8List.fromList(out.sublist(0, length));
  }

  Future<Uint8List?> _readOnce() async {
    try {
      final data = await _socket.first;
      return data;
    } catch (_) {
      return null;
    }
  }
}
