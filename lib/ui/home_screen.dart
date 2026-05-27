import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/post.dart';
import '../models/image_meta.dart';
import '../providers.dart';
import '../services/export_service.dart';
import 'export_filter_sheet.dart';
import 'publish_screen.dart';
import 'lan_sync_screen.dart';
import 'statistics_screen.dart';
import 'tags_screen.dart';
import 'package:share_plus/share_plus.dart';

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
  bool _isCalendarExpanded = false;
  DateTime? _selectedDate;
  String? _selectedTagFilter;
  late DateTime _calendarMonth;
  Set<int> _datesWithPosts = {};
  static const _weekDays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  @override
  void initState() {
    super.initState();
    _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  }

  @override
  Widget build(BuildContext context) {
    final postsAsync = ref.watch(activePostsProvider);

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: _buildCalendarPanel(),
                  crossFadeState: _isCalendarExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 300),
                  sizeCurve: Curves.easeInOut,
                ),
                Expanded(
                  child: postsAsync.when(
                    data: (allPosts) {
                      final posts = _filterPosts(allPosts);

                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        switchInCurve: Curves.easeInOut,
                        switchOutCurve: Curves.easeInOut,
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                              opacity: animation, child: child);
                        },
                        child: _isFeedView
                            ? _buildFeedView(posts, key: const ValueKey('feed'))
                            : _buildGridView(
                                posts, key: const ValueKey('grid')),
                      );
                    },
                    loading: () => const Center(
                      child: CircularProgressIndicator(),
                    ),
                    error: (err, _) => const Center(
                      child: Text('加载失败',
                          style: TextStyle(color: Colors.grey)),
                    ),
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

  /// 根据当前筛选条件过滤日记
  List<Post> _filterPosts(List<Post> allPosts) {
    var result = allPosts;

    // 日期筛选
    if (_selectedDate != null) {
      result = result.where((p) =>
          p.updatedAt.year == _selectedDate!.year &&
          p.updatedAt.month == _selectedDate!.month &&
          p.updatedAt.day == _selectedDate!.day).toList();
    }

    // 标签筛选
    if (_selectedTagFilter != null) {
      result = result
          .where((p) => p.tags.any((t) => t.name == _selectedTagFilter))
          .toList();
    }

    return result;
  }

  // ============================================================
  // 头部 — 日期 + 天气占位 + 视图切换
  // ============================================================

  Widget _buildHeader() {
    final now = DateTime.now();
    String dateStr;
    if (_selectedDate != null) {
      final weekDay = _weekDays[_selectedDate!.weekday - 1];
      dateStr = '${_selectedDate!.month}月${_selectedDate!.day}日 $weekDay';
    } else {
      final weekDay = _weekDays[now.weekday - 1];
      dateStr = '${now.month}月${now.day}日 $weekDay';
    }

    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 8, top: 8, bottom: 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: _toggleCalendar,
            child: Text(
              dateStr,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3A3A3A),
              ),
            ),
          ),
          const Spacer(),
          if (_selectedDate != null || _selectedTagFilter != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: GestureDetector(
                onTap: _onClearFilter,
                child: Text(
                  _selectedTagFilter != null ? '清除标签筛选' : '清除筛选',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          IconButton(
            icon: Icon(
              _isCalendarExpanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.calendar_month_outlined,
              size: 20,
            ),
            color: _isCalendarExpanded
                ? Theme.of(context).colorScheme.primary
                : const Color(0xFF3A3A3A),
            onPressed: _toggleCalendar,
          ),
          IconButton(
            icon: const Icon(Icons.lan_outlined, size: 20),
            color: const Color(0xFF3A3A3A),
            tooltip: '局域网同步',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LanSyncScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.archive_outlined, size: 20),
            color: const Color(0xFF3A3A3A),
            tooltip: '导出日记',
            onPressed: _exportDiary,
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
  }

  /// 导出日记为 ZIP 并唤起系统分享
  Future<void> _exportDiary() async {
    // ——— 弹出筛选面板，等待用户确认 ———
    final filteredPosts = await showModalBottomSheet<List<Post>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const ExportFilterSheet(),
    );

    // 用户取消或没有符合条件的日记
    if (filteredPosts == null || filteredPosts.isEmpty) return;

    // ——— Loading 弹窗 ———
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 36, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  '正在导出…',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF3A3A3A),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final zipPath =
          await ExportService.exportToZip(filteredPosts);

      if (!mounted) return;
      // 关闭 Loading 弹窗
      Navigator.of(context).pop();

      // 唤起系统分享面板
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(zipPath)],
          text: '我的相册日记备份',
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('导出成功'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      // 关闭 Loading 弹窗
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导出失败：$e'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ============================================================
  // Feed 视图 — 卡片流
  // ============================================================

  Widget _buildFeedView(List<Post> posts, {Key? key}) {
    if (posts.isEmpty) {
      return _buildEmptyState(
        key: key,
        message: _selectedDate != null ? '这一天处于记忆的空白，去写一篇吧～' : '还没有日记',
      );
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

            // ——— 标签区域 ———
            if (post.tags.isNotEmpty) ...[
              const SizedBox(height: 14),
              SizedBox(
                height: 26,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: post.tags.length > 3 ? 4 : post.tags.length,
                  separatorBuilder: (context, a) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    if (index == 3) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9472).withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '+${post.tags.length - 3}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFFF9472),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    }
                    final tag = post.tags.toList()[index];
                    return GestureDetector(
                      onTap: () => _toggleTagFilter(tag.name),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9472).withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          tag.name,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFFF9472),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
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
      return _buildEmptyState(
        key: key,
        message: _selectedDate != null ? '这一天还没有图片记忆' : '暂无图片',
      );
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
  // 日历时光隧道 — 可折叠年月面板
  // ============================================================

  /// 展开/收起日历
  void _toggleCalendar() {
    setState(() {
      _isCalendarExpanded = !_isCalendarExpanded;
    });
    if (_isCalendarExpanded) {
      _fetchDatesWithPosts();
    }
  }

  /// 查询当前显示月份中有日记的日期
  void _fetchDatesWithPosts() {
    final store = ref.read(objectBoxProvider);
    final days = store.getDaysWithPostsInMonth(
      _calendarMonth.year,
      _calendarMonth.month,
    );
    setState(() {
      _datesWithPosts = days.toSet();
    });
  }

  /// 上一个月
  void _onPreviousMonth() {
    setState(() {
      _calendarMonth =
          DateTime(_calendarMonth.year, _calendarMonth.month - 1, 1);
    });
    _fetchDatesWithPosts();
  }

  /// 下一个月
  void _onNextMonth() {
    setState(() {
      _calendarMonth =
          DateTime(_calendarMonth.year, _calendarMonth.month + 1, 1);
    });
    _fetchDatesWithPosts();
  }

  /// 点击某一天
  void _onDayTap(int day) {
    final date = DateTime(_calendarMonth.year, _calendarMonth.month, day);
    setState(() {
      if (_selectedDate != null &&
          _selectedDate!.year == date.year &&
          _selectedDate!.month == date.month &&
          _selectedDate!.day == date.day) {
        _selectedDate = null; // 再次点击同一天取消筛选
      } else {
        _selectedDate = date;
      }
    });
  }

  /// 清除日期筛选
  void _onClearFilter() {
    setState(() {
      _selectedDate = null;
      _selectedTagFilter = null;
    });
  }

  /// 切换标签筛选
  void _toggleTagFilter(String tagName) {
    setState(() {
      if (_selectedTagFilter == tagName) {
        _selectedTagFilter = null; // 再次点击取消筛选
      } else {
        _selectedTagFilter = tagName;
        _selectedDate = null; // 切换到标签筛选时清除日期筛选
      }
    });
  }

  /// 当前显示月份中的某天是否为今天
  bool _isToday(int day) {
    final now = DateTime.now();
    return now.year == _calendarMonth.year &&
        now.month == _calendarMonth.month &&
        now.day == day;
  }

  /// 日历面板
  Widget _buildCalendarPanel() {
    final theme = Theme.of(context);
    final daysInMonth =
        DateTime(_calendarMonth.year, _calendarMonth.month + 1, 0).day;
    final firstWeekday =
        DateTime(_calendarMonth.year, _calendarMonth.month, 1).weekday -
            1; // Mon = 0

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F0EB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ——— 月份导航 ———
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 22),
                  color: const Color(0xFF3A3A3A),
                  onPressed: _onPreviousMonth,
                ),
                Text(
                  '${_calendarMonth.year}年${_calendarMonth.month}月',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3A3A3A),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 22),
                  color: const Color(0xFF3A3A3A),
                  onPressed: _onNextMonth,
                ),
              ],
            ),
          ),
          // ——— 星期行 ———
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Row(
              children: ['一', '二', '三', '四', '五', '六', '日']
                  .map(
                    (day) => Expanded(
                      child: Center(
                        child: Text(
                          day,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurface.withAlpha(100),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          // ——— 日期网格 ———
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1.1,
              ),
              itemCount: 42,
              itemBuilder: (context, index) {
                final day = index - firstWeekday + 1;
                if (day < 1 || day > daysInMonth) {
                  return const SizedBox.shrink();
                }

                final isToday = _isToday(day);
                final isSelected = _selectedDate != null &&
                    _selectedDate!.year == _calendarMonth.year &&
                    _selectedDate!.month == _calendarMonth.month &&
                    _selectedDate!.day == day;
                final hasPost = _datesWithPosts.contains(day);

                return _buildDayCell(day, isToday, isSelected, hasPost);
              },
            ),
          ),
          // ——— 底部：回到今天 ———
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: TextButton(
              onPressed: () {
                setState(() {
                  _calendarMonth =
                      DateTime(DateTime.now().year, DateTime.now().month, 1);
                  _selectedDate = null;
                });
                _fetchDatesWithPosts();
              },
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('回到今天', style: TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  /// 单个日期格
  Widget _buildDayCell(int day, bool isToday, bool isSelected, bool hasPost) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => _onDayTap(day),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: isSelected
            ? BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              )
            : null,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$day',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                  color: isSelected
                      ? Colors.white
                      : isToday
                          ? theme.colorScheme.primary
                          : const Color(0xFF3A3A3A),
                ),
              ),
              if (hasPost)
                Container(
                  width: 4,
                  height: 4,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withAlpha(180)
                        : theme.colorScheme.primary.withAlpha(120),
                    shape: BoxShape.circle,
                  ),
                )
              else
                const SizedBox(height: 5),
            ],
          ),
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
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StatisticsScreen()),
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
              },
            ),
          ),
          _barIcon(Icons.local_offer_outlined, () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TagsScreen()),
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
