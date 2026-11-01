import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme.dart';
import '../widgets/common.dart';

/// 图库选择页的返回结果。
///
/// [paths] 非空表示选中了文件；
/// [fallbackToSystem] 为 true 表示用户希望改用系统选择器（权限被拒时的兜底）。
class GalleryPickResult {
  final List<String> paths;
  final bool fallbackToSystem;

  const GalleryPickResult.picked(this.paths) : fallbackToSystem = false;
  const GalleryPickResult.fallback()
      : paths = const [],
        fallbackToSystem = true;
}

/// 内置图库选择器：读取系统相册、自绘网格。
///
/// 之所以不用 image_picker 的系统选择器：国产 ROM 普遍缺少 Google 的
/// Photo Picker 模块，`ACTION_GET_CONTENT` 会回退成文件管理器界面。
class GalleryPickerPage extends StatefulWidget {
  final bool videoOnly;
  final int maxCount;
  final String title;

  const GalleryPickerPage({
    super.key,
    this.videoOnly = false,
    this.maxCount = 9,
    this.title = '照片',
  });

  @override
  State<GalleryPickerPage> createState() => _GalleryPickerPageState();
}

enum _Phase { loading, denied, empty, ready }

class _GalleryPickerPageState extends State<GalleryPickerPage> {
  final _scroll = ScrollController();
  final _selected = <AssetEntity>[];

  _Phase _phase = _Phase.loading;
  List<AssetPathEntity> _albums = const [];
  AssetPathEntity? _album;
  final _assets = <AssetEntity>[];

  int _page = 0;
  bool _hasMore = true;
  bool _loadingMore = false;

  RequestType get _type =>
      widget.videoOnly ? RequestType.video : RequestType.image;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
        _loadMore();
      }
    });
    _init();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final ps = await PhotoManager.requestPermissionExtend();
    if (!mounted) return;
    if (!ps.isAuth) {
      setState(() => _phase = _Phase.denied);
      return;
    }
    final albums = await PhotoManager.getAssetPathList(
      type: _type,
      onlyAll: true,
    );
    if (!mounted) return;
    if (albums.isEmpty) {
      setState(() => _phase = _Phase.empty);
      return;
    }
    _albums = albums;
    _album = albums.first;
    await _loadMore(reset: true);
  }

  Future<void> _loadMore({bool reset = false}) async {
    if (_loadingMore || (!_hasMore && !reset)) return;
    if (_album == null) return;
    setState(() => _loadingMore = true);

    if (reset) {
      _page = 0;
      _hasMore = true;
      _assets.clear();
    }

    final list = await _album!.getAssetListPaged(page: _page, size: 60);
    if (!mounted) return;
    setState(() {
      _assets.addAll(list);
      _page += 1;
      _hasMore = list.length == 60;
      _loadingMore = false;
      _phase = _assets.isEmpty ? _Phase.empty : _Phase.ready;
    });
  }

  Future<void> _switchAlbum() async {
    if (_albums.length <= 1) return;
    final picked = await showModalBottomSheet<AssetPathEntity>(
      context: context,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: _albums.length,
          itemBuilder: (_, i) {
            final a = _albums[i];
            final on = a.id == _album?.id;
            return ListTile(
              title: Text(
                a.name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                  color: on ? AppColors.clay : AppColors.ink,
                ),
              ),
              trailing: on
                  ? const Icon(Icons.check, size: 18, color: AppColors.clay)
                  : null,
              onTap: () => Navigator.pop(ctx, a),
            );
          },
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _album = picked;
      _phase = _Phase.loading;
    });
    await _loadMore(reset: true);
  }

  void _toggle(AssetEntity a) {
    final i = _selected.indexWhere((e) => e.id == a.id);
    if (i >= 0) {
      setState(() => _selected.removeAt(i));
      return;
    }
    if (widget.maxCount == 1) {
      setState(() {
        _selected
          ..clear()
          ..add(a);
      });
      _done();
      return;
    }
    if (_selected.length >= widget.maxCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('最多选择 ${widget.maxCount} 个')),
      );
      return;
    }
    setState(() => _selected.add(a));
  }

  Future<void> _done() async {
    if (_selected.isEmpty) return;
    final paths = <String>[];
    for (final a in _selected) {
      final f = await a.file;
      if (f != null) paths.add(f.path);
    }
    if (!mounted) return;
    if (paths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('读取文件失败，请换一张试试')),
      );
      return;
    }
    Navigator.pop(context, GalleryPickResult.picked(paths));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(child: _body()),
            if (_phase == _Phase.ready) _albumBar(),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    final n = _selected.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 14, 10),
      child: Row(
        children: [
          AppIconButton(
            icon: Icons.close,
            size: 19,
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Text(
              widget.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
          SizedBox(
            width: 62,
            child: n == 0
                ? const SizedBox()
                : GestureDetector(
                    onTap: _done,
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                      '完成 ($n)',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.clay,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.loading:
        return const Center(
          child: CircularProgressIndicator(
              color: AppColors.clay, strokeWidth: 2.4),
        );
      case _Phase.denied:
        return _deniedView();
      case _Phase.empty:
        return EmptyState(
          icon: Icons.photo_library_outlined,
          title: widget.videoOnly ? '相册里还没有视频' : '相册里还没有照片',
          subtitle: '拍一张或换个相册看看',
        );
      case _Phase.ready:
        return GridView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 3,
            crossAxisSpacing: 3,
          ),
          itemCount: _assets.length + (_hasMore ? 1 : 0),
          itemBuilder: (ctx, i) {
            if (i >= _assets.length) {
              return const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.ink3),
                ),
              );
            }
            return _tile(_assets[i]);
          },
        );
    }
  }

  Widget _deniedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline,
                size: 48, color: AppColors.lineStrong),
            const SizedBox(height: AppSpace.md),
            const Text(
              '没有相册访问权限',
              style: TextStyle(fontSize: 14, color: AppColors.ink2),
            ),
            const SizedBox(height: 6),
            const Text(
              '需要读取相册才能显示图片列表',
              textAlign: TextAlign.center,
              style: AppText.caption,
            ),
            const SizedBox(height: AppSpace.lg),
            const FilledButton(
              onPressed: PhotoManager.openSetting,
              child: Text('去开启权限'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, const GalleryPickResult.fallback()),
              child: const Text('改用系统选择器'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _albumBar() {
    return GestureDetector(
      onTap: _switchAlbum,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _album?.name ?? '最近项目',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, size: 15, color: AppColors.ink3),
          ],
        ),
      ),
    );
  }

  Widget _tile(AssetEntity a) {
    final idx = _selected.indexWhere((e) => e.id == a.id);
    final on = idx >= 0;
    return GestureDetector(
      onTap: () => _toggle(a),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _Thumb(asset: a),
          if (on)
            Container(
              decoration: BoxDecoration(
                color: AppColors.clay.withValues(alpha: 0.18),
                border: Border.all(color: AppColors.clay, width: 2.5),
              ),
            ),
          // 序号角标
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              width: 19,
              height: 19,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color:
                    on ? AppColors.clay : Colors.black.withValues(alpha: 0.18),
                shape: BoxShape.circle,
                border: Border.all(
                  color:
                      on ? Colors.white : Colors.white.withValues(alpha: 0.9),
                  width: 1.4,
                ),
              ),
              child: on
                  ? Text(
                      '${idx + 1}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
          ),
          if (widget.videoOnly)
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  a.videoDuration.toHHMMSS(),
                  style: const TextStyle(fontSize: 9, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

extension on Duration {
  String toHHMMSS() {
    final m = inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// 缩略图：异步取 300px 缩略图，失败时显示占位块。
class _Thumb extends StatefulWidget {
  final AssetEntity asset;

  const _Thumb({required this.asset});

  @override
  State<_Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<_Thumb> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = await widget.asset.thumbnailDataWithSize(
      const ThumbnailSize.square(300),
      quality: 82,
    );
    if (!mounted) return;
    setState(() => _bytes = b);
  }

  @override
  Widget build(BuildContext context) {
    final b = _bytes;
    if (b == null) {
      return Container(color: AppColors.clayLight);
    }
    return Image.memory(b, fit: BoxFit.cover, gaplessPlayback: true);
  }
}
