import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/post.dart';
import '../providers.dart';
import '../services/objectbox_store.dart';
import 'image_gallery_viewer.dart';
import 'publish_screen.dart';

/// 日记预览页面（只读模式）
///
/// 从首页卡片点击进入，展示完整日记内容。
/// 支持查看 Markdown 渲染、图片画廊、标签。
/// 可跳转编辑页面。
class PostPreviewScreen extends ConsumerWidget {
  final Post post;

  const PostPreviewScreen({super.key, required this.post});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final images = post.images.toList();
    final tags = post.tags.toList();
    final hasContent = post.content.trim().isNotEmpty;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF3A3A3A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '编辑',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PublishScreen(post: post),
                ),
              );
              // 编辑返回后刷新首页数据
              ref.invalidate(activePostsProvider);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              if (value == 'delete') _confirmDelete(context, ref);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline_rounded, size: 20, color: Colors.red),
                    SizedBox(width: 8),
                    Text('删除', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ——— 日期 ———
            Text(
              _formatDate(post.updatedAt),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 12),

            // ——— 标签 ———
            if (tags.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: tags.map((tag) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9472).withAlpha(20),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      tag.name,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFFF9472),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],

            // ——— Markdown 内容 ———
            if (hasContent)
              MarkdownBody(
                data: post.content,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(
                    fontSize: 15,
                    height: 1.8,
                    color: Color(0xFF3A3A3A),
                  ),
                  h1: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2A2A2A),
                  ),
                  h2: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2A2A2A),
                  ),
                  h3: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2A2A2A),
                  ),
                  code: TextStyle(
                    fontSize: 13,
                    backgroundColor: Colors.grey.shade100,
                    color: const Color(0xFF3A3A3A),
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  blockquoteDecoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: theme.colorScheme.primary.withAlpha(100),
                        width: 3,
                      ),
                    ),
                  ),
                  blockquotePadding:
                      const EdgeInsets.only(left: 12, top: 4, bottom: 4),
                ),
              ),

            // ——— 图片网格 ———
            if (images.isNotEmpty) ...[
              if (hasContent) const SizedBox(height: 16),
              _buildImageGrid(context, images, screenWidth),
            ],

            // ——— 字数统计 ———
            const SizedBox(height: 24),
            Text(
              '${post.content.length} 字',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageGrid(
      BuildContext context, List<dynamic> images, double screenWidth) {
    if (images.length == 1) {
      final path = (images[0] as dynamic).localPath as String;
      return GestureDetector(
        onTap: () => _openGallery(context, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.file(
            File(path),
            width: double.infinity,
            height: 240,
            fit: BoxFit.cover,
            cacheWidth: 800,
            errorBuilder: (context, error, stackTrace) => Container(
              height: 240,
              color: Colors.grey.shade200,
              child: const Icon(Icons.broken_image, color: Colors.grey),
            ),
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: images.length == 2 ? 2 : 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: images.length.clamp(0, 9),
      itemBuilder: (context, index) {
        final path = (images[index] as dynamic).localPath as String;
        return GestureDetector(
          onTap: () => _openGallery(context, index),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(path),
              fit: BoxFit.cover,
              cacheWidth: 400,
              errorBuilder: (context, error, stackTrace) => Container(
                color: Colors.grey.shade200,
                child: const Icon(Icons.broken_image,
                    color: Colors.grey, size: 20),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openGallery(BuildContext context, int index) {
    final paths = post.images.map((img) => img.localPath).toList();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImageGalleryViewer(
          imagePaths: paths,
          initialIndex: index,
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除日记'),
        content: const Text('确定要删除这篇日记吗？删除后可在回收站恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              ObjectBoxStore.instance.softDeletePost(post.id);
              ref.invalidate(activePostsProvider);
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final y = date.year;
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    final weekDay = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final wd = weekDay[date.weekday - 1];
    return '$y年$m月$d日 $wd $hh:$mm';
  }
}
