import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../db/app_database.dart';
import '../services/sync_service.dart';
import '../theme.dart';

class SyncPage extends StatefulWidget {
  const SyncPage({super.key});

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  final _ipCtrl = TextEditingController();
  String _localIp = '获取中…';
  String _role = '';
  bool _serverRunning = false;
  bool _syncing = false;
  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _loadIp();
    _loadRole();
    SyncService.instance.events.listen((e) {
      if (!mounted) return;
      setState(() {
        _logs.insert(0, e.message);
        if (_logs.length > 50) _logs.removeRange(50, _logs.length);
      });
    });
  }

  Future<void> _loadIp() async {
    try {
      final ip = await NetworkInfo().getWifiIP();
      if (!mounted) return;
      setState(() => _localIp = ip ?? '未连接WiFi');
    } catch (_) {
      if (mounted) setState(() => _localIp = '获取失败');
    }
  }

  Future<void> _loadRole() async {
    final info = await AppDatabase.instance.getBabyInfo();
    if (mounted) {
      setState(() => _role = info?.deviceRole == 'wife' ? '妈妈设备' : '爸爸设备');
    }
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    super.dispose();
  }

  Future<void> _startServer() async {
    try {
      await SyncService.instance.startServer();
      if (mounted) setState(() => _serverRunning = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('开启服务失败，可能端口被占用')));
      }
    }
  }

  Future<void> _stopServer() async {
    await SyncService.instance.stopServer();
    if (mounted) setState(() => _serverRunning = false);
  }

  Future<void> _connectAndSync() async {
    final ip = _ipCtrl.text.trim();
    if (ip.isEmpty) {
      _snack('请输入对方的局域网 IP');
      return;
    }
    setState(() => _syncing = true);
    try {
      await SyncService.instance.connectAndSync(ip);
      _snack('同步完成');
    } catch (e) {
      _snack('同步失败: $e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('局域网同步'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _tipBanner(),
          const SizedBox(height: 16),
          _infoPanel(),
          const SizedBox(height: 16),
          // 开启/关闭服务
          FilledButton.icon(
            onPressed: _serverRunning ? _stopServer : _startServer,
            icon: Icon(_serverRunning ? Icons.stop : Icons.settings_input_antenna),
            label: Text(_serverRunning ? '关闭同步服务' : '开启同步服务（等待对方连接）'),
          ),
          const SizedBox(height: 16),
          // 手动连接
          TextField(
            controller: _ipCtrl,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              hintText: '输入对方局域网 IP（如 192.168.1.8）',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _syncing ? null : _connectAndSync,
            icon: const Icon(Icons.sync),
            label: Text(_syncing ? '同步中…' : '连接并开始同步'),
          ),
          const SizedBox(height: 16),
          // 日志
          Container(
            height: 220,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF1F2A29),
              borderRadius: BorderRadius.circular(12),
            ),
            child: _logs.isEmpty
                ? const Center(
                    child: Text('同步日志将显示在这里',
                        style: TextStyle(color: Colors.white38, fontSize: 13)),
                  )
                : ListView.builder(
                    reverse: true,
                    itemCount: _logs.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        _logs[i],
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          const Text(
            '提示：两台手机需连接同一个 WiFi（同频段）、关闭路由器 AP 隔离。\nMVP 版使用手动 IP 连接；自动扫描设备为二期功能。',
            style: TextStyle(fontSize: 12, color: AppColors.secondaryText, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _tipBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF0C27A)),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber, color: Color(0xFFE07A5F), size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '两台设备连接同一个 WiFi、同频段（同 2.4G 或同 5G），关闭路由器 AP 隔离，否则无法搜索到对方。',
              style: TextStyle(fontSize: 13, color: Color(0xFF7A5C2E), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoPanel() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _infoRow('本机 IP', _localIp),
          _infoRow('本机身份', _role),
          _infoRow('监听端口', '58888'),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.secondaryText, fontSize: 14)),
          Text(value,
              style: const TextStyle(
                  color: AppColors.textMain, fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
