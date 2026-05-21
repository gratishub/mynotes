import 'package:objectbox/objectbox.dart';
import 'post.dart';

/// 图片元数据（ImageMeta）实体类
///
/// 用于存储日记帖子中引用的图片的元数据信息。
///
/// 设计理念：
/// - 图片文件本身存储在设备文件系统中（通常在 app 的 documents 目录）
/// - 数据库只记录图片的路径、大小、创建时间等元数据
/// - 这种设计避免了在数据库中存储二进制数据，减少数据库体积
///
/// 关系：
/// - ImageMeta 属于某一个 Post，是 Post 的子实体（一对多关系的"多"端）
/// - 每个 ImageMeta 只能属于一个 Post，通过 Post 的 images ToMany 关系访问
///
/// 字段说明：
/// - id: 主键
/// - localPath: 图片文件在设备上的完整路径
///   格式示例：/data/user/0/com.example.mynotes/files/images/xxxx.jpg
/// - 创建后 localPath 不应随意更改，否则会导致图片丢失
@Entity()
class ImageMeta {
  /// 主键 ID
  int id;

  /// 图片的本地文件系统路径
  ///
  /// 存储图片文件在设备上的完整路径。
  /// 路径由 path_provider 插件生成，通常位于应用私有目录内。
  ///
  /// 安全考量：
  /// - 应用卸载时，此目录下的所有文件会被系统清理
  /// - 图片文件应存储在 getApplicationDocumentsDirectory() 下，而非临时目录
  String localPath;

  /// 关联的父帖子（反向引用）
  ///
  /// 这是 Post 类中 images ToMany 的反向端。
  /// ObjectBox 根据这个注解自动建立 ImageMeta 与 Post 的关联关系。
  ///
  /// 通过反向引用，可以：
  ///   image.post.target  // 获取图片所属的帖子
  ///   image.post.targetId // 获取帖子 ID（不加载整个对象）
  final post = ToOne<Post>();

  ImageMeta({
    this.id = 0,
    required this.localPath,
  });
}