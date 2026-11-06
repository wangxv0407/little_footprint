// 临时回环验证脚本：验证 _Channel 在真实 TCP 上收发 JSON 行与二进制块。
// 用法：dart run tool/channel_loopback_probe.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// ---- 从 sync_service.dart 复制的 _Channel（保持一致，验证用）----
class _Channel {
  final Socket _socket;
  final List<int> _buf = [];
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

  Future<bool> _fill() async {
    while (_pending.isEmpty) {
      if (_eof) return false;
      final w = _notify ??= Completer<void>();
      await w.future;
    }
    _buf.addAll(_pending.removeAt(0));
    return true;
  }

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

  Future<Uint8List?> receiveBytes(int length) async {
    while (_buf.length < length) {
      if (!await _fill()) return null;
    }
    final out = Uint8List.fromList(_buf.sublist(0, length));
    _buf.removeRange(0, length);
    return out;
  }
}

Future<void> main() async {
  const port = 58891;
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);

  // 服务端：收 hello → 回 hello → 收 changeset → 回 changeset
  //        → 收 file_header + 二进制 → 回 file_ack
  server.listen((sock) async {
    final ch = _Channel(sock);
    final hello = await ch.receive();
    print('S 收 hello: $hello');
    await ch.send({'type': 'hello'});
    final cs = await ch.receive();
    print('S 收 changeset: ${cs!['records'].length} 条, 首条内容: ${cs['records'][0]['content']}');
    await ch.send({'type': 'changeset', 'records': [
      {'uuid': 'u1', 'content': '妈妈端记录：第一次翻身😄'}
    ]});
    final header = await ch.receive();
    final size = header!['file_size'] as int;
    final bytes = await ch.receiveBytes(size);
    print('S 收文件: ${header['file_name']} 期望 $size 实际 ${bytes!.length} md5匹配=${_md5ish(bytes)}');
    await ch.send({'type': 'file_ack', 'ok': true});
    // 连续再收两行（验证缓冲区残留处理）
    final extra = await ch.receive();
    print('S 收尾包: $extra');
    await sock.close();
  });

  final sock = await Socket.connect(InternetAddress.loopbackIPv4, port);
  final ch = _Channel(sock);

  await ch.send({'type': 'hello', 'role': 'sync'});
  await ch.receive(); // 消费对端 hello

  // changeset 里放长中文 + emoji（多字节，验证跨分片不乱码）
  final longCn = '爸爸端记录：' + '今天去了公园，桃花开了，宝宝第一次看到风筝，' * 40 + '🌸结尾';
  await ch.send({
    'type': 'changeset',
    'records': [
      {'uuid': 'u1', 'content': longCn}
    ]
  });
  final peer = await ch.receive();
  print('C 收 changeset: ${peer!['records'].length} 条, 内容一致=${peer['records'][0]['content'] == '妈妈端记录：第一次翻身😄'}');

  // 发一个 3MB 的二进制块 + 紧跟一行 JSON（验证行与二进制共缓冲不错位）
  final blob = Uint8List(3 * 1024 * 1024);
  for (var i = 0; i < blob.length; i++) {
    blob[i] = i % 251;
  }
  await ch.send({'type': 'file_header', 'file_name': 'photo.jpg', 'file_size': blob.length});
  await ch.sendBytes(blob);
  await ch.send({'type': 'done'}); // 紧随其后的行，必须能被对端按行读到

  final ack = await ch.receive();
  print('C 收 ack: $ack');
  await sock.close();
  server.close();
  print('LOOPBACK_OK');
}

String _md5ish(List<int> b) => 'len=${b.length}';
