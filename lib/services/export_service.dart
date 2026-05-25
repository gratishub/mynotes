import 'dart:io';

import 'package:intl/intl.dart';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';

import '../objectbox.g.dart';
import '../services/objectbox_store.dart';
import '../models/post.dart';

/// 日记导出服务
///
/// 负责从 ObjectBox 中查询所有非软删除的日记，
/// 按天聚合，并组装为带 YAML Frontmatter 的 Markdown 字符串。
class ExportService {
  /// 查询所有非软删除的帖子，按 updatedAt 严格升序排列
  static List<Post> getAllPostsAscending() {
    final query = ObjectBoxStore.instance.postBox
        .query(Post_.isDeleted.notEquals(true))
        .order(Post_.updatedAt) // 默认升序
        .build();

    final results = query.find();
    query.close();
    return results;
  }

  /// 按天分组（yyyy-MM-dd）
  static Map<String, List<Post>> groupByDay(List<Post> posts) {
    final grouped = <String, List<Post>>{};
    for (final post in posts) {
      final dayKey = DateFormat('yyyy-MM-dd').format(post.updatedAt);
      grouped.putIfAbsent(dayKey, () => []).add(post);
    }
    return grouped;
  }

  /// 提取该天所有帖子中去重的标签名称集合
  static Set<String> collectUniqueTags(List<Post> posts) {
    final tags = <String>{};
    for (final post in posts) {
      for (final tag in post.tags) {
        tags.add(tag.name);
      }
    }
    return tags;
  }

  /// 构建 YAML Frontmatter
  ///
  /// 输出格式：
  /// ---
  /// date: 2026-05-25
  /// tags:
  ///   - 生活
  ///   - 工作
  /// ---
  static String _buildFrontmatter(String date, Set<String> tags) {
    final buf = StringBuffer();
    buf.writeln('---');
    buf.writeln('date: $date');
    if (tags.isNotEmpty) {
      buf.writeln('tags:');
      for (final tag in tags.toList()..sort()) {
        buf.writeln('  - $tag');
      }
    }
    buf.writeln('---');
    return buf.toString();
  }

  /// 构建单条帖子在正文中的 Markdown 片段
  ///
  /// 格式：
  /// ### HH:mm
  ///
  /// 正文内容...
  ///
  /// ![image](assets/文件名)
  static String _buildPostBody(Post post) {
    final buf = StringBuffer();

    // 时间分割线
    final timeStr = DateFormat('HH:mm').format(post.updatedAt);
    buf.writeln('### $timeStr');
    buf.writeln();

    // 正文内容（非空时输出）
    final trimmed = post.content.trim();
    if (trimmed.isNotEmpty) {
      buf.writeln(trimmed);
      buf.writeln();
    }

    // 图片引用
    for (final image in post.images) {
      final fileName = image.localPath.split(RegExp(r'[/\\]')).last;
      buf.writeln('![image](assets/$fileName)');
      buf.writeln();
    }

    return buf.toString();
  }

  /// 构建单日完整的 Markdown 内容
  ///
  /// 串联：YAML Frontmatter → 各条日记的 ### HH:mm + 正文 + 图片
  static String buildDailyMarkdown(String date, List<Post> posts) {
    final buf = StringBuffer();

    // Frontmatter
    final tags = collectUniqueTags(posts);
    buf.write(_buildFrontmatter(date, tags));
    buf.writeln();

    // 正文（posts 本身已按 updatedAt 升序排列）
    for (final post in posts) {
      buf.write(_buildPostBody(post));
    }

    return buf.toString();
  }

  /// 生成完整的导出内容
  ///
  /// 返回值：Map<文件名, Markdown内容>
  /// 文件名格式：yyyy-MM-dd.md
  static Map<String, String> generateExportContent() {
    final posts = getAllPostsAscending();
    final grouped = groupByDay(posts);

    final result = <String, String>{};
    for (final entry in grouped.entries) {
      result['${entry.key}.md'] = buildDailyMarkdown(entry.key, entry.value);
    }

    return result;
  }

  // ============================================================
  // ZIP 导出
  // ============================================================

  /// 执行完整的 ZIP 导出流程
  ///
  /// [postsToExport] 待导出的日记列表（已由调用方筛好）。
  ///
  /// 1. 在临时目录下创建沙盒环境（mynotes_export/assets）
  /// 2. 按天聚合传入列表 → 写入 Markdown 文件
  /// 3. 遍历所有日记的图片，物理拷贝到 assets/
  /// 4. 用 archive 库压缩为 ZIP
  /// 5. 清理临时文件夹
  ///
  /// 返回值：生成的 ZIP 文件绝对路径
  ///
  /// 异常情况：
  /// - 空列表时抛出 [StateError]
  /// - 图片文件在本地丢失时，Markdown 中替换为注释占位
  static Future<String> exportToZip(List<Post> postsToExport) async {
    if (postsToExport.isEmpty) {
      throw StateError('没有可导出的日记');
    }

    // ——— 1. 建立沙盒环境 ———
    final tempDir = await getTemporaryDirectory();
    final exportDir = Directory('${tempDir.path}/mynotes_export');
    final assetsDir = Directory('${exportDir.path}/assets');
    await exportDir.create(recursive: true);
    await assetsDir.create(recursive: true);

    try {
      // ——— 2. 按天聚合 → 写入 Markdown ———
      final grouped = groupByDay(postsToExport);
      final content = <String, String>{};
      for (final entry in grouped.entries) {
        final md = buildDailyMarkdown(entry.key, entry.value);
        final fileName = '${entry.key}.md';
        content[fileName] = md;
        await File('${exportDir.path}/$fileName').writeAsString(md);
      }

      // ——— 3. 物理拷贝图片 ———
      final missingImages = <String>{};

      for (final post in postsToExport) {
        for (final image in post.images) {
          final sourceFile = File(image.localPath);
          final fileName = image.localPath.split(RegExp(r'[/\\]')).last;

          if (await sourceFile.exists()) {
            await sourceFile.copy('${assetsDir.path}/$fileName');
          } else {
            missingImages.add(fileName);
          }
        }
      }

      // 对缺失图片：在已生成的 Markdown 中将引用替换为注释占位
      if (missingImages.isNotEmpty) {
        for (final fileName in content.keys) {
          final mdFile = File('${exportDir.path}/$fileName');
          var mdContent = await mdFile.readAsString();
          for (final img in missingImages) {
            mdContent = mdContent.replaceAll(
              '![image](assets/$img)',
              '<!-- 图片缺失: $img -->',
            );
          }
          await mdFile.writeAsString(mdContent);
        }
      }

      // ——— 4. ZIP 压缩 ———
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final zipFileName = 'mynotes_backup_$timestamp.zip';
      final zipFilePath = '${tempDir.path}/$zipFileName';

      final encoder = ZipFileEncoder();
      encoder.create(zipFilePath);
      await encoder.addDirectory(exportDir, includeDirName: true);
      await encoder.close();

      return zipFilePath;
    } finally {
      // ——— 5. 清理临时文件夹 ———
      if (await exportDir.exists()) {
        await exportDir.delete(recursive: true);
      }
    }
  }
}
