import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// 图片处理器
///
/// 负责将用户从相册选中的原始图片压缩、转换为缩略图并保存到应用私有目录。
/// 缩略图参数：最大宽度 400px、JPEG 格式（兼顾质量与体积）。
class ImageProcessor {
  /// 缩略图最大宽度（像素）
  ///
  /// 400px 是日记应用中一个合理的缩略图尺寸：
  /// - 在大多数手机屏幕上展示足够清晰
  /// - 文件体积通常在 20-50KB 之间
  /// - 不会显著增加数据库或磁盘负担
  static const int maxWidth = 400;

  /// JPEG 压缩质量 (0-100)
  ///
  /// 85 是一个平衡点：画质损失肉眼几乎不可察觉，但体积比原图缩小 5-10 倍。
  static const int webpQuality = 85;

  /// 处理图片：读取 → 缩放 → 转 WebP → 存入本地
  ///
  /// [source] 从 image_picker 获取的图片文件（XFile 对象）
  /// 返回：缩略图在沙盒目录中的完整路径
  ///
  /// 处理流程：
  /// 1. 从 XFile 读取原始图片字节
  /// 2. 使用 `image` 包解码图片
  /// 3. 按比例缩放至 maxWidth（原图更小时不做放大）
  /// 4. 编码为 JPEG 格式
  /// 5. 写入应用私有目录，文件名使用时间戳避免冲突
  ///
  /// 错误处理：任何步骤失败都会抛出异常，调用方应捕获并提示用户。
  static Future<String> process(XFile source) async {
    // 1. 读取原始图片文件
    final originalBytes = await source.readAsBytes();

    // 2. 解码为内存中的图像对象
    final originalImage = img.decodeImage(originalBytes);
    if (originalImage == null) {
      throw Exception('无法解码图片文件：${source.path}');
    }

    // 3. 按比例缩放。如果原图宽度已小于 maxWidth，保持原尺寸不做放大
    final img.Image resized;
    if (originalImage.width > maxWidth) {
      resized = img.copyResize(originalImage, width: maxWidth);
    } else {
      resized = originalImage;
    }

    // 4. 编码为 JPEG 格式（image 4.x 已移除 WebP 编码器）
    final compressedBytes = img.encodeJpg(resized, quality: webpQuality);

    // 5. 写入沙盒目录
    final dir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${dir.path}/images');

    // 确保图片目录存在
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    // 用时间戳 + 随机数生成唯一文件名
    final fileName = 'img_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final filePath = '${imagesDir.path}/$fileName';

    final file = File(filePath);
    await file.writeAsBytes(compressedBytes);

    return filePath;
  }
}