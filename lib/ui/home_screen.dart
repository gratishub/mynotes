import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/post.dart';
import '../models/image_meta.dart';
import '../providers.dart';
import 'publish_screen.dart';

/// 主界面 - 展示已发布的日记
///
/// 支持两种视图模式：
/// - Feed 视图（默认）：卡片流，展示文字 + 图片缩略图
/// - Grid 视图：图片瀑布流，纯视觉浏览
///
/// 底部胶囊栏常驻，点击中央编辑按钮跳转发布页。
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isFeedView = true;
  static const _weekDays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(objectBoxProvider);
    final posts = store.getActivePosts();

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeInOut,
                    switchOutCurve: Curves.easeInOut,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                    child: _isFeedView
                        ? _buildFeedView(posts, key: const ValueKey('feed'))
                        : _buildGridView(posts, key: const ValueKey('grid')),
                  ),
                ),
              ],
            ),
          ),
          // 悬浮胶囊底栏
          Positioned(
            left: 32,
            right: 32,
            bottom: MediaQuery.of(context).padding.bottom + 12,
            child: _buildCapsuleBar(),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 头部 — 日期 + 天气占位 + 视图切换
  // ============================================================

  Widget _buildHeader() {
    final now = DateTime.now();
    final weekDay = _weekDays[now.weekday - 1];
    final dateStr = '${now.month}月${now.day}日 $weekDay';

    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 8, top: 8, bottom: 4),
      child: Row(
        children: [
          Text(
            dateStr,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: Color(0xFF3A3A3A),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.wb_sunny_outlined, size: 20),
            color: const Color(0xFF3A3A3A),
            onPressed: () {},
          ),
          IconButton(
            icon: Icon(
              _isFeedView ? Icons.grid_view_rounded : Icons.view_list_rounded,
            ),
            color: const Color(0xFF3A3A3A),
            onPressed: () {
              setState(() => _isFeedView = !_isFeedView);
            },
          ),
        ],
      ),
    );
  }

  /// 打开帖子查看/编辑
  Future<void> _openPost(Post post) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PublishScreen(post: post)),
    );
    if (mounted) setState(() {});
  }

  // ============================================================
  // Feed 视图 — 卡片流
  // ============================================================

  Widget _buildFeedView(List<Post> posts, {Key? key}) {
    if (posts.isEmpty) {
      return _buildEmptyState(key: key);
    }

    return ListView.builder(
      key: key,
      padding: const EdgeInsets.only(top: 4, bottom: 100),
      itemCount: posts.length,
      itemBuilder: (context, index) => _buildFeedCard(posts[index]),
    );
  }

  /// 单张日记卡片 — 极简手账风格
  Widget _buildFeedCard(Post post) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final postDate = DateTime(
      post.updatedAt.year,
      post.updatedAt.month,
      post.updatedAt.day,
    );
    final wordCount = post.content.replaceAll(RegExp(r'\s'), '').length;

    // ---------- 时间格式化 ----------
    String timeStr;
    if (postDate == today) {
      timeStr =
          '${post.updatedAt.hour.toString().padLeft(2, '0')}:${post.updatedAt.minute.toString().padLeft(2, '0')}';
    } else if (postDate == today.subtract(const Duration(days: 1))) {
      timeStr =
          '昨天 ${post.updatedAt.hour.toString().padLeft(2, '0')}:${post.updatedAt.minute.toString().padLeft(2, '0')}';
    } else if (post.updatedAt.year == now.year) {
      timeStr = '${post.updatedAt.month}月${post.updatedAt.day}日';
    } else {
      timeStr =
          '${post.updatedAt.year}/${post.updatedAt.month}/${post.updatedAt.day}';
    }

    return GestureDetector(
      onTap: () => _openPost(post),
      child: Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ——— 右上角时间 ———
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(
                  Icons.access_time,
                  size: 11,
                  color: theme.colorScheme.onSurface.withAlpha(70),
                ),
                const SizedBox(width: 3),
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withAlpha(70),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ——— 正文（Markdown 渲染） ———
            if (post.content.isNotEmpty)
              SizedBox(
                width: double.infinity,
                child: Stack(
                  children: [
                    MarkdownBody(
                      data: post.content,
                      styleSheet: MarkdownStyleSheet(
                        p: theme.textTheme.bodyLarge?.copyWith(
                          height: 1.65,
                          color: const Color(0xFF3A3A3A),
                        ),
                        a: TextStyle(color: Theme.of(context).colorScheme.primary),
                        strong: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF3A3A3A),
                        ),
                        em: theme.textTheme.bodyLarge?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: const Color(0xFF3A3A3A),
                        ),
                        h1: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF3A3A3A),
                        ),
                        h2: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF3A3A3A),
                        ),
                        h3: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF3A3A3A),
                        ),
                        blockquote: theme.textTheme.bodyLarge?.copyWith(
                          color: const Color(0xFF888888),
                          fontStyle: FontStyle.italic,
                        ),
                        code: TextStyle(
                          backgroundColor: Colors.grey.shade100,
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                        listBullet: TextStyle(color: const Color(0xFF3A3A3A)),
                        horizontalRuleDecoration: BoxDecoration(
                          border: Border(top: BorderSide(color: Colors.grey.shade300)),
                        ),
                      ),
                    ),
                    // 渐变遮罩 — 内容超长时在底部渐变淡出
                    if (post.content.length > 150)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: 40,
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  theme.scaffoldBackgroundColor,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              )
            else
              Text(
                '(空白日记)',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(50),
                  fontStyle: FontStyle.italic,
                ),
              ),

            // ——— 图片区域 ———
            if (post.images.isNotEmpty) ...[
              const SizedBox(height: 14),
              _buildCardImages(post.images.toList()),
            ],

            const SizedBox(height: 14),

            // ——— 底部信息：字数 / 评论 ———
            Row(
              children: [
                Text(
                  '字数 $wordCount',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withAlpha(80),
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  '评论',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withAlpha(80),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// 卡片内的图片展示
  ///
  /// - 1 张：全宽展示，大圆角
  /// - 多张：三列网格（类九宫格），最多 9 张
  Widget _buildCardImages(List<ImageMeta> images) {
    if (images.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.file(
          File(images[0].localPath),
          width: double.infinity,
          height: 200,
          fit: BoxFit.cover,
          cacheWidth: 800,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              height: 200,
              color: Colors.grey.shade200,
              child: const Icon(Icons.broken_image, color: Colors.grey),
            );
          },
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: min(images.length, 9),
      itemBuilder: (context, index) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(images[index].localPath),
            fit: BoxFit.cover,
            cacheWidth: 300,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: Colors.grey.shade200,
                child: const Icon(
                  Icons.broken_image,
                  color: Colors.grey,
                  size: 20,
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ============================================================
  // Grid 视图 — 瀑布流
  // ============================================================

  Widget _buildGridView(List<Post> posts, {Key? key}) {
    final allImages = <(ImageMeta, Post)>[];
    for (final post in posts) {
      for (final image in post.images) {
        allImages.add((image, post));
      }
    }

    if (allImages.isEmpty) {
      return _buildEmptyState(key: key, message: '暂无图片');
    }

    return MasonryGridView.count(
      key: key,
      crossAxisCount: 2,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: allImages.length,
      itemBuilder: (context, index) {
        final (image, post) = allImages[index];

        return GestureDetector(
          onTap: () => _openPost(post),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(image.localPath),
              fit: BoxFit.cover,
              cacheWidth: 400,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  height: 150,
                  color: Colors.grey.shade200,
                  child: const Center(
                    child: Icon(Icons.broken_image, color: Colors.grey),
                  ),
                );
              },
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded) return child;
                if (frame == null) {
                  return Container(color: Colors.grey.shade100);
                }
                return child;
              },
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // 空状态
  // ============================================================

  Widget _buildEmptyState({Key? key, String message = '还没有日记'}) {
    return Center(
      key: key,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurface.withAlpha(60),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withAlpha(120),
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '记录生活中的点滴',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color:
                        Theme.of(context).colorScheme.onSurface.withAlpha(80),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // 底部胶囊栏 — 纯图标悬浮底栏
  // ============================================================

  Widget _buildCapsuleBar() {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _barIcon(Icons.bar_chart_rounded, () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('统计功能即将上线'),
                duration: Duration(seconds: 1),
              ),
            );
          }),
          _barIcon(Icons.photo_library_outlined, () {
            if (!_isFeedView) return;
            setState(() => _isFeedView = false);
          }),
          // 中央编辑按钮 — 暖色圆形
          Container(
            width: 40,
            height: 40,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: const BoxDecoration(
              color: Color(0xFFFF9472),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.edit_outlined, size: 20, color: Colors.white),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PublishScreen()),
                );
                setState(() {});
              },
            ),
          ),
          _barIcon(Icons.local_offer_outlined, () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('标签功能即将上线'),
                duration: Duration(seconds: 1),
              ),
            );
          }),
          _barIcon(Icons.more_horiz_rounded, () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('更多功能即将上线'),
                duration: Duration(seconds: 1),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _barIcon(IconData icon, VoidCallback onTap) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 22),
        color: const Color(0xFF3A3A3A),
        onPressed: onTap,
      ),
    );
  }
}
