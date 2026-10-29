import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../services/media_service.dart';

/// 全屏媒体浏览：支持多图左右滑动、双指缩放、保存到相册
class MediaViewerPage extends StatefulWidget {
  final List<String> imagePaths; // 相对路径
  final int initialIndex;
  const MediaViewerPage({
    super.key,
    required this.imagePaths,
    this.initialIndex = 0,
  });

  @override
  State<MediaViewerPage> createState() => _MediaViewerPageState();
}

class _MediaViewerPageState extends State<MediaViewerPage> {
  late int _index;
  final _pageController = PageController();
  List<String>? _resolved;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _saveCurrent() async {
    if (_resolved == null || _resolved!.isEmpty) return;
    final path = _resolved![_index];
    try {
      final saved = await MediaService.instance.saveToGallery(path);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已保存到相册: $saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<List<String>>(
        future: _resolveAll(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }
          _resolved = snap.data;
          final paths = snap.data!;
          return Stack(
            children: [
              PhotoViewGallery.builder(
                pageController: _pageController,
                itemCount: paths.length,
                onPageChanged: (i) => setState(() => _index = i),
                builder: (context, i) => PhotoViewGalleryPageOptions(
                  imageProvider: FileImage(File(paths[i])),
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.covered * 3,
                  heroAttributes: PhotoViewHeroAttributes(tag: 'media_$i'),
                ),
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 12,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black38,
                  ),
                ),
              ),
              if (paths.length > 1)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_index + 1} / ${paths.length}',
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ),
                  ),
                ),
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 20,
                left: 0,
                right: 0,
                child: Center(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF333333),
                    ),
                    onPressed: _saveCurrent,
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('保存到相册'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<List<String>> _resolveAll() async {
    final list = <String>[];
    for (final rel in widget.imagePaths) {
      list.add(await MediaService.instance.absolutePathOf(rel));
    }
    return list;
  }
}
