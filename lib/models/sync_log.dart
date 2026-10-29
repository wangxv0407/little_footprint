/// 本地同步记录（仅本机，不同步给对方）
/// 作用：记录上次同步时间，实现增量同步
class SyncLog {
  final int id;
  final String peerIp;
  final int syncTs;
  final String summary;

  const SyncLog({
    required this.id,
    required this.peerIp,
    required this.syncTs,
    required this.summary,
  });

  factory SyncLog.fromMap(Map<String, dynamic> map) => SyncLog(
        id: map['id'] as int? ?? 0,
        peerIp: map['peer_ip'] as String? ?? '',
        syncTs: map['sync_ts'] as int? ?? 0,
        summary: map['summary'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {
        'peer_ip': peerIp,
        'sync_ts': syncTs,
        'summary': summary,
      };
}
