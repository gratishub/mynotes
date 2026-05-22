import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../models/post.dart';
import '../models/image_meta.dart';
import '../services/image_processor.dart';
import '../providers.dart';

/// 发布页 - 撰写新日记
///
/// 页面结构：
/// ┌─────────────────────────┐
/// │  AppBar: 发布日记        │
/// ├─────────────────────────┤
/// │                         │
/// │  [文本输入框]            │
/// │  (多行，自由书写)         │
/// │                         │
/// ├─────────────────────────┤
/// │  [选中的图片网格预览]     │
/// │  [📷] [+] 按钮          │
/// ├─────────────────────────┤
/// │  [  ✏️ 发布  ]          │
/// └─────────────────────────┘
class PublishScreen extends ConsumerStatefulWidget {
  const PublishScreen({super.key});

  @override
  ConsumerState<PublishScreen> createState() => _PublishScreenState();
}

class _PublishScreenState extends ConsumerState<PublishScreen> {
  /// 日记文本控制器
  final _contentController = TextEditingController();

  /// 用户从相册选中的原始图片列表（尚未压缩）
  final List<XFile> _selectedImages = [];

  /// 发布状态：true 表示正在压缩图片和写入数据库
  bool _isPublishing = false;

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  // ============================================================
  // 图片选取
  // ============================================================

  /// 打开系统相册，允许用户多选图片
  ///
  /// image_picker 通过平台通道调用系统原生相册选择器：
  /// - Android：打开系统相册（需要 READ_EXTERNAL_STORAGE 权限）
  /// - iOS：打开 PHPicker（无需额外权限）
  ///
  /// 用户选择的图片以 XFile 列表返回。
  /// XFile 是跨平台的抽象，封装了文件路径和字节流。
  Future<void> _pickImages() async {
    try {
      final picker = ImagePicker();

      // pickMultiImage 允许用户从相册中多选图片
      final images = await picker.pickMultiImage(
        imageQuality: 100,      // 暂不压缩，后续由 ImageProcessor 统一处理
        maxWidth: 400,          // 限制原始尺寸，减少 picker 阶段的内存消耗
      );

      if (images.isNotEmpty) {
        setState(() {
          _selectedImages.addAll(images);
        });
      }
    } catch (e) {
      _showError('选取图片失败: $e');
    }
  }

  /// 从选中列表中移除某张图片
  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  // ============================================================
  // 发布
  // ============================================================

  /// 发布日记：压缩图片 → 构建实体 → 存入数据库
  ///
  /// 步骤：
  /// 1. 校验输入（至少要有文本或图片）
  /// 2. 设置 isPublishing = true，显示 loading
  /// 3. 使用 ImageProcessor 逐个压缩图片
  /// 4. 构建 Post 和 ImageMeta 对象
  /// 5. 通过 ObjectBoxStore 写入数据库
  /// 6. 清空表单，提示成功
  Future<void> _publish() async {
    final content = _contentController.text.trim();

    // 校验：至少要有文本内容或图片
    if (content.isEmpty && _selectedImages.isEmpty) {
      _showError('请至少输入一些文字或添加一张图片');
      return;
    }

    setState(() {
      _isPublishing = true;
    });

    try {
      final store = ref.read(objectBoxProvider);

      // 1. 构建 Post 对象
      //    UUID 使用 uuid 包生成，确保全局唯一
      final post = Post(
        uuid: const Uuid().v4(),
        content: content,
        updatedAt: DateTime.now(),
        isDeleted: false,
      );

      // 2. 压缩图片并收集路径
      //    按顺序处理，因为操作文件系统，并行处理可能导致资源竞争。
      final processedPaths = <String>[];
      for (final image in _selectedImages) {
        final savedPath = await ImageProcessor.process(image);
        processedPaths.add(savedPath);
      }

      // 3. 写入数据库
      //    先 put post，获取分配的 ID，然后创建 ImageMeta 并关联。
      //    ObjectBox 的 put 方法返回分配的主键 ID。
      final postId = store.putPost(post);

      // 刷新 post 对象，使其包含数据库分配的最新状态
      final savedPost = store.getPost(postId)!;

      for (final path in processedPaths) {
        final imageMeta = ImageMeta(localPath: path);

        // 建立关联：ImageMeta → Post
        imageMeta.post.target = savedPost;

        // 存入 ImageMeta
        store.imageBox.put(imageMeta);
      }

      // 4. 清空表单
      _contentController.clear();
      setState(() {
        _selectedImages.clear();
        _isPublishing = false;
      });

      // 5. 提示成功
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('日记发布成功！')));
      }
    } catch (e) {
      setState(() {
        _isPublishing = false;
      });
      _showError('发布失败: $e');
    }
  }

  /// 显示错误提示
  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('写日记'),
        actions: [
          // 发布按钮放在 AppBar 右侧
          _isPublishing
              ? const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _publish,
                  tooltip: '发布',
                ),
        ],
      ),
      body: Column(
        children: [
          // --- 文本输入区域 ---
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _contentController,
                maxLines: null,        // 无限行数，自由书写
                expands: true,         // 填满 Expanded 的空间
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: '今天发生了什么……',
                  border: InputBorder.none, // 无边框，干净
                ),
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),

          // --- 底部操作栏 ---
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 已选图片横向预览
                if (_selectedImages.isNotEmpty) ...[
                  SizedBox(
                    height: 80,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _selectedImages.length,
                      itemBuilder: (context, index) {
                        return _buildImagePreview(index);
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // 操作按钮行
                Row(
                  children: [
                    // 选取图片按钮
                    OutlinedButton.icon(
                      icon: const Icon(Icons.image),
                      label: Text(
                        _selectedImages.isEmpty
                            ? '添加图片'
                            : '添加图片 (${_selectedImages.length})',
                      ),
                      onPressed:
                          _isPublishing ? null : _pickImages,
                    ),
                    const Spacer(),
                    // 发布按钮
                    FilledButton.icon(
                      icon: const Icon(Icons.edit),
                      label: const Text('发布'),
                      onPressed: _isPublishing ? null : _publish,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建单张图片的缩略图预览卡片
  Widget _buildImagePreview(int index) {
    return Stack(
      children: [
        // 图片预览（使用 XFile.path 加载本地图片）
        Container(
          width: 72,
          height: 72,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            image: DecorationImage(
              image: FileImage(File(_selectedImages[index].path)),
              fit: BoxFit.cover,
            ),
          ),
        ),
        // 删除按钮（右上角）
        Positioned(
          top: 0,
          right: 4,
          child: GestureDetector(
            onTap: () => _removeImage(index),
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 16, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}