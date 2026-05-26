import 'package:objectbox/objectbox.dart';
import 'tag.dart';
import 'image_meta.dart';

/// 日记帖子（Post）实体类
///
/// Post 是应用的核心数据模型，代表一篇日记条目。
///
/// 字段说明：
/// - id: 主键，由 ObjectBox 自动生成
/// - uuid: 全局唯一标识符，用于在多设备同步时作为唯一凭据
/// - content: 日记正文内容（支持纯文本和富文本）
/// - updatedAt: 最后修改时间，用于排序和冲突检测
/// - isDeleted: 软删除标记，支持"回收站"功能
///
/// 关系：
/// - Post 与 Tag 是多对多（Many-to-Many）关系，通过 `ToMany<Tag>` 维护
/// - Post 与 ImageMeta 是一对多（One-to-Many）关系，一个帖子可包含多张图片
///
/// 软删除设计：
/// - isDeleted 默认为 false
/// - 调用 delete() 时，实际执行的是 isDeleted = true，而非物理删除
/// - 查询时默认过滤掉已删除的帖子，除非明确查询"回收站"
@Entity()
class Post {
  /// 主键 ID
  ///
  /// ObjectBox 自动生成，实体创建时为 0，存入数据库后变为正整数。
  /// 注意：即使实体从数据库中删除，其 ID 也不会被复用，这是 ObjectBox 的设计原则。
  int id;

  /// 全局唯一标识符（Universally Unique Identifier）
  ///
  /// UUID 是 128 位的随机数，理论上在全球范围内不重复。
  /// 主要用途：
  /// 1. 多设备同步时作为记录的唯一标识（而不是依赖数据库 ID）
  /// 2. 防止数据冲突：在合并来自其他设备的数据时，UUID 碰撞概率极低
  ///
  /// 生成方式：使用 Dart 的 Uuid 类在创建 Post 时生成。
  String uuid;

  /// 日记正文内容
  ///
  /// 支持任意字符串，包括空字符串（表示空白日记）。
  /// 最大长度理论上是 2GB（String 的上限），实际应用中建议限制在几 MB 以内。
  String content;

  /// 最后更新时间
  ///
  /// 使用 DateTime 存储精确到微秒的时间戳。
  /// 每次修改帖子内容时，都需要更新此字段。
  /// 在同步场景下，updatedAt 较大的记录优先保留（最后写入者获胜）。
  @Property(type: PropertyType.date)
  DateTime updatedAt;

  /// 创建时间
  ///
  /// 帖子首次创建的时间戳，写入后不再变更。
  /// 与 updatedAt 不同，createdAt 不受内容修改影响，
  /// 可用于按创建时间排序和展示。
  @Property(type: PropertyType.date)
  DateTime createdAt;

  /// 软删除标记
  ///
  /// true = 已删除（进入回收站）
  /// false = 正常状态
  ///
  /// 为什么要用软删除？
  /// 1. 防止误删：用户可以"撤销"删除操作
  /// 2. 数据安全：管理员可以恢复被删除的内容
  /// 3. 审计需求：保留删除记录用于追溯
  /// 4. 同步友好：删除操作可以精确同步到其他设备
  @Index()
  bool isDeleted;

  /// 关联的标签列表（多对多关系）
  ///
  /// `ToMany<Tag>` 是 ObjectBox 提供的关系类型，表示"一个 Post 关联多个 Tag"。
  ///
  /// 工作原理：
  /// - ObjectBox 在底层维护一张关联表（Post-Tag 映射表）
  /// - 添加/删除关联只是修改这张映射表，不会影响 Tag 实体本身
  /// - 访问 tags 时，ObjectBox 会自动从关联表中查询并返回对应的 Tag 列表
  ///
  /// 示例用法：
  ///   post.tags.add(tag);      // 添加标签关联
  ///   post.tags.remove(tag);   // 移除标签关联
  ///   post.tags.clear();       // 清除所有标签关联
  ///   post.tags.length;        // 获取关联的标签数量
  final tags = ToMany<Tag>();

  /// 关联的图片元数据列表（一对多关系）
  ///
  /// 一个帖子可以包含多张本地图片。每张图片的元数据存储在 ImageMeta 中。
  ///
  /// 与 ToMany 的区别：
  /// - ToMany: 多对多关系，关联表独立存在，双方都可以独立存在
  /// - ToOne/ToMany (一方): 一对多关系，子实体的存在依赖于父实体
  ///
  /// 这里的 ImageMeta.localPath 存储图片的本地路径，
  /// 图片文件本身由文件系统管理，数据库只记录路径元数据。
  @Backlink('post')
  final images = ToMany<ImageMeta>();

  Post({
    this.id = 0,
    required this.uuid,
    this.content = '',
    required this.updatedAt,
    this.isDeleted = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}