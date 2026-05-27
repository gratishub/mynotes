import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../models/post.dart';
import '../models/image_meta.dart';
import '../models/tag.dart';
import '../services/image_processor.dart';
import '../providers.dart';

/// 发布/编辑页 — 沉浸式书写界面（支持 Markdown 快捷输入与预览）
///
/// 传入 [post] 时为编辑模式，会预填内容并将保存结果写回同一篇帖子。
/// 不传 [post] 时为新建模式。
class PublishScreen extends ConsumerStatefulWidget {
  final Post? post;

  const PublishScreen({super.key, this.post});

  @override
  ConsumerState<PublishScreen> createState() => _PublishScreenState();
}

class _PublishScreenState extends ConsumerState<PublishScreen> {
  final _contentController = TextEditingController();
  final _focusNode = FocusNode();
  final List<XFile> _selectedImages = [];
  final List<String> _existingImagePaths = [];
  final List<String> _deletedImagePaths = [];
  final List<String> _selectedTags = [];
  bool _isPublishing = false;
  bool _isPreview = false;

  static const _weekDays = [
    '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日',
  ];

  bool get _isEditing => widget.post != null;

  @override
  void initState() {
    super.initState();
    if (widget.post != null) {
      _contentController.text = widget.post!.content;
      _existingImagePaths
          .addAll(widget.post!.images.map((img) => img.localPath));
      _selectedTags.addAll(widget.post!.tags.map((t) => t.name));
    }
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _contentController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ============================================================
  // 图片选取
  // ============================================================

  Future<void> _pickImages() async {
    try {
      final picker = ImagePicker();
      final images = await picker.pickMultiImage(
        imageQuality: 100,
        maxWidth: 400,
      );
      if (images.isNotEmpty) {
        setState(() => _selectedImages.addAll(images));
      }
    } catch (e) {
      _showError('选取图片失败: $e');
    }
  }

  void _removeImage(int index) {
    setState(() {
      final existingCount = _existingImagePaths.length;
      if (index < existingCount) {
        // 删除已有图片（标记为待删除）
        _deletedImagePaths.add(_existingImagePaths[index]);
        _existingImagePaths.removeAt(index);
      } else {
        // 删除新选图片
        _selectedImages.removeAt(index - existingCount);
      }
    });
  }

  // ============================================================
  // Markdown 快捷格式插入
  // ============================================================

  /// 通用 Markdown 格式注入
  ///
  /// [prefix] 标记前缀，如 `**`、`*`
  /// [suffix] 标记后缀。不传时使用行首插入模式（标题/列表/引用）；
  ///          传值时使用包裹模式（加粗/斜体），选中文本时包裹，未选中时插入占位。
  void _insertMarkdown(String prefix, {String suffix = ''}) {
    if (suffix.isNotEmpty) {
      _wrapSelection(prefix, suffix: suffix);
    } else {
      _insertLinePrefix(prefix);
    }
    _focusNode.requestFocus();
  }

  /// 在选中文字两侧包裹标记
  void _wrapSelection(String prefix, {String suffix = ''}) {
    final text = _contentController.text;
    final sel = _contentController.selection;

    if (sel.isValid && sel.start < sel.end) {
      final selected = text.substring(sel.start, sel.end);
      _contentController.text = text.replaceRange(
        sel.start,
        sel.end,
        '$prefix$selected$suffix',
      );
      _contentController.selection = TextSelection.collapsed(
        offset: sel.start + prefix.length + selected.length + suffix.length,
      );
    } else {
      final content = '$prefix$suffix';
      _contentController.text = text.replaceRange(sel.start, sel.start, content);
      _contentController.selection = TextSelection.collapsed(
        offset: sel.start + prefix.length,
      );
    }
  }

  /// 在行首插入前缀（标题、引用、列表、待办）
  void _insertLinePrefix(String prefix) {
    final text = _contentController.text;
    final cursorPos = _contentController.selection.start;

    int lineStart = cursorPos;
    while (lineStart > 0 && text[lineStart - 1] != '\n') {
      lineStart--;
    }

    _contentController.text = text.replaceRange(lineStart, lineStart, prefix);
    _contentController.selection = TextSelection.collapsed(
      offset: cursorPos + prefix.length,
    );
  }

  /// 插入加粗 ** **
  void _insertBold() => _insertMarkdown('**', suffix: '**');

  /// 插入斜体 * *
  void _insertItalic() => _insertMarkdown('*', suffix: '*');

  /// 插入标题 #
  void _insertHeading() => _insertMarkdown('# ');

  /// 引用
  void _insertQuote() => _insertMarkdown('> ');

  /// 无序列表
  void _insertList() => _insertMarkdown('- ');

  /// 待办清单
  void _insertTodo() => _insertMarkdown('- [ ] ');

  // ============================================================
  // 发布
  // ============================================================

  Future<void> _publish() async {
    final content = _contentController.text.trim();

    if (content.isEmpty &&
        _selectedImages.isEmpty &&
        _existingImagePaths.isEmpty) {
      _showError('请至少输入一些文字或添加一张图片');
      return;
    }

    setState(() => _isPublishing = true);

    try {
      final store = ref.read(objectBoxProvider);

      final Post post;
      if (_isEditing) {
        post = widget.post!;
        post.content = content;
        // 编辑不改变 updatedAt，保留原始日期
      } else {
        post = Post(
          uuid: const Uuid().v4(),
          content: content,
          updatedAt: DateTime.now(),
          isDeleted: false,
        );
      }

      final processedPaths = <String>[];
      for (final image in _selectedImages) {
        final savedPath = await ImageProcessor.process(image);
        processedPaths.add(savedPath);
      }

      final postId = store.putPost(post);
      final savedPost = store.getPost(postId)!;

      for (final path in processedPaths) {
        final imageMeta = ImageMeta(localPath: path);
        imageMeta.post.target = savedPost;
        store.imageBox.put(imageMeta);
      }

      // 清理编辑模式下被删除的已有图片
      for (final path in _deletedImagePaths) {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
        for (final img in savedPost.images) {
          if (img.localPath == path) {
            store.imageBox.remove(img.id);
            break;
          }
        }
      }

      // 处理标签
      savedPost.tags.clear();
      for (final tagName in _selectedTags) {
        var tag = store.getTagByName(tagName);
        if (tag == null) {
          tag = Tag(name: tagName);
          store.putTag(tag);
        }
        savedPost.tags.add(tag);
      }
      store.putPost(savedPost);

      // 保存成功后强制刷新主页的日记列表
      // activePostsProvider 是 StreamProvider，invalidate 会让它重新从 Stream 读取最新数据
      ref.invalidate(activePostsProvider);

      _contentController.clear();
      setState(() {
        _selectedImages.clear();
        _existingImagePaths.clear();
        _deletedImagePaths.clear();
        _selectedTags.clear();
        _isPublishing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isEditing ? '日记已更新！' : '日记发布成功！')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _isPublishing = false);
      _showError('${_isEditing ? '更新' : '发布'}失败: $e');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // ============================================================
  // 标签选择面板
  // ============================================================

  Future<void> _showTagPicker() async {
    final store = ref.read(objectBoxProvider);
    final allTags = store.getAllTags();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '选择标签',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3A3A3A),
                  ),
                ),
                const SizedBox(height: 12),
                // 输入新标签
                StatefulBuilder(
                  builder: (context, setInputState) {
                    final controller = TextEditingController();
                    return Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: controller,
                            decoration: InputDecoration(
                              hintText: '添加新标签',
                              hintStyle: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 14,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade200),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade200),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                              ),
                              isDense: true,
                            ),
                            onSubmitted: (value) {
                              final tag = value.trim();
                              if (tag.isNotEmpty && !_selectedTags.contains(tag)) {
                                setState(() => _selectedTags.add(tag));
                                setSheetState(() {});
                              }
                              controller.clear();
                              setInputState(() {});
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(Icons.add_circle, color: Theme.of(context).colorScheme.primary),
                          onPressed: () {
                            final tag = controller.text.trim();
                            if (tag.isNotEmpty && !_selectedTags.contains(tag)) {
                              setState(() => _selectedTags.add(tag));
                              setSheetState(() {});
                            }
                            controller.clear();
                            setInputState(() {});
                          },
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                // 已选标签提示
                if (_selectedTags.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _selectedTags.map((t) => Chip(
                      label: Text(t, style: const TextStyle(fontSize: 12)),
                      backgroundColor: Theme.of(context).colorScheme.primary.withAlpha(25),
                      labelStyle: TextStyle(color: Theme.of(context).colorScheme.primary),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    )).toList(),
                  ),
                  const SizedBox(height: 10),
                ],
                // 已有标签列表
                if (allTags.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        '暂无标签',
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: allTags.map((tag) {
                      final isSelected = _selectedTags.contains(tag.name);
                      return FilterChip(
                        label: Text(tag.name),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedTags.add(tag.name);
                            } else {
                              _selectedTags.remove(tag.name);
                            }
                          });
                          setSheetState(() {});
                        },
                        selectedColor: Theme.of(context).colorScheme.primary.withAlpha(35),
                        checkmarkColor: Theme.of(context).colorScheme.primary,
                        labelStyle: TextStyle(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : const Color(0xFF555555),
                          fontSize: 13,
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  // UI — 构建入口
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final weekDay = _weekDays[now.weekday - 1];
    final dateStr = '${now.month}月${now.day}日 $weekDay';

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ——— 顶部栏：返回 / 日期 / 预览按钮 + 发布 ———
            _buildTopBar(dateStr, theme),
            // ——— 主体内容区 ———
            Expanded(
              child: _isPreview
                  ? _buildPreviewBody(theme)
                  : _buildEditBody(theme),
            ),
            // ——— 底部工具栏（仅编辑模式可见） ———
            if (!_isPreview) ...[
              if (_totalImageCount > 0) _buildImagePreviewRow(),
              _buildMarkdownToolbar(theme),
              _buildCapsuleToolbar(theme),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // 顶部栏
  // ============================================================

  Widget _buildTopBar(String dateStr, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.arrow_back_rounded, size: 22),
              color: const Color(0xFF3A3A3A),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const Spacer(),
          Text(
            dateStr,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFFB0B0B0),
              fontWeight: FontWeight.w400,
            ),
          ),
          const Spacer(),
          // 预览/编辑切换
          IconButton(
            icon: Icon(
              _isPreview ? Icons.edit_rounded : Icons.remove_red_eye_outlined,
              size: 20,
            ),
            color: _isPreview
                ? theme.colorScheme.primary
                : const Color(0xFF3A3A3A),
            tooltip: _isPreview ? '返回编辑' : '预览',
            onPressed: () {
              setState(() {
                _isPreview = !_isPreview;
                if (_isPreview) {
                  _focusNode.unfocus();
                } else {
                  _focusNode.requestFocus();
                }
              });
            },
          ),
          const SizedBox(width: 4),
          // 发布按钮
          _isPublishing
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : TextButton(
                  onPressed: _publish,
                  style: TextButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary.withAlpha(30),
                    foregroundColor: theme.colorScheme.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    '发布',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  // ============================================================
  // 编辑模式主体 — 文本输入
  // ============================================================

  Widget _buildEditBody(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 已选标签展示
          if (_selectedTags.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _selectedTags.map((tag) => GestureDetector(
                onTap: () {
                  setState(() => _selectedTags.remove(tag));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        tag,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.close,
                        size: 14,
                        color: theme.colorScheme.primary.withAlpha(150),
                      ),
                    ],
                  ),
                ),
              )).toList(),
            ),
            const SizedBox(height: 4),
          ],
          // 文本输入框
          Expanded(
            child: TextField(
              controller: _contentController,
              focusNode: _focusNode,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              cursorWidth: 2,
              cursorColor: theme.colorScheme.primary,
              decoration: InputDecoration(
                hintText: '此刻的想法或发生的故事...',
                hintStyle: TextStyle(
                  color: theme.colorScheme.onSurface.withAlpha(35),
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  height: 1.7,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                isDense: true,
              ),
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.7,
                color: const Color(0xFF3A3A3A),
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 预览模式主体 — Markdown 渲染
  // ============================================================

  Widget _buildPreviewBody(ThemeData theme) {
    final content = _contentController.text.trim();
    final hasContent = content.isNotEmpty;
    final totalImages = _totalImageCount;

    if (!hasContent && totalImages == 0) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 已选标签展示
          if (_selectedTags.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _selectedTags.map((tag) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  tag,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.primary,
                  ),
                ),
              )).toList(),
            ),
            const SizedBox(height: 8),
          ],
          if (hasContent)
            MarkdownBody(
              data: content,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: theme.textTheme.bodyLarge?.copyWith(
                  height: 1.7,
                  color: const Color(0xFF3A3A3A),
                ),
                a: TextStyle(color: theme.colorScheme.primary),
                strong: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF3A3A3A),
                ),
                em: theme.textTheme.bodyLarge?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: const Color(0xFF3A3A3A),
                ),
                h1: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF2A2A2A),
                ),
                h2: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF2A2A2A),
                ),
                h3: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF2A2A2A),
                ),
                blockquote: theme.textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFF888888),
                  fontStyle: FontStyle.italic,
                ),
                code: TextStyle(
                  backgroundColor: Colors.grey.shade100,
                  fontFamily: 'monospace',
                  fontSize: 14,
                  color: const Color(0xFF3A3A3A),
                ),
                codeblockDecoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                listBullet: const TextStyle(color: Color(0xFF3A3A3A)),
                horizontalRuleDecoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey.shade300)),
                ),
                blockquoteDecoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: theme.colorScheme.primary.withAlpha(100),
                      width: 3,
                    ),
                  ),
                ),
              ),
            ),
          if (totalImages > 0) ...[
            if (hasContent) const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _allImagePaths.map((path) {
                return GestureDetector(
                  onTap: () => _openFullScreenImage(path),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(path),
                      width: (MediaQuery.of(context).size.width - 48) / 2,
                      height: 160,
                      fit: BoxFit.cover,
                      cacheWidth: 400,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: (MediaQuery.of(context).size.width - 48) / 2,
                          height: 160,
                          color: Colors.grey.shade200,
                          child: const Icon(
                            Icons.broken_image,
                            size: 28,
                            color: Colors.grey,
                          ),
                        );
                      },
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // Markdown 快捷格式栏
  // ============================================================

  Widget _buildMarkdownToolbar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(210),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withAlpha(140)),
            ),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              children: [
                _mdToolButton(
                  Icons.format_bold_rounded,
                  '加粗',
                  _insertBold,
                ),
                _mdToolButton(
                  Icons.format_italic_rounded,
                  '斜体',
                  _insertItalic,
                ),
                _mdToolDivider(),
                _mdToolButton(
                  Icons.format_size_rounded,
                  '标题',
                  _insertHeading,
                ),
                _mdToolDivider(),
                _mdToolButton(
                  Icons.checklist_rounded,
                  '待办',
                  _insertTodo,
                ),
                _mdToolButton(
                  Icons.format_list_bulleted_rounded,
                  '列表',
                  _insertList,
                ),
                _mdToolButton(
                  Icons.format_quote_rounded,
                  '引用',
                  _insertQuote,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _mdToolButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 40,
        height: 42,
        child: IconButton(
          padding: EdgeInsets.zero,
          icon: Icon(icon, size: 20),
          color: const Color(0xFF555555),
          onPressed: onTap,
        ),
      ),
    );
  }

  Widget _mdToolDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        width: 1,
        color: Colors.black.withAlpha(12),
      ),
    );
  }

  // ============================================================
  // 图片预览行
  // ============================================================

  /// 总图片数（已有 + 新选）
  int get _totalImageCount =>
      _existingImagePaths.length + _selectedImages.length;

  /// 合并后的所有图片路径
  List<String> get _allImagePaths =>
      [..._existingImagePaths, ..._selectedImages.map((x) => x.path)];

  /// 打开全屏图片查看器（支持捏合缩放）
  void _openFullScreenImage(String path) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              maxScale: 5,
              child: Image.file(
                File(path),
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
        ),
      ),
    );
  }

  Widget _buildImagePreviewRow() {
    return SizedBox(
      height: 76,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _totalImageCount,
        itemBuilder: (context, index) => _buildImagePreview(index),
      ),
    );
  }

  Widget _buildImagePreview(int index) {
    final existingCount = _existingImagePaths.length;
    final imagePath = index < existingCount
        ? _existingImagePaths[index]
        : _selectedImages[index - existingCount].path;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        children: [
          GestureDetector(
            onTap: () => _openFullScreenImage(imagePath),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(imagePath),
                width: 68,
                height: 68,
                fit: BoxFit.cover,
                cacheWidth: 200,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 68,
                  height: 68,
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.broken_image,
                      size: 20, color: Colors.grey),
                );
              },
            ),
          ),
        ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: () => _removeImage(index),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(100),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withAlpha(80),
                        width: 0.5,
                      ),
                    ),
                    child: const Icon(Icons.close, size: 12, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 悬浮胶囊工具栏（毛玻璃）
  // ============================================================

  Widget _buildCapsuleToolbar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(220),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withAlpha(160)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(12),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                // 🖼️ 图片
                _pillIcon(Icons.image_outlined, '添加图片', _pickImages),
                const Spacer(),
                // # 标签
                _pillIcon(
                  Icons.local_offer_outlined,
                  '选择标签',
                  _showTagPicker,
                  isActive: _selectedTags.isNotEmpty,
                ),
                const Spacer(),
                // ➕ 更多
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey.withAlpha(30),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.more_horiz_rounded, size: 22),
                    color: const Color(0xFF888888),
                    onPressed: () => _showInfo('进阶工具包开发中...'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pillIcon(
    IconData icon,
    String tooltip,
    VoidCallback onTap, {
    bool isActive = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 44,
        height: 44,
        child: IconButton(
          padding: EdgeInsets.zero,
          icon: Icon(icon, size: 22),
          color: isActive
              ? Theme.of(context).colorScheme.primary
              : const Color(0xFF555555),
          onPressed: onTap,
        ),
      ),
    );
  }

  void _showInfo(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(40, 0, 40, 80),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      );
    }
  }
}
