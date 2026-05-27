import 'dart:io';

import 'package:flutter/material.dart';

/// 全屏图片画廊查看器
///
/// 放支持：
/// - 多图左右滑动（PageView）
/// - 双指缩放（InteractiveViewer）
/// - 双击切换 1x/3x 缩放
/// - 页码指示器
/// - 关闭按钮
class ImageGalleryViewer extends StatefulWidget {
  final List<String> imagePaths;
  final int initialIndex;

  const ImageGalleryViewer({
    super.key,
    required this.imagePaths,
    this.initialIndex = 0,
  });

  @override
  State<ImageGalleryViewer> createState() => _ImageGalleryViewerState();
}

class _ImageGalleryViewerState extends State<ImageGalleryViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: widget.imagePaths.length > 1
            ? Text(
                '${_currentIndex + 1} / ${widget.imagePaths.length}',
                style: const TextStyle(fontSize: 14, color: Colors.white70),
              )
            : null,
        centerTitle: true,
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.imagePaths.length,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (context, index) {
          return _ZoomableImage(imagePath: widget.imagePaths[index]);
        },
      ),
    );
  }
}

/// 可缩放的单张图片
///
/// 支持双指缩放和双击切换 1x/3x。
class _ZoomableImage extends StatefulWidget {
  final String imagePath;

  const _ZoomableImage({required this.imagePath});

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> {
  final TransformationController _controller = TransformationController();
  TapDownDetails? _doubleTapDetails;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (d) => _doubleTapDetails = d,
      onDoubleTap: () {
        if (_controller.value != Matrix4.identity()) {
          _controller.value = Matrix4.identity();
        } else {
          final pos = _doubleTapDetails!.localPosition;
          _controller.value = Matrix4.identity()
            ..translateByDouble(-pos.dx * 2, -pos.dy * 2, 0, 1)
            ..scaleByDouble(3.0, 3.0, 3.0, 1);
        }
      },
      child: InteractiveViewer(
        transformationController: _controller,
        maxScale: 5.0,
        minScale: 0.8,
        clipBehavior: Clip.none,
        child: Center(
          child: Image.file(
            File(widget.imagePath),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return const Center(
                child: Icon(
                  Icons.broken_image,
                  size: 48,
                  color: Colors.white54,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
