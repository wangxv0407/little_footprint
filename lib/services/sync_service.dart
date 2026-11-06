import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

/// 局域网 TCP 同步服务：增量双向合并，端口 58888
/// 协议：JSON 行报文（UTF-8，\n 结尾）+ 二进制文件流
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  static const int port = 58888;

  ServerSocket? _server;
  Socket? _socket;
  final _events = StreamController<SyncEvent>.broadcast();
  Stream<SyncEvent> get events => _events.stream;

  bool get isListening => _server != null;

  // ---------- 服务端：开启同步服务 ----------
  Future<void> startServer() async {
    if (_server != null) return;
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
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
    _emit('已关闭同步服务');
  }

  Future<void> _onIncoming(Socket socket) async {
    _emit('检测到设备连接: ${socket.remoteAddress.address}');
    _socket = socket;
    try {
      // 服务端是被动方：先响应对方，再拉取对方
      await _runSync(socket, initiator: false);
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
      final socket =
          await Socket.connect(ip, port, timeout: const Duration(seconds: 8));
      _socket = socket;
      _emit('已连接到 ${socket.remoteAddress.address}');
      // 客户端是发起方：先拉取对方，再响应对方
      await _runSync(socket, initiator: true);
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

  int _added = 0, _updated = 0, _conflicts = 0;

  /// [initiator] 客户端=true / 服务端=false。
  ///
  /// 两台手机跑的是同一份代码，必须用连接角色拆开「谁先拉」，
  /// 否则两边同时发 need 又同时等数据，互等死锁。
  Future<void> _runSync(Socket socket, {required bool initiator}) async {
    final channel = _Channel(socket);
    final db = AppDatabase.instance;
    final lastSyncTs = await db.getLastSyncTs();
    _added = 0;
    _updated = 0;
    _conflicts = 0;

    // 阶段1：hello。发完必须把对方的 hello 读掉，
    // 否则下面等 changeset 时会读到 hello，整条消息流错位一格。
    await channel.send({'type': 'hello', 'role': 'sync', 'ok': true});
    final peerHello = await channel.receive();
    if (peerHello == null) {
      _emit('对方没有响应', 2);
      return;
    }

    // 阶段2：交换 changeset（增量）
    final myRecords = await db.getRecordsChangedSince(lastSyncTs);
    final myMetrics = await db.getMetricsChangedSince(lastSyncTs);
    final changeset = {
      'type': 'changeset',
      'last_sync_ts': lastSyncTs,
      'records': myRecords
          .map(
              (r) => {'uuid': r.uuid, 'ts': r.lastModifyTs, 'del': r.isDeleted})
          .toList(),
      'metrics': myMetrics
          .map(
              (m) => {'uuid': m.uuid, 'ts': m.lastModifyTs, 'del': m.isDeleted})
          .toList(),
    };
    await channel.send(changeset);
    final peerChangeset = await channel.receive();
    if (peerChangeset == null || peerChangeset['type'] != 'changeset') {
      _emit('握手失败：未收到对方数据清单', 2);
      return;
    }

    // 阶段3：对比，确定需要从对方获取的数据。
    // 直接查本地库逐条比时间戳，而不是只跟「本次有变动的记录」比——
    // 本地一条很久没动的新版本不在变动集里，只跟变动集比会被旧版本覆盖。
    final needRecords = await _computeNeedRecords(peerChangeset, db);
    final needMetrics = await _computeNeedMetrics(peerChangeset, db);
    _emit('对方有 ${needRecords.length} 条记录 / ${needMetrics.length} 条数据待同步');

    // 阶段4：两轮交换。发起方先拉后响应，被动方先响应后拉，
    // 消息顺序在两个方向上都严格成对，不会互等。
    if (initiator) {
      await _pull(channel, db,
          needRecords: needRecords, needMetrics: needMetrics);
      await _serve(channel, db);
    } else {
      await _serve(channel, db);
      await _pull(channel, db,
          needRecords: needRecords, needMetrics: needMetrics);
    }

    // 阶段5：完成，记录同步时间。中途抛异常走不到这里，
    // lastSyncTs 不会前进，下次同步会自动重试本次没同步到的增量。
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insertSyncLog(SyncLog(
      id: 0,
      peerIp: socket.remoteAddress.address,
      syncTs: now,
      summary: '新增$_added，更新$_updated，冲突$_conflicts',
    ));
    await channel.send({'type': 'done'});
    _emit('同步完成：新增 $_added，更新 $_updated，冲突 $_conflicts', 1);
  }

  // 计算需要从对方拉取的记录 uuid 列表
  Future<List<String>> _computeNeedRecords(
      Map<String, dynamic>? peer, AppDatabase db) async {
    if (peer == null) return const <String>[];
    final need = <String>[];
    for (final item in (peer['records'] as List? ?? [])) {
      final uuid = item['uuid'] as String;
      final peerTs = item['ts'] as int? ?? 0;
      final peerDel = item['del'] as int? ?? 0;
      final mine = await db.getGrowthRecord(uuid);
      if (mine == null) {
        // 对方有，我没有。删除标记的记录我本地本来就没有，不用拉
        if (peerDel == 1) continue;
        need.add(uuid);
      } else if (peerTs > mine.lastModifyTs) {
        // 对方更新（含对方删了这条：拉回来的是带删除标记的墓碑，
        // upsert 后本地查询过滤 is_deleted=0，等于同步了删除操作）
        need.add(uuid);
      }
    }
    return need;
  }

  Future<List<String>> _computeNeedMetrics(
      Map<String, dynamic>? peer, AppDatabase db) async {
    if (peer == null) return const <String>[];
    final byUuid = {for (final m in await db.getAllMetrics()) m.uuid: m};
    final need = <String>[];
    for (final item in (peer['metrics'] as List? ?? [])) {
      final uuid = item['uuid'] as String;
      final peerTs = item['ts'] as int? ?? 0;
      final peerDel = item['del'] as int? ?? 0;
      final mine = byUuid[uuid];
      if (mine == null) {
        if (peerDel == 1) continue;
        need.add(uuid);
      } else if (peerTs > mine.lastModifyTs) {
        need.add(uuid);
      }
    }
    return need;
  }

  /// 拉取阶段：本方发 need，逐条收对方数据。
  /// 对方对每个请求的 uuid 都必须回一条（没有就回 data=null 占位），
  /// 否则本方会在这里永远等下去。
  Future<void> _pull(_Channel channel, AppDatabase db,
      {required List<String> needRecords,
      required List<String> needMetrics}) async {
    await channel.send({'type': 'need_records', 'uuids': needRecords});
    for (final uuid in needRecords) {
      final rec = await _receiveRecord(channel);
      if (rec == null) continue; // 对方也没有，占位响应
      final existing = await db.getGrowthRecord(uuid);
      if (existing == null) {
        _added++;
      } else {
        _updated++;
        if (rec.lastModifyTs < existing.lastModifyTs) _conflicts++;
      }
      await db.upsertGrowthRecord(rec);
      // 接收对应压缩媒体
      await _receiveMediaForRecord(channel, db, uuid);
    }

    await channel.send({'type': 'need_metrics', 'uuids': needMetrics});
    for (final _ in needMetrics) {
      final m = await _receiveMetric(channel);
      if (m != null) {
        await db.upsertGrowthMetric(m);
      }
    }
  }

  /// 响应阶段：本方收对方的 need，逐条发数据。
  Future<void> _serve(_Channel channel, AppDatabase db) async {
    final needRec = await channel.receive();
    if (needRec == null || needRec['type'] != 'need_records') return;
    final uuids = (needRec['uuids'] as List? ?? []).cast<String>();
    for (final uuid in uuids) {
      final rec = await db.getGrowthRecord(uuid);
      if (rec == null) {
        // 占位响应，避免拉取方在等待 record_data 时卡死
        await channel.send({'type': 'record_data', 'data': null});
        continue;
      }
      await channel.send({'type': 'record_data', 'data': rec.toMap()});
      // 发送该记录的压缩媒体
      final medias = await db.getMediaForRecord(uuid, onlySyncable: true);
      for (final m in medias) {
        await _sendMedia(channel, db, m);
      }
      await channel.send({'type': 'media_done', 'record_uuid': uuid});
    }

    final needMet = await channel.receive();
    if (needMet == null || needMet['type'] != 'need_metrics') return;
    final metUuids = (needMet['uuids'] as List? ?? []).cast<String>();
    final metrics = await db.getAllMetrics();
    for (final uuid in metUuids) {
      GrowthMetric? m;
      for (final x in metrics) {
        if (x.uuid == uuid) {
          m = x;
          break;
        }
      }
      // 没有也要回一条占位，否则拉取方会卡死
      await channel.send({'type': 'metric_data', 'data': m?.toMap()});
    }
  }

  // ---------- 媒体文件发送 / 接收 ----------
  Future<void> _sendMedia(_Channel channel, AppDatabase db, MediaItem m) async {
    final absPath =
        await MediaService.instance.absolutePathOf(m.localRelativePath);
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
          await channel
              .send({'type': 'file_ack', 'file_name': fileName, 'ok': false});
          continue;
        }
        // 同一条记录同步过一次后媒体就落了库，不查重会越同步越多
        final known = await db.getMediaForRecord(recordUuid);
        if (known.any((e) => e.fileName == fileName)) {
          await channel
              .send({'type': 'file_ack', 'file_name': fileName, 'ok': true});
          continue;
        }
        final dir = await MediaService.instance.compressedDir;
        final target = File(p.join(dir.path, fileName));
        await target.writeAsBytes(bytes);
        final rel = p.relative(target.path,
            from: (await MediaService.instance.recordsRoot).path);
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
        await channel
            .send({'type': 'file_ack', 'file_name': fileName, 'ok': true});
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

/// JSON 行 + 二进制传输通道。
///
/// **Socket 是单订阅流，绝不能反复 `socket.first`**——第二次监听直接抛
/// StateError，之后所有读取都会拿到「连接已断」。所以构造时订阅一次，
/// 把字节攒进缓冲区，再按需取「一行 JSON」或「定长二进制块」。
/// 行和二进制共用同一个字节缓冲，TCP 不保证消息边界，
/// 拆成两个缓冲区（行一个、字节一个）会互相污染。
class _Channel {
  final Socket _socket;

  /// 已到达但还没消费完的原始字节
  final List<int> _buf = [];

  /// 已到达但还没并入 [_buf] 的 TCP 分片
  final List<Uint8List> _pending = [];

  Completer<void>? _notify;
  bool _eof = false;

  _Channel(this._socket) {
    _socket.listen(
      _onData,
      onDone: _onDone,
      onError: (Object _) => _onDone(),
      cancelOnError: true,
    );
  }

  void _onData(Uint8List d) {
    _pending.add(d);
    _wake();
  }

  void _onDone() {
    _eof = true;
    _wake();
  }

  void _wake() {
    final w = _notify;
    _notify = null;
    w?.complete();
  }

  /// 等到新的字节就并入缓冲并返回 true；连接已结束返回 false
  Future<bool> _fill() async {
    while (_pending.isEmpty) {
      if (_eof) return false;
      final w = _notify ??= Completer<void>();
      await w.future;
    }
    _buf.addAll(_pending.removeAt(0));
    return true;
  }

  /// 读一行（以 \n 结尾）。连接结束时没有完整行则返回 null。
  /// 只对「完整的一行」做 utf8 解码，中文被 TCP 分片切断也不会乱码。
  Future<String?> readLine() async {
    while (true) {
      final nl = _buf.indexOf(10);
      if (nl >= 0) {
        final line = utf8.decode(_buf.sublist(0, nl));
        _buf.removeRange(0, nl + 1);
        return line;
      }
      if (!await _fill()) return null;
    }
  }

  Future<void> send(Map<String, dynamic> json) async {
    _socket.add(utf8.encode('${jsonEncode(json)}\n'));
    await _socket.flush();
  }

  Future<void> sendBytes(List<int> bytes) async {
    _socket.add(bytes);
    await _socket.flush();
  }

  Future<Map<String, dynamic>?> receive() async {
    final line = await readLine();
    if (line == null || line.isEmpty) return null;
    return jsonDecode(line) as Map<String, dynamic>;
  }

  /// 读定长二进制块。连接中断导致读不满时返回 null。
  Future<Uint8List?> receiveBytes(int length) async {
    while (_buf.length < length) {
      if (!await _fill()) return null;
    }
    final out = Uint8List.fromList(_buf.sublist(0, length));
    _buf.removeRange(0, length);
    return out;
  }
}
