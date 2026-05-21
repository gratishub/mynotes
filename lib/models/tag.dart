import 'package:objectbox/objectbox.dart';

/// 标签（Tag）实体类
///
/// 在 ObjectBox 中，每个实体类都对应数据库中的一张表。
/// @Entity 注解标记此类为 ObjectBox 的持久化实体。
///
/// 标签用于对日记帖子（Post）进行分类。一个帖子可以关联多个标签，
/// 一个标签也可以关联多个帖子，因此 Tag 和 Post 是多对多（Many-to-Many）关系。
///
/// 关系维护：
/// - 在 Post 类中通过 `ToMany<Tag>` tags 维护关联
/// - ObjectBox 会自动生成反向引用，无需在 Tag 类中显式声明
@Entity()
class Tag {
  /// 主键 ID
  ///
  /// ObjectBox 会为每个实体自动生成一个递增的整型 ID，作为主键。
  /// 只要实体未被删除，这个 ID 在整个数据库生命周期中是唯一且不变的。
  /// 注意：ID 为 0 表示"未分配"状态（通常用于新创建但尚未存入数据库的对象）。
  int id;

  /// 标签名称
  ///
  /// 唯一约束：同一个应用内，标签名称不能重复。
  /// 我们使用 @Unique() 注解来确保这一约束，ObjectBox 会在插入时验证。
  /// 如果插入重复名称的标签，操作会失败并抛出异常。
  @Unique()
  String name;

  Tag({
    this.id = 0,  // 默认值 0 表示这是一个新建对象，尚未写入数据库
    required this.name,
  });
}