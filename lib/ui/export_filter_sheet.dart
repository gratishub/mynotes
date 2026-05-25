import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/tag.dart';
import '../providers.dart';

/// 导出日记配置面板（BottomSheet）
///
/// 用户可在导出前筛选日期范围和标签，确认后返回符合条件的 [List<Post>]。
class ExportFilterSheet extends ConsumerStatefulWidget {
  const ExportFilterSheet({super.key});

  @override
  ConsumerState<ExportFilterSheet> createState() => _ExportFilterSheetState();
}

class _ExportFilterSheetState extends ConsumerState<ExportFilterSheet> {
  late DateTime? _startDate;
  late DateTime? _endDate;
  final Set<String> _selectedTags = {};
  List<Tag> _allTags = [];
  int _postCount = 0;
  bool _isLoadingTags = true;

  @override
  void initState() {
    super.initState();
    // 默认最近一个月
    _endDate = DateTime.now();
    _startDate = _endDate!.subtract(const Duration(days: 30));
    _loadTagsAndCount();
  }

  void _loadTagsAndCount() {
    final store = ref.read(objectBoxProvider);
    _allTags = store.getAllTags();
    _isLoadingTags = false;
    _recalculateCount();
  }

  void _recalculateCount() {
    final store = ref.read(objectBoxProvider);
    final posts = store.getFilteredPosts(
      startDate: _startDate,
      endDate: _endDate,
      selectedTags:
          _selectedTags.isNotEmpty ? _selectedTags.toList() : null,
    );
    setState(() => _postCount = posts.length);
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      helpText: '选择开始日期',
      cancelText: '取消',
      confirmText: '确认',
    );
    if (picked != null) {
      setState(() => _startDate = picked);
      _recalculateCount();
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now(),
      firstDate: _startDate ?? DateTime(2000),
      lastDate: DateTime.now(),
      helpText: '选择结束日期',
      cancelText: '取消',
      confirmText: '确认',
    );
    if (picked != null) {
      setState(() => _endDate = picked);
      _recalculateCount();
    }
  }

  void _onExport() {
    final store = ref.read(objectBoxProvider);
    final posts = store.getFilteredPosts(
      startDate: _startDate,
      endDate: _endDate,
      selectedTags:
          _selectedTags.isNotEmpty ? _selectedTags.toList() : null,
    );
    if (posts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('筛选条件下没有可导出的日记'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.of(context).pop(posts);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat('yyyy-MM-dd');

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ——— 拖拽指示条 ———
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // ——— 标题 ———
            const Center(
              child: Text(
                '导出日记配置',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3A3A3A),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ====================================================
            // 日期选择区
            // ====================================================
            Row(
              children: [
                Icon(Icons.date_range_rounded,
                    size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  '日期范围',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _DateTile(
                    label: '开始日期',
                    formatted: _startDate != null
                        ? dateFmt.format(_startDate!)
                        : '不限',
                    onTap: _pickStartDate,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('—',
                      style: TextStyle(
                          fontSize: 16, color: Colors.grey.shade400)),
                ),
                Expanded(
                  child: _DateTile(
                    label: '结束日期',
                    formatted: _endDate != null
                        ? dateFmt.format(_endDate!)
                        : '不限',
                    onTap: _pickEndDate,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ====================================================
            // 标签筛选区
            // ====================================================
            Row(
              children: [
                Icon(Icons.label_outline_rounded,
                    size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  '标签筛选',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '（不选 = 全部标签）',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade400,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_isLoadingTags)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_allTags.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  '暂无标签',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade400,
                  ),
                ),
              )
            else
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _allTags.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final tag = _allTags[index];
                    final selected = _selectedTags.contains(tag.name);
                    return FilterChip(
                      label: Text(tag.name),
                      selected: selected,
                      onSelected: (value) {
                        setState(() {
                          if (value) {
                            _selectedTags.add(tag.name);
                          } else {
                            _selectedTags.remove(tag.name);
                          }
                        });
                        _recalculateCount();
                      },
                      visualDensity: VisualDensity.compact,
                      selectedColor:
                          theme.colorScheme.primary.withAlpha(30),
                      checkmarkColor: theme.colorScheme.primary,
                      labelStyle: TextStyle(
                        fontSize: 13,
                        color: selected
                            ? theme.colorScheme.primary
                            : const Color(0xFF3A3A3A),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 28),

            // ====================================================
            // 底部动作按钮
            // ====================================================
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: _postCount > 0 ? _onExport : null,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  backgroundColor: const Color(0xFFFF9472),
                  disabledBackgroundColor: Colors.grey.shade200,
                ),
                child: Text(
                  _postCount > 0
                      ? '打包导出（共 $_postCount 篇）'
                      : '没有符合条件的日记',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 日期选择块
class _DateTile extends StatelessWidget {
  final String label;
  final String formatted;
  final VoidCallback onTap;

  const _DateTile({
    required this.label,
    required this.formatted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              formatted,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF3A3A3A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
