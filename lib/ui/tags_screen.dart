import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../models/tag.dart';

/// 标签管理页面
///
/// 展示数据库中所有的标签，以及每个标签关联的日记数量。
/// 支持左滑删除空标签。
class TagsScreen extends ConsumerWidget {
  const TagsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.read(objectBoxProvider);
    final allTags = store.getAllTags();
    final activePosts = ref.watch(activePostsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('标签'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: activePosts.when(
        data: (posts) {
          if (allTags.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.local_offer_outlined,
                    size: 64,
                    color: Color(0xFFCCCCCC),
                  ),
                  SizedBox(height: 16),
                  Text(
                    '还没有标签',
                    style: TextStyle(
                      fontSize: 16,
                      color: Color(0xFF888888),
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '在写日记时添加标签来分类',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFFBBBBBB),
                    ),
                  ),
                ],
              ),
            );
          }

          // 计算每个标签关联的日记数量
          final tagCounts = <int, int>{};
          for (final tag in allTags) {
            int count = 0;
            for (final post in posts) {
              if (post.tags.any((t) => t.id == tag.id)) {
                count++;
              }
            }
            tagCounts[tag.id] = count;
          }

          // 按日记数量降序排列
          final sortedTags = [...allTags]
            ..sort((a, b) => (tagCounts[b.id] ?? 0).compareTo(tagCounts[a.id] ?? 0));

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: sortedTags.length,
            itemBuilder: (context, index) {
              final tag = sortedTags[index];
              final count = tagCounts[tag.id] ?? 0;

              return Dismissible(
                key: Key('tag_${tag.id}'),
                direction: count == 0
                    ? DismissDirection.endToStart
                    : DismissDirection.none,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  decoration: BoxDecoration(
                    color: Colors.red.shade400,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.delete_outline,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                confirmDismiss: (_) async {
                  if (count > 0) return false;
                  return await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('删除标签'),
                      content: Text('确定删除标签「${tag.name}」吗？'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(
                            '删除',
                            style: TextStyle(color: Colors.red.shade600),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                onDismissed: (_) {
                  store.deleteTag(tag.id);
                  // 触发 UI 刷新
                  ref.invalidate(activePostsProvider);
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(6),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 4,
                    ),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9472).withAlpha(25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.local_offer_outlined,
                        color: Color(0xFFFF9472),
                        size: 20,
                      ),
                    ),
                    title: Text(
                      tag.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF3A3A3A),
                      ),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: count > 0
                            ? const Color(0xFFFF9472).withAlpha(25)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$count 篇',
                        style: TextStyle(
                          fontSize: 12,
                          color: count > 0
                              ? const Color(0xFFFF9472)
                              : Colors.grey.shade500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('加载失败: $err')),
      ),
    );
  }
}