import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../objectbox.g.dart';
import '../models/post.dart';
import '../models/tag.dart';
import '../models/image_meta.dart';

/// ObjectBox 数据库管理单例
///
/// 单例模式确保整个应用只存在一个数据库连接实例。
/// 为什么要用单例？
/// 1. ObjectBox 的 Store 对象创建成本较高（需要打开文件、建立索引）
/// 2. 多个 Store 实例同时操作同一数据库文件会导致数据损坏
/// 3. 全局共享一个 Store 让数据管理更简单、可预测
///
/// 使用流程：
/// 1. 在 main() 函数中调用 ObjectBoxStore.init() 初始化数据库目录并打开 Store
/// 2. 之后通过 ObjectBoxStore.instance 在应用的任何位置访问数据库
class ObjectBoxStore {
  /// 单例实例
  static ObjectBoxStore? _instance;

  /// 获取单例对象
  ///
  /// 注意：调用此方法前必须先调用 [init] 进行初始化。
  /// 如果未初始化就访问会抛出 StateError。
  static ObjectBoxStore get instance {
    if (_instance == null) {
      throw StateError(
        'ObjectBoxStore 尚未初始化。请在 main() 中调用 ObjectBoxStore.init() 后再使用。',
      );
    }
    return _instance!;
  }

  /// ObjectBox 数据库引擎的核心对象
  ///
  /// Store 是 ObjectBox 的顶层对象，代表完整的数据库实例。
  /// 所有读写操作最终都通过 Store 执行。Store 内部管理：
  /// - 数据库文件的打开和关闭
  /// - 内存缓冲区和缓存管理
  /// - 事务的提交和回滚
  /// - 并发读取控制（多个 reader 可同时读取，但 writer 串行执行）
  late final Store _store;

  /// 帖子的数据容器（Box）
  ///
  /// `Box<Post>` 是 Post 实体在数据库中的"入口"。
  /// 每个 Box 对应一张数据库表。通过 Box 可以执行：
  /// - put: 新增或更新记录（UPSERT 语义）
  /// - get: 根据 ID 查询单条记录
  /// - getAll: 获取所有记录
  /// - remove: 删除记录
  /// - query: 构建复杂查询条件
  late final Box<Post> postBox;

  /// 标签的数据容器
  late final Box<Tag> tagBox;

  /// 图片元数据的数据容器
  late final Box<ImageMeta> imageBox;

  /// 初始化数据库
  ///
  /// 此方法完成以下步骤：
  /// 1. 获取设备上的持久化存储目录（通常位于应用私有目录中）
  /// 2. 在该目录下创建 `objectbox` 子目录，作为数据库的根目录
  /// 3. 调用 openStore() 打开或创建数据库文件
  /// 4. 绑定三个 Box 到对应的实体类
  ///
  /// path_provider 的作用：
  /// - getApplicationDocumentsDirectory() 返回应用专有的写入目录
  /// - 该目录在应用卸载时会被系统清理，因此数据不会残留
  /// - Android 路径：/data/data/com.example.mynotes/files/
  /// - iOS 路径：`<Application_Home>/Documents/`
  static Future<void> init() async {
    if (_instance != null) {
      // 防止重复初始化：在一个进程中，数据库只需打开一次
      return;
    }

    // 获取持久化存储目录
    final dir = await getApplicationDocumentsDirectory();

    // 打开 ObjectBox 数据库
    // 参数说明：
    //   directory: 数据库文件的存储路径；如果不指定，ObjectBox 会使用默认路径
    //   queriesCaseSensitiveDefault: 默认查询区分大小写（保持与 SQL 一致的行为）
    final store = openStore(
      directory: '${dir.path}/objectbox',
      queriesCaseSensitiveDefault: true,
    );

    _instance = ObjectBoxStore._internal(store);
  }

  /// 私有构造函数，由 [init] 调用
  ///
  /// 之所以是私有的，是为了防止外部代码通过 new ObjectBoxStore() 创建多个实例，
  /// 从而破坏单例模式的约定。
  ObjectBoxStore._internal(Store store) {
    _store = store;
    postBox = store.box<Post>();
    tagBox = store.box<Tag>();
    imageBox = store.box<ImageMeta>();
  }

  // ============================================================
  // 通用操作
  // ============================================================

  /// 获取原始 Store 对象
  ///
  /// 当需要使用事务、批量操作等功能时，可以通过此方法获取底层 Store。
  /// 在事务中执行多个操作比逐个操作更高效，因为：
  /// - 事务将多次磁盘写入合并为一次
  /// - 出现异常时自动回滚，保证数据一致性
  Store get store => _store;

  // ============================================================
  // Post CRUD（帖子增删改查）
  // ============================================================

  /// 保存帖子（新增或更新）
  ///
  /// ObjectBox 的 put 方法是 UPSERT 语义：
  /// - 如果 Post.id == 0（新对象），则执行 INSERT 操作，写入新记录
  /// - 如果 Post.id != 0 且数据库中存在该 ID，则执行 UPDATE 操作，覆盖旧记录
  /// - 如果 Post.id != 0 但数据库中没有该 ID，则执行 INSERT 操作，使用指定 ID
  ///
  /// 返回值：写入后的 ID（首次保存时，ObjectBox 分配的新 ID）
  ///
  /// 关联的处理：
  /// - Post.tags 中的 ToMany 关系会自动被 ObjectBox 持久化
  /// - Post.images 中的 Backlink 关系也会一起保存
  int putPost(Post post) {
    return postBox.put(post);
  }

  /// 根据 ID 获取单篇帖子
  ///
  /// [id] 数据库主键 ID。
  /// 如果 ID 不存在，返回 null。
  /// 查询性能：O(1) — 基于 B+ 树索引的直接查找
  Post? getPost(int id) {
    return postBox.get(id);
  }

  /// 获取所有帖子，按更新时间降序排列
  ///
  /// 使用 ObjectBox 的 Query API 构建查询：
  /// - order(Post_.updatedAt, flags: Order.descending) 确保最新帖子排在最前面
  /// - 实际场景中需要过滤掉 isDeleted == true 的记录
  ///
  /// 注意：Query 对象需要调用 build() 创建，执行完毕后调用 close() 释放资源。
  /// 如果忘记 close()，会导致内存泄漏。
  List<Post> getAllPosts() {
    return postBox.getAll();
  }

  /// 获取所有非删除状态的帖子，按更新时间降序
  ///
  /// ObjectBox Query 构建流程：
  /// 1. postBox.query() 开始构建查询
  /// 2. equals / notEquals / greaterThan 等方法添加过滤条件
  /// 3. order() 添加排序规则
  /// 4. build() 生成 Query 对象
  /// 5. find() 执行查询并返回结果
  List<Post> getActivePosts() {
    final query = postBox
        .query(Post_.isDeleted.notEquals(true))
        .order(Post_.updatedAt, flags: Order.descending)
        .build();

    final results = query.find();
    // 关闭查询对象，释放内部资源
    query.close();
    return results;
  }

  /// 获取回收站中的帖子（软删除的帖子）
  List<Post> getDeletedPosts() {
    final query = postBox
        .query(Post_.isDeleted.equals(true))
        .order(Post_.updatedAt, flags: Order.descending)
        .build();

    final results = query.find();
    query.close();
    return results;
  }

  /// 根据 UUID 查找帖子
  ///
  /// UUID 是业务层面的全局唯一标识，主要用于跨设备同步场景。
  /// 虽然在单机使用中可以用数据库 ID 直接查找，
  /// 但在一条记录被导入到另一台设备时，数据库 ID 可能不同，
  /// 而 UUID 保持不变，所以 UUID 是更可靠的查找凭据。
  ///
  /// findUnique() 是 Query 的特殊方法：
  /// - 如果匹配到唯一记录，返回该记录
  /// - 如果没有匹配，返回 null
  /// - 如果匹配到多条（理论上不应该，因为 uuid 应该有唯一约束），抛出异常
  Post? getPostByUuid(String uuid) {
    final query = postBox.query(Post_.uuid.equals(uuid)).build();
    final result = query.findUnique();
    query.close();
    return result;
  }

  /// 搜索帖子内容（关键词匹配）
  ///
  /// contains 方法执行子字符串匹配，相当于 SQL 的 LIKE '%keyword%'。
  /// 注意：
  /// - 子字符串查询效率较低（全表扫描），大量数据时需要考虑使用全文搜索库
  /// - ObjectBox 本身支持 full-text search，但需要额外配置
  /// - 对于日记应用（通常几百到几千条），子字符串匹配的性能完全够用
  List<Post> searchPosts(String keyword) {
    final query = postBox
        .query(Post_.content.contains(keyword, caseSensitive: false))
        .order(Post_.updatedAt, flags: Order.descending)
        .build();

    final results = query.find();
    query.close();
    return results;
  }

  // ============================================================
  // 日历查询（按日期检索）
  // ============================================================

  /// 获取指定日期的所有非删除帖子，按更新时间降序
  ///
  /// [date] 要查询的日期（忽略时间部分，只使用年月日）
  ///
  /// 实现说明：
  /// - 将输入日期转换为当天 00:00:00 到次日 00:00:00 时间范围
  /// - 使用 greaterOrEqual + lessThan 实现 between 语义
  /// - 正确处理时区：DateTime 不携带时区信息，依赖系统本地时间
  List<Post> getPostsByDate(DateTime date) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final startMs = startOfDay.millisecondsSinceEpoch;
    final endMs = endOfDay.millisecondsSinceEpoch;

    final query = postBox
        .query(
            Post_.isDeleted.notEquals(true)
                .and(Post_.updatedAt.greaterOrEqual(startMs))
                .and(Post_.updatedAt.lessThan(endMs)))
        .order(Post_.updatedAt, flags: Order.descending)
        .build();

    final results = query.find();
    query.close();
    return results;
  }

  /// 获取指定月份内有日记的所有日期（用于日历记忆足迹标记）
  ///
  /// [year] 年份，如 2025
  /// [month] 月份，1-12
  ///
  /// 返回值：该月内有帖子的日期列表（day of month，如 [3, 7, 15]）
  List<int> getDaysWithPostsInMonth(int year, int month) {
    final startOfMonth = DateTime(year, month, 1);
    final startOfNextMonth = DateTime(year, month + 1, 1);
    final startMs = startOfMonth.millisecondsSinceEpoch;
    final endMs = startOfNextMonth.millisecondsSinceEpoch;

    final query = postBox
        .query(
            Post_.isDeleted.notEquals(true)
                .and(Post_.updatedAt.greaterOrEqual(startMs))
                .and(Post_.updatedAt.lessThan(endMs)))
        .build();

    final posts = query.find();
    query.close();

    // 提取不重复的日期（按天去重）
    final daySet = posts.map((p) => p.updatedAt.day).toSet();
    final days = daySet.toList()..sort();
    return days;
  }

  /// 软删除帖子（将 isDeleted 设为 true）
  ///
  /// 为什么不直接物理删除？
  /// 1. 回收站功能：用户可以恢复被误删的帖子
  /// 2. 数据完整性：删除帖子的图片关联得以保留
  /// 3. 同步安全：删除标记可以传输到其他设备
  ///
  /// 物理删除（彻底销毁）需要在软删除一段时间后执行，例如 30 天后自动清理。
  void softDeletePost(int id) {
    final post = postBox.get(id);
    if (post != null) {
      post.isDeleted = true;
      post.updatedAt = DateTime.now();
      postBox.put(post);
    }
  }

  /// 物理删除帖子（不可恢复）
  ///
  /// 此操作从数据库中彻底移除记录。执行前应确认用户意图。
  /// 同时也会删除帖子的所有关联图片文件。
  void hardDeletePost(int id) {
    final post = postBox.get(id);
    if (post != null) {
      // 删除关联的图片文件
      for (final image in post.images) {
        final file = File(image.localPath);
        if (file.existsSync()) {
          file.deleteSync();
        }
        imageBox.remove(image.id);
      }
      // 清除标签关联后删除帖子
      post.tags.clear();
      postBox.remove(id);
    }
  }

  /// 恢复软删除的帖子
  void restorePost(int id) {
    final post = postBox.get(id);
    if (post != null) {
      post.isDeleted = false;
      post.updatedAt = DateTime.now();
      postBox.put(post);
    }
  }

  // ============================================================
  // Tag CRUD（标签增删改查）
  // ============================================================

  /// 创建新标签
  ///
  /// 如果标签名称已存在，ObjectBox 会因 @Unique() 约束而抛出异常。
  /// 调用方应该在调用前先检查名称是否已存在。
  int putTag(Tag tag) {
    return tagBox.put(tag);
  }

  /// 根据名称查找标签
  ///
  /// 标签名称使用了 @Unique() 约束，因此最多只有一条匹配记录。
  Tag? getTagByName(String name) {
    final query = tagBox.query(Tag_.name.equals(name)).build();
    final result = query.findUnique();
    query.close();
    return result;
  }

  /// 获取所有标签
  List<Tag> getAllTags() {
    return tagBox.getAll();
  }

  /// 删除标签（同时清除所有帖子中对该标签的关联）
  ///
  /// 删除标签前需要先清除所有关联，否则 ObjectBox 会因为
  /// 关联表中有引用而拒绝删除。
  void deleteTag(int id) {
    final tag = tagBox.get(id);
    if (tag != null) {
      // 查找所有关联此标签的帖子
      // linkMany 不能链式调用：它是 Builder 上的方法，在已有 builder 上调用来添加条件
      final builder = postBox.query();
      builder.linkMany(Post_.tags, Tag_.id.equals(id));
      final query = builder.build();
      final posts = query.find();
      query.close();

      // 从所有关联帖子中移除这个标签
      for (final post in posts) {
        post.tags.remove(tag);
        postBox.put(post);
      }

      // 最后删除标签本身
      tagBox.remove(id);
    }
  }

  // ============================================================
  // ImageMeta CRUD（图片元数据增删改查）
  // ============================================================

  /// 为帖子添加图片
  ///
  /// [postId] 目标帖子的 ID
  /// [localPath] 图片文件在设备上的本地路径
  ///
  /// 注意：
  /// 1. localPath 必须在调用此方法之前已经确认文件存在
  /// 2. 数据库只存储路径，不检查文件系统状态
  /// 3. 如果图片文件被外部删除（如用户清理缓存），ImageMeta 不会自动更新
  int addImage(int postId, String localPath) {
    final post = postBox.get(postId);
    if (post == null) {
      throw ArgumentError('Post with id $postId not found');
    }

    final image = ImageMeta(localPath: localPath);
    image.post.target = post; // 建立关联关系
    return imageBox.put(image);
  }

  /// 获取某篇帖子的所有图片
  List<ImageMeta> getImagesForPost(int postId) {
    final post = postBox.get(postId);
    if (post == null) return [];
    return post.images.toList();
  }

  /// 删除图片元数据以及对应的文件
  ///
  /// 此方法同时执行两个操作：
  /// 1. 从数据库中删除 ImageMeta 记录
  /// 2. 从文件系统中删除图片文件
  void deleteImage(int imageId) {
    final image = imageBox.get(imageId);
    if (image != null) {
      // 删除文件系统中的图片文件
      final file = File(image.localPath);
      if (file.existsSync()) {
        file.deleteSync();
      }
      // 删除数据库记录
      imageBox.remove(imageId);
    }
  }

  // ============================================================
  // 生命周期
  // ============================================================

  /// 关闭数据库连接
  ///
  /// 在应用退出前必须调用此方法，否则可能导致：
  /// - 未完成的数据写入丢失
  /// - 数据库文件损坏
  /// - 内存泄漏（文件句柄未释放）
  ///
  /// 在 Flutter 中，建议在 App 的 dispose 或 WidgetsBinding 的
  /// didRequestAppExit 回调中调用此方法。
  void close() {
    _store.close();
    _instance = null;
  }
}