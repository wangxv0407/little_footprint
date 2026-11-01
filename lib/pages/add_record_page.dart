import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';
import '../models/growth_record.dart';
import '../models/media_item.dart';
import '../models/milestone_def.dart';
import '../models/record_type.dart';
import '../services/media_service.dart';
import '../theme.dart';
import '../utils/age_calculator.dart';
import '../widgets/audio_recorder_panel.dart';
import '../widgets/common.dart';
import 'gallery_picker_page.dart';

/// 新增 / 编辑记录
class AddRecordPage extends StatefulWidget {
  final int babyId;

  /// 从里程碑页进入时预选
  final String? initialMilestoneCode;

  /// 有值表示编辑模式
  final String? recordUuid;

  const AddRecordPage({
    super.key,
    required this.babyId,
    this.initialMilestoneCode,
    this.recordUuid,
  });

  @override
  State<AddRecordPage> createState() => _AddRecordPageState();
}

class _AddRecordPageState extends State<AddRecordPage> {
  final _contentCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  final _tags = <String>[];

  /// 记录时间只保留到「天」，时分秒归零
  DateTime _recordTime = _dateOnly(DateTime.now());

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _recordType = RecordType.diary;
  String _milestoneCode = '';

  GrowthRecord? _existing;
  List<MediaItem> _existingMedia = const [];
  final Set<int> _removedMediaIds = {};

  final _picker = ImagePicker();
  final _recorder = AudioRecorder();
  bool _recording = false;
  String? _recordedPath;
  String? _recordingPath;
  int _recordSeconds = 0;
  Timer? _recordTimer;

  /// 实时音量序列（0..1），驱动录音面板的音浪
  final _levels = <double>[];
  StreamSubscription<Amplitude>? _ampSub;

  final _pickedImagePaths = <String>[];
  String? _pickedVideoPath;

  bool _saving = false;
  bool _loading = true;
  String _rootPath = '';
  DateTime? _babyBirthForAge;
  Map<String, MilestoneDef> _msDefs = const {};

  static const _presetTags = ['翻身', '辅食', '疫苗', '出游', '学说话'];

  bool get _isEdit => widget.recordUuid != null;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _ampSub?.cancel();
    _contentCtrl.dispose();
    _tagCtrl.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final db = AppDatabase.instance;
    _rootPath = (await MediaService.instance.recordsRoot).path;
    _babyBirthForAge = (await db.getBabyById(widget.babyId))?.birthDate;
    final defs = await db.getMilestoneDefs();
    final map = {for (final d in defs) d.code: d};

    if (widget.initialMilestoneCode != null) {
      _recordType = RecordType.milestone;
      _milestoneCode = widget.initialMilestoneCode!;
    }

    if (_isEdit) {
      final r = await db.getGrowthRecord(widget.recordUuid!);
      if (r != null) {
        _existing = r;
        _recordTime = _dateOnly(r.recordTime);
        _contentCtrl.text = r.content;
        _tags
          ..clear()
          ..addAll(r.tags);
        _recordType = r.recordType;
        _milestoneCode = r.milestoneCode;
        _existingMedia = await db.getMediaForRecord(r.uuid);
      }
    }

    if (!mounted) return;
    setState(() {
      _msDefs = map;
      _loading = false;
    });
  }

  // ==================== 时间 ====================

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _recordTime,
      firstDate: DateTime(now.year - 18),
      lastDate: now,
      helpText: '选择发生日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked == null) return;
    setState(() {
      // 记录只精确到「天」，时间部分统一归零
      _recordTime = DateTime(picked.year, picked.month, picked.day);
    });
  }

  // ==================== 媒体 ====================

  /// 拍照：走系统相机（Android 11+ 已在 Manifest 声明 IMAGE_CAPTURE 可见性）
  Future<void> _captureImage() async {
    try {
      final f =
          await _picker.pickImage(source: ImageSource.camera, imageQuality: 90);
      if (f != null) setState(() => _pickedImagePaths.add(f.path));
    } catch (e) {
      _snack('打不开相机：$e');
    }
  }

  Future<void> _captureVideo() async {
    try {
      final f = await _picker.pickVideo(source: ImageSource.camera);
      if (f != null) setState(() => _pickedVideoPath = f.path);
    } catch (e) {
      _snack('打不开相机：$e');
    }
  }

  /// 内置图库选择器。权限被拒时用户可以选择改用系统选择器。
  Future<void> _pickFromGallery({bool video = false}) async {
    final r = await Navigator.of(context).push<GalleryPickResult>(
      MaterialPageRoute(
        builder: (_) => GalleryPickerPage(
          videoOnly: video,
          maxCount: video ? 1 : 9,
          title: video ? '视频' : '照片',
        ),
      ),
    );
    if (r == null || !mounted) return;

    if (r.fallbackToSystem) {
      await _systemPick(video: video);
      return;
    }
    setState(() {
      if (video) {
        _pickedVideoPath = r.paths.first;
      } else {
        _pickedImagePaths.addAll(r.paths);
      }
    });
  }

  /// 兜底：系统选择器（无需权限，但外观依赖 ROM，部分机型会落成文件管理器）
  Future<void> _systemPick({required bool video}) async {
    try {
      if (video) {
        final f = await _picker.pickVideo(source: ImageSource.gallery);
        if (f != null) setState(() => _pickedVideoPath = f.path);
      } else {
        final files = await _picker.pickMultiImage();
        if (files.isNotEmpty) {
          setState(() => _pickedImagePaths.addAll(files.map((f) => f.path)));
        }
      }
    } catch (e) {
      _snack('打开选择器失败：$e');
    }
  }

  /// 上传本地音频文件
  Future<void> _pickAudioFile() async {
    try {
      final res = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['mp3', 'm4a', 'wav', 'aac', 'ogg', 'flac'],
        withData: false,
      );
      final path = res?.files.single.path;
      if (path == null || !mounted) return;
      setState(() => _recordedPath = path);
    } catch (e) {
      _snack('选择音频失败：$e');
    }
  }

  // ==================== 录音 ====================

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted && !status.isLimited) {
      final blocked = status.isPermanentlyDenied || status.isRestricted;
      _snack(
        blocked ? '麦克风权限已被关闭，请在系统设置中开启' : '需要麦克风权限才能录音',
        actionLabel: blocked ? '去设置' : null,
        onAction: blocked ? () => openAppSettings() : null,
      );
      return;
    }

    final dir = await MediaService.instance.compressedDir;
    final path =
        p.join(dir.path, 'rec_${DateTime.now().millisecondsSinceEpoch}.aac');
    try {
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
    } catch (e) {
      _snack('开始录音失败：$e');
      return;
    }
    if (!mounted) return;
    _recordingPath = path;

    // 实时音量：current 是 dBFS，静音约 -45，满量程 0
    _ampSub?.cancel();
    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 120))
        .listen((amp) {
      if (!mounted) return;
      final lv = ((amp.current + 45) / 45).clamp(0.0, 1.0);
      setState(() {
        _levels.add(lv);
        if (_levels.length > 80) _levels.removeRange(0, _levels.length - 80);
      });
    });

    setState(() {
      _recording = true;
      _recordSeconds = 0;
      _levels.clear();
    });

    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _recordSeconds++);
    });
  }

  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    await _ampSub?.cancel();
    _ampSub = null;
    final path = await _recorder.stop();
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordedPath = path ?? _recordingPath;
      _levels.clear();
    });
    _recordingPath = null;
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    await _ampSub?.cancel();
    _ampSub = null;
    await _recorder.stop();
    final tmp = _recordingPath;
    _recordingPath = null;
    if (tmp != null) {
      try {
        final f = File(tmp);
        if (await f.exists()) await f.delete();
      } catch (_) {
        // 临时文件删不掉不影响使用
      }
    }
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordSeconds = 0;
      _levels.clear();
    });
  }

  // ==================== 标签 ====================

  void _addTag([String? value]) {
    final v = (value ?? _tagCtrl.text).trim();
    if (v.isEmpty) return;
    if (_tags.contains(v)) {
      _tagCtrl.clear();
      return;
    }
    setState(() {
      _tags.add(v);
      _tagCtrl.clear();
    });
  }

  // ==================== 保存 ====================

  Future<void> _save() async {
    if (_saving) return;
    if (_recording) {
      _snack('请先停止录音');
      return;
    }
    if (_recordType == RecordType.milestone && _milestoneCode.isEmpty) {
      _snack('请选择一个里程碑');
      return;
    }

    final db = AppDatabase.instance;
    final media = MediaService.instance;

    if (_recordType == RecordType.milestone && !_isEdit) {
      final achieved =
          await db.isMilestoneAchieved(widget.babyId, _milestoneCode);
      if (achieved) {
        final def = _msDefs[_milestoneCode];
        _snack('「${def?.name ?? '该里程碑'}」已经记录过了');
        return;
      }
    }

    setState(() => _saving = true);

    final ts = DateTime.now().millisecondsSinceEpoch;
    final uuid = _isEdit ? _existing!.uuid : const Uuid().v4();
    final role = await db.getDeviceRole();

    final record = GrowthRecord(
      uuid: uuid,
      babyId: widget.babyId,
      recordTime: _recordTime,
      content: _contentCtrl.text.trim(),
      tags: List.of(_tags),
      recordType: _recordType,
      milestoneCode: _recordType == RecordType.milestone ? _milestoneCode : '',
      isFavorite: _existing?.isFavorite ?? 0,
      createDevice: _existing?.createDevice ?? role,
      lastModifyTs: ts,
      isDeleted: 0,
    );
    await db.upsertGrowthRecord(record);

    // 编辑模式：移除被删掉的媒体
    if (_isEdit) {
      final keep = _existingMedia
          .where((m) => !_removedMediaIds.contains(m.id))
          .map((m) => m.id)
          .toList();
      await db.retainMedia(uuid, keep);
    }

    // 新增照片：压缩后入库
    for (final path in _pickedImagePaths) {
      try {
        final r = await media.createCompressedImage(path);
        await db.insertMedia(MediaItem(
          id: 0,
          recordUuid: uuid,
          fileName: p.basename(r.$1),
          fileType: 'image',
          localRelativePath: r.$2,
          fileMd5: r.$3,
          fileSize: r.$4,
          isOrigin: 0,
        ));
      } catch (_) {
        _snack('有图片处理失败，已跳过');
      }
    }

    // 录音
    if (_recordedPath != null && await File(_recordedPath!).exists()) {
      final r = await media.storeRecording(_recordedPath!);
      await db.insertMedia(MediaItem(
        id: 0,
        recordUuid: uuid,
        fileName: p.basename(r.$1),
        fileType: 'audio',
        localRelativePath: r.$2,
        fileMd5: r.$3,
        fileSize: r.$4,
        isOrigin: 0,
      ));
    }

    // 视频：本期仍只存本机原片，不参与跨机同步
    if (_pickedVideoPath != null && await File(_pickedVideoPath!).exists()) {
      final r = await media.storeOrigin(_pickedVideoPath!);
      await db.insertMedia(MediaItem(
        id: 0,
        recordUuid: uuid,
        fileName: p.basename(r.$1),
        fileType: 'video',
        localRelativePath: r.$2,
        fileMd5: r.$3,
        fileSize: r.$4,
        isOrigin: 1,
      ));
    }

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  void _snack(String msg, {String? actionLabel, VoidCallback? onAction}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        action: (actionLabel != null && onAction != null)
            ? SnackBarAction(label: actionLabel, onPressed: onAction)
            : null,
      ),
    );
  }

  String get _recTimeText {
    final m = (_recordSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_recordSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_recording,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _recording) _snack('正在录音，请先停止或取消');
      },
      child: Scaffold(
        backgroundColor: AppColors.paper,
        appBar: AppBar(
          backgroundColor: AppColors.paper,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          titleSpacing: AppSpace.xs,
          title: Row(
            children: [
              TextButton(
                onPressed: () => Navigator.maybePop(context),
                style: TextButton.styleFrom(foregroundColor: AppColors.ink2),
                child: const Text('取消'),
              ),
              const Spacer(),
              Text(
                _isEdit ? '编辑记录' : '新增记录',
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              TextButton(
                onPressed: _saving ? null : _save,
                child: const Text('保存'),
              ),
            ],
          ),
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.clay))
            : Stack(
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(
                              AppSpace.pageX, 4, AppSpace.pageX, 20),
                          children: [
                            _typeSelector(),
                            const SizedBox(height: AppSpace.md),
                            if (_recordType == RecordType.milestone)
                              _milestonePicker(),
                            _label('发生时间'),
                            _timeRow(),
                            _label('此刻发生了什么'),
                            _contentField(),
                            _label('标签'),
                            _tagArea(),
                            _label('照片与声音'),
                            _mediaGrid(),
                            const SizedBox(height: AppSpace.xs),
                            const Text('图片与录音会同步到另一台手机；视频目前只保存在本机',
                                style: AppText.caption),
                          ],
                        ),
                      ),
                      _bottomBar(),
                    ],
                  ),
                  // 录音时底部升起紧凑面板，录制期间仍可看到正在写的内容
                  if (_recording)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: AudioRecorderPanel(
                        timeText: _recTimeText,
                        levels: _levels,
                        onStop: _stopRecording,
                        onCancel: _cancelRecording,
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  /// 切换记录类型。切到「里程碑」时若尚未选定具体条目，直接弹出清单，
  /// 省掉「切类型 → 再点选择行 → 再选条目」里的中间一步。
  void _switchType(String type) {
    if (_recordType == type) return;
    if (type == RecordType.diary) {
      setState(() {
        _recordType = type;
        _milestoneCode = '';
      });
      return;
    }
    setState(() => _recordType = type);
    if (_milestoneCode.isEmpty) _chooseMilestone();
  }

  Widget _typeSelector() {
    Widget item(String type, String label) {
      final on = _recordType == type;
      return Expanded(
        child: GestureDetector(
          onTap: () => _switchType(type),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? AppColors.card : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              boxShadow: on
                  ? const [
                      BoxShadow(
                          color: Color(0x142B2724),
                          blurRadius: 4,
                          offset: Offset(0, 1))
                    ]
                  : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                color: on ? AppColors.ink : AppColors.ink2,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFEFE7DA),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(children: [
        item(RecordType.diary, '日常'),
        item(RecordType.milestone, '里程碑')
      ]),
    );
  }

  Widget _milestonePicker() {
    final def = _msDefs[_milestoneCode];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        border: Border.all(color: AppColors.line),
        onTap: _chooseMilestone,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(def == null ? '选择里程碑' : '已选择',
                      style: AppText.caption.copyWith(letterSpacing: 1.2)),
                  const SizedBox(height: 4),
                  Text(
                    def?.name ?? '从里程碑库里挑一个',
                    style: def == null
                        ? AppText.itemTitle.copyWith(color: AppColors.ink3)
                        : AppText.serifTitle(size: 17),
                  ),
                  if (def != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${MilestoneCategory.label(def.category)} · 建议 ${def.monthRangeLabel}',
                      style: AppText.caption,
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.ink3),
          ],
        ),
      ),
    );
  }

  Widget _timeRow() {
    final baby = _babyBirthForAge;
    final ageText =
        baby == null ? null : AgeCalculator.fullText(baby, _recordTime);
    return GestureDetector(
      onTap: _pickDate,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: AppDecor.card(radius: AppRadius.md),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined,
                size: 17, color: AppColors.clay),
            const SizedBox(width: 10),
            Text(
              DateFormat('yyyy-MM-dd').format(_recordTime),
              style: const TextStyle(fontSize: 14, color: AppColors.ink),
            ),
            const Spacer(),
            if (ageText != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.pineLight,
                  borderRadius: AppRadius.pill,
                ),
                child: Text(
                  ageText,
                  style: const TextStyle(fontSize: 10.5, color: AppColors.pine),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _contentField() {
    return TextField(
      controller: _contentCtrl,
      maxLines: 6,
      minLines: 3,
      style: const TextStyle(fontSize: 14.5, height: 1.7, color: AppColors.ink),
      decoration: InputDecoration(
        hintText: '写下此刻的小事…',
        hintStyle: const TextStyle(color: AppColors.ink3, fontSize: 14),
        filled: true,
        fillColor: AppColors.card,
        contentPadding: const EdgeInsets.all(14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.clay, width: 1.4),
        ),
      ),
    );
  }

  Widget _tagArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in _tags)
              GestureDetector(
                onTap: () => setState(() => _tags.remove(t)),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.clayLight,
                    borderRadius: AppRadius.pill,
                    border: Border.all(color: const Color(0xFFE9C9BA)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(t,
                          style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.clayDark,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 4),
                      const Icon(Icons.close,
                          size: 12, color: AppColors.clayDark),
                    ],
                  ),
                ),
              ),
            for (final t in _presetTags.where((t) => !_tags.contains(t)))
              AppChip(label: t, onTap: () => _addTag(t)),
            GestureDetector(
              onTap: _promptNewTag,
              child: AppChip(label: '+ 新建', dashed: true),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _promptNewTag() async {
    _tagCtrl.clear();
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paper,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: const Text('新建标签', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: _tagCtrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如：第一次游泳'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _tagCtrl.text),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (v != null) _addTag(v);
  }

  Widget _mediaGrid() {
    final items = <Widget>[];

    // 编辑模式：已有媒体
    for (final m in _existingMedia) {
      if (_removedMediaIds.contains(m.id)) continue;
      items.add(_thumbTile(
        child: m.fileType == 'image'
            ? Image.file(File(p.join(_rootPath, m.localRelativePath)),
                fit: BoxFit.cover, errorBuilder: (_, __, ___) => _broken())
            : Center(
                child: Icon(
                  m.fileType == 'audio' ? Icons.graphic_eq : Icons.videocam,
                  color: AppColors.pine,
                  size: 26,
                ),
              ),
        onRemove: () => setState(() => _removedMediaIds.add(m.id)),
      ));
    }

    // 新选图片
    for (final path in _pickedImagePaths) {
      items.add(_thumbTile(
        child: Image.file(File(path),
            fit: BoxFit.cover, errorBuilder: (_, __, ___) => _broken()),
        onRemove: () => setState(() => _pickedImagePaths.remove(path)),
      ));
    }

    // 新视频
    if (_pickedVideoPath != null) {
      items.add(_thumbTile(
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam, color: AppColors.pine, size: 24),
            SizedBox(height: 2),
            Text('已选择', style: AppText.caption),
          ],
        ),
        onRemove: () => setState(() => _pickedVideoPath = null),
      ));
    }

    // 添加按钮
    items.add(
      GestureDetector(
        onTap: _showMediaSheet,
        child: Container(
          decoration: AppDecor.dashed(),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, color: AppColors.ink3, size: 24),
              SizedBox(height: 4),
              Text('添加',
                  style: TextStyle(fontSize: 10.5, color: AppColors.ink3)),
            ],
          ),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, c) {
        const gap = 8.0;
        final size = (c.maxWidth - gap * 2) / 3;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final w in items)
                  SizedBox(width: size, height: size, child: w),
              ],
            ),
            // 音频单独用横条展示，比塞进方格更容易看出文件名
            if (_recordedPath != null) ...[
              const SizedBox(height: gap),
              _audioTile(c.maxWidth),
            ],
          ],
        );
      },
    );
  }

  Widget _audioTile(double width) {
    final path = _recordedPath!;
    return SizedBox(
      width: width,
      height: 58,
      child: Container(
        decoration: AppDecor.card(radius: AppRadius.md),
        padding: const EdgeInsets.only(left: 10, right: 4),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: AppColors.clayLight,
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.graphic_eq, size: 16, color: AppColors.clay),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    '音频',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    p.basename(path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption,
                  ),
                ],
              ),
            ),
            AppIconButton(
              icon: Icons.close,
              size: 16,
              onPressed: () => setState(() => _recordedPath = null),
            ),
          ],
        ),
      ),
    );
  }

  Widget _broken() => Container(color: AppColors.line);

  Widget _thumbTile({
    required Widget child,
    required VoidCallback onRemove,
  }) {
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Container(color: AppColors.clayLight, child: child),
          ),
        ),
        Positioned(
          right: 3,
          top: 3,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                  color: Color(0x99000000), shape: BoxShape.circle),
              child: const Icon(Icons.close, size: 13, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showMediaSheet() async {
    final pick = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.lineStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              '添加媒体',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  _mediaTile('拍照', Icons.photo_camera_outlined,
                      primary: true,
                      onTap: () => Navigator.pop(ctx, 'capture')),
                  const SizedBox(width: 10),
                  _mediaTile('图库照片', Icons.photo_library_outlined,
                      primary: true,
                      onTap: () => Navigator.pop(ctx, 'gallery')),
                  const SizedBox(width: 10),
                  _mediaTile('拍摄视频', Icons.videocam_outlined,
                      onTap: () => Navigator.pop(ctx, 'capture_video')),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  _mediaTile('图库视频', Icons.video_library_outlined,
                      onTap: () => Navigator.pop(ctx, 'gallery_video')),
                  const SizedBox(width: 10),
                  _mediaTile('录音', Icons.mic_none,
                      onTap: () => Navigator.pop(ctx, 'record')),
                  const SizedBox(width: 10),
                  _mediaTile('上传音频', Icons.graphic_eq,
                      onTap: () => Navigator.pop(ctx, 'audio_file')),
                ],
              ),
            ),
            const SizedBox(height: 26),
          ],
        ),
      ),
    );
    switch (pick) {
      case 'capture':
        await _captureImage();
      case 'gallery':
        await _pickFromGallery();
      case 'capture_video':
        await _captureVideo();
      case 'gallery_video':
        await _pickFromGallery(video: true);
      case 'record':
        await _startRecording();
      case 'audio_file':
        await _pickAudioFile();
    }
  }

  Widget _mediaTile(
    String label,
    IconData icon, {
    bool primary = false,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: primary ? AppColors.clayLight : AppColors.card,
                borderRadius: BorderRadius.circular(19),
                border: Border.all(
                  color: primary ? const Color(0xFFF0D9CE) : AppColors.line,
                ),
              ),
              child: Center(
                child: Icon(
                  icon,
                  size: 23,
                  color: primary ? AppColors.clay : AppColors.ink2,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                color: primary ? AppColors.clay : AppColors.ink2,
                fontWeight: primary ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _chooseMilestone() async {
    final defs = await AppDatabase.instance.getMilestoneDefs();
    final achieved =
        await AppDatabase.instance.getMilestoneStatuses(widget.babyId);
    final achievedCodes = {
      for (final s in achieved.where((e) => e.achieved)) s.def.code
    };
    if (!mounted) return;

    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.paper,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        maxChildSize: 0.92,
        minChildSize: 0.5,
        expand: false,
        builder: (_, scrollCtrl) {
          var category = MilestoneCategory.motorGross;
          return StatefulBuilder(
            builder: (ctx2, setSheet) {
              final list = defs.where((d) => d.category == category).toList();
              return Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.lineStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('选择里程碑',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.pageX),
                      itemCount: MilestoneCategory.ordered.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final c = MilestoneCategory.ordered[i];
                        return Center(
                          child: AppChip(
                            label: MilestoneCategory.label(c),
                            selected: category == c,
                            onTap: () => setSheet(() => category = c),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollCtrl,
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final d = list[i];
                        final done = achievedCodes.contains(d.code);
                        return ListTile(
                          title: Text(
                            d.name,
                            style: AppText.itemTitle.copyWith(
                              color: done ? AppColors.ink3 : AppColors.ink,
                            ),
                          ),
                          subtitle: Text(
                            done ? '已达成' : '建议 ${d.monthRangeLabel}',
                            style: AppText.caption,
                          ),
                          trailing: done
                              ? const Icon(Icons.check_circle,
                                  size: 18, color: AppColors.pineLight)
                              : const Icon(Icons.chevron_right,
                                  size: 18, color: AppColors.ink3),
                          onTap: () => Navigator.pop(ctx, d.code),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );

    if (picked != null) {
      setState(() {
        _recordType = RecordType.milestone;
        _milestoneCode = picked;
      });
    }
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.lg, bottom: AppSpace.xs),
        child: Text(
          text,
          style: AppText.caption
              .copyWith(fontWeight: FontWeight.w600, letterSpacing: 1.2),
        ),
      );

  Widget _bottomBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.pageX, AppSpace.sm, AppSpace.pageX, AppSpace.sm),
        decoration: const BoxDecoration(
          color: Color(0xF0FBF8F3),
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(
              _saving ? '保存中…' : (_isEdit ? '保存修改' : '保存这条记录'),
            ),
          ),
        ),
      ),
    );
  }
}
