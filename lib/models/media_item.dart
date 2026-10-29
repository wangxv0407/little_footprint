/// 媒体文件（一条记录可关联多个：图/音/视频）
class MediaItem {
  final int id; // 本地自增 id，同步不认
  final String recordUuid; // 关联 growth_record.uuid
  final String fileName; // 文件名
  final String fileType; // image / audio / video
  final String localRelativePath; // APP 内相对路径
  final String fileMd5; // 文件哈希，同步去重
  final int fileSize; // 字节
  final int isOrigin; // 0=压缩预览版（参与同步），1=原图/原视频（不同步）

  const MediaItem({
    required this.id,
    required this.recordUuid,
    required this.fileName,
    required this.fileType,
    required this.localRelativePath,
    required this.fileMd5,
    required this.fileSize,
    required this.isOrigin,
  });

  MediaItem copyWith({
    int? id,
    String? recordUuid,
    String? fileName,
    String? fileType,
    String? localRelativePath,
    String? fileMd5,
    int? fileSize,
    int? isOrigin,
  }) =>
      MediaItem(
        id: id ?? this.id,
        recordUuid: recordUuid ?? this.recordUuid,
        fileName: fileName ?? this.fileName,
        fileType: fileType ?? this.fileType,
        localRelativePath: localRelativePath ?? this.localRelativePath,
        fileMd5: fileMd5 ?? this.fileMd5,
        fileSize: fileSize ?? this.fileSize,
        isOrigin: isOrigin ?? this.isOrigin,
      );

  factory MediaItem.fromMap(Map<String, dynamic> map) => MediaItem(
        id: map['id'] as int? ?? 0,
        recordUuid: map['record_uuid'] as String,
        fileName: map['file_name'] as String,
        fileType: map['file_type'] as String,
        localRelativePath: map['local_relative_path'] as String,
        fileMd5: map['file_md5'] as String? ?? '',
        fileSize: map['file_size'] as int? ?? 0,
        isOrigin: map['is_origin'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'record_uuid': recordUuid,
        'file_name': fileName,
        'file_type': fileType,
        'local_relative_path': localRelativePath,
        'file_md5': fileMd5,
        'file_size': fileSize,
        'is_origin': isOrigin,
      };
}
