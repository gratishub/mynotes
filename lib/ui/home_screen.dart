import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../models/post.dart';
import '../models/image_meta.dart';
import '../providers.dart';
import 'publish_screen.dart';

/// 主界面 - 展示已发布的日记
///
/// 支持两种视图模式，通过 AppBar 按钮切换：
/// - Feed 视图（默认）：卡片流，展示文字 + 图片缩略图
/// - Grid 视图：图片瀑布流，纯视觉浏览
///
/// 切换动画由 AnimatedSwitcher 驱动，使用淡入淡出过渡。
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// 当前视图模式
  /// true = Feed 卡片流
  /// false = Grid 瀑布流
  bool _isFeedView = true;

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(objectBoxProvider);

    // 查询所有非删除状态的帖子，按更新时间降序
    // 每次 _refreshKey 变化时重新查询（用于发布后自动刷新）
    final posts = store.getActivePosts();

    return Scaffold(
      appBar: AppBar(
        title: const Text('mynotes'),
        actions: [
          // 视图切换按钮
          IconButton(
            icon: Icon(_isFeedView ? Icons.grid_view : Icons.view_list),
            tooltip: _isFeedView ? '切换到网格视图' : '切换到列表视图',
            onPressed: () {
              setState(() {
                _isFeedView = !_isFeedView;
              });
            },
          ),
        ],
      ),
      // 使用 AnimatedSwitcher 包裹主内容区域，实现视图切换动画
      // duration 控制动画时长，switchInCurve/switchOutCurve 控制缓动曲线
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeInOut,
        transitionBuilder: (child, animation) {
          // 淡入淡出效果
          return FadeTransition(opacity: animation, child: child);
        },
        child: _isFeedView
            ? _buildFeedView(posts, key: const ValueKey('feed'))
            : _buildGridView(posts, key: const ValueKey('grid')),
      ),
      // 右下角悬浮按钮 → 跳转发布页
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          // 导航到发布页，返回后强制刷新主界面
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PublishScreen()),
          );
          // 从发布页返回后，setState 触发 build 方法重新执行
          // getActivePosts() 会获取最新的数据
          setState(() {});
        },
        tooltip: '写日记',
        child: const Icon(Icons.edit),
      ),
    );
  }

  // ============================================================
  // Feed 视图 - 卡片列表
  // ============================================================

  /// 构建卡片列表视图
  ///
  /// ListView.builder 按需构建子组件，即使是数百条记录也不会造成性能问题。
  /// 每个卡片展示一篇日记的文本内容 + 图片缩略图 + 时间戳。
  Widget _buildFeedView(List<Post> posts, {Key? key}) {
    if (posts.isEmpty) {
      return _buildEmptyState(key: key);
    }

    return ListView.builder(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: posts.length,
      // 使用 prototypeItem 优化滚动性能：Flutter 会用此组件估算每项高度
      prototypeItem: _buildFeedCard(posts.first),
      itemBuilder: (context, index) {
        return _buildFeedCard(posts[index]);
      },
    );
  }

  /// 构建单张日记卡片
  Widget _buildFeedCard(Post post) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 日记正文 —— 限制显示行数，避免卡片过长
            if (post.content.isNotEmpty)
              Text(
                post.content,
                style: theme.textTheme.bodyLarge,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              )
            else
              Text(
                '(空白日记)',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(100),
                ),
              ),

            // 图片缩略图横向滚动行
            if (post.images.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildImageRow(post.images.toList()),
            ],

            // 底部信息栏：时间戳 + 标签
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 14,
                  color: theme.colorScheme.onSurface.withAlpha(120),
                ),
                const SizedBox(width: 4),
                Text(
                  _formatTime(post.updatedAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(120),
                  ),
                ),
                const Spacer(),
                // 标签
                if (post.tags.isNotEmpty)
                  ...post.tags.map(
                    (tag) => Container(
                      margin: const EdgeInsets.only(left: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        tag.name,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建图片横向滚动行
  ///
  /// 使用 cacheWidth: 400 限制解码后的图片尺寸，降低内存占用。
  /// 400px 的缓存宽度远大于屏幕上实际显示的缩略图尺寸，
  /// 因此不会损失画质，但内存占用从原图的数十 MB 降至数十 KB 级别。
  Widget _buildImageRow(List<ImageMeta> images) {
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.file(
              File(images[index].localPath),
              width: 100,
              height: 100,
              fit: BoxFit.cover,
              cacheWidth: 400,        // 关键：限制解码缓存尺寸，防 OOM
              errorBuilder: (context, error, stackTrace) {
                // 图片文件可能已被外部删除
                return Container(
                  width: 100,
                  height: 100,
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.broken_image, color: Colors.grey),
                );
              },
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  // Grid 视图 - 瀑布流
  // ============================================================

  /// 构建图片瀑布流视图
  ///
  /// MasonryGridView 实现类似 Pinterest 的瀑布流布局。
  /// 每张图片高度不同，自动填充间隙，形成错落有致的视觉效果。
  Widget _buildGridView(List<Post> posts, {Key? key}) {
    // 收集所有帖子中的所有图片
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
      crossAxisCount: 2,                   // 两列瀑布流
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      padding: const EdgeInsets.all(8),
      itemCount: allImages.length,
      itemBuilder: (context, index) {
        final (image, post) = allImages[index];

        // 使用 Image 直接加载本地文件
        // cacheWidth: 400 确保即使是高分图片也不会占用过多内存
        return GestureDetector(
          onTap: () {
            // 点击图片可以展示帖子详情（后续阶段实现）
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  post.content.isNotEmpty ? post.content : '(空白日记)',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(image.localPath),
              fit: BoxFit.cover,
              cacheWidth: 400,             // 防 OOM 的核心配置
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  height: 150,
                  color: Colors.grey.shade200,
                  child: const Center(
                    child: Icon(Icons.broken_image, color: Colors.grey),
                  ),
                );
              },
              // 显示加载中的占位色
              frameBuilder:
                  (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded) return child;
                if (frame == null) {
                  return Container(
                    color: Colors.grey.shade100,
                  );
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

  /// 数据为空时的占位组件
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
                    color:
                        Theme.of(context).colorScheme.onSurface.withAlpha(120),
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击右下角按钮开始写日记',
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
  // 工具方法
  // ============================================================

  /// 格式化时间戳为简短显示
  ///
  /// 今天：显示 "14:30"
  /// 昨天：显示 "昨天 14:30"
  /// 今年内：显示 "3月15日 14:30"
  /// 更早：显示 "2025/3/15"
  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final date = DateTime(dt.year, dt.month, dt.day);

    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');

    if (date == today) {
      return '$hour:$minute';
    } else if (date == yesterday) {
      return '昨天 $hour:$minute';
    } else if (dt.year == now.year) {
      return '${dt.month}月${dt.day}日 $hour:$minute';
    } else {
      return '${dt.year}/${dt.month}/${dt.day}';
    }
  }
}