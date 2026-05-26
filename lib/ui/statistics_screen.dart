import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers.dart';

/// 统计页面
///
/// 展示日记数据的汇总统计信息：
/// - 累计日记篇数
/// - 累计字数
/// - 累计图片数
/// - 记录天数跨度
class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(activePostsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('统计'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: postsAsync.when(
        data: (posts) {
          // 累计篇数
          final totalPosts = posts.length;

          // 累计字数（去除空白字符）
          final totalChars = posts.fold<int>(
            0,
            (sum, post) => sum + post.content.replaceAll(RegExp(r'\s'), '').length,
          );

          // 累计图片数
          final totalImages = posts.fold<int>(
            0,
            (sum, post) => sum + post.images.length,
          );

          // 记录天数跨度
          final uniqueDays = <String>{};
          for (final post in posts) {
            final dayKey = DateFormat('yyyy-MM-dd').format(post.updatedAt);
            uniqueDays.add(dayKey);
          }
          final totalDays = uniqueDays.length;

          // 最早和最新日期
          final sorted = [...posts]
            ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
          final earliest =
              sorted.isNotEmpty ? sorted.first.updatedAt : DateTime.now();
          final latest =
              sorted.isNotEmpty ? sorted.last.updatedAt : DateTime.now();
          final daySpan = latest.difference(earliest).inDays;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildStatCard(
                  context,
                  icon: Icons.article_outlined,
                  label: '累计日记',
                  value: totalPosts.toString(),
                  unit: '篇',
                  color: const Color(0xFFFF9472),
                ),
                const SizedBox(height: 16),
                _buildStatCard(
                  context,
                  icon: Icons.text_fields_outlined,
                  label: '累计字数',
                  value: _formatNumber(totalChars),
                  unit: '字',
                  color: const Color(0xFF6BB5FF),
                ),
                const SizedBox(height: 16),
                _buildStatCard(
                  context,
                  icon: Icons.image_outlined,
                  label: '累计图片',
                  value: totalImages.toString(),
                  unit: '张',
                  color: const Color(0xFF7DD97D),
                ),
                const SizedBox(height: 16),
                _buildStatCard(
                  context,
                  icon: Icons.calendar_today_outlined,
                  label: '记录天数',
                  value: totalDays.toString(),
                  unit: '天',
                  color: const Color(0xFFFFC56E),
                ),
                if (posts.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  _buildSpanCard(context, earliest, latest, daySpan),
                ],
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('加载失败: $err')),
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF888888),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF3A3A3A),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    unit,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF888888),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpanCard(
    BuildContext context,
    DateTime earliest,
    DateTime latest,
    int daySpan,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F0EB),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          const Text(
            '记录时间跨度',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF888888),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                DateFormat('yyyy/MM/dd').format(earliest),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3A3A3A),
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.arrow_forward,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Text(
                DateFormat('yyyy/MM/dd').format(latest),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3A3A3A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '共 $daySpan 天',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF888888),
            ),
          ),
        ],
      ),
    );
  }

  String _formatNumber(int n) {
    if (n >= 10000) {
      return '${(n / 10000).toStringAsFixed(1)}万';
    } else if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(1)}千';
    }
    return n.toString();
  }
}