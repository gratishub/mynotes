import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// 图片处理器
///
/// 负责将用户从相册选中的原始图片保存到应用私有目录。
/// 文件不经压缩，保留原始质量。
class ImageProcessor {
  /// 处理图片：直接拷贝到沙盒目录
  ///
  /// [source] 从 image_picker 获取的图片文件（XFile 对象）
  /// 返回：图片在沙盒目录中的完整路径
  ///
  /// 处理流程：
  /// 1. 获取应用私有目录下的 images 文件夹路径
  /// 2. 提取原始文件的扩展名
  /// 3. 用时间戳生成唯一文件名，直接拷贝文件
  ///
  /// 错误处理：任何步骤失败都会抛出异常，调用方应捕获并提示用户。
  static Future<String> process(XFile source) async {
    // 1. 获取沙盒目录并确保 images 文件夹存在
    final dir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${dir.path}/images');

    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    // 2. 提取原始文件的扩展名
    final rawExt = source.path.split('.').last.toLowerCase();
    final ext = rawExt.isNotEmpty ? rawExt : 'jpg';

    // 3. 用时间戳 + 随机数生成唯一文件名并拷贝
    final fileName = 'img_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final filePath = '${imagesDir.path}/$fileName';

    await File(source.path).copy(filePath);

    return filePath;
  }
}