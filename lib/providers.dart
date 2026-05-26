import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/objectbox_store.dart';
import 'services/local_server_service.dart';
import 'models/post.dart';
import 'objectbox.g.dart';

/// ObjectBox 数据库实例提供者
///
/// Riverpod 的 Provider 是一种"惰性求值"的单例容器：
/// - 第一次被 watch 或 read 时创建值
/// - 之后每次访问都返回同一个实例
/// - 组件销毁时不会影响 Provider（生命周期由 Riverpod 管理）
///
/// 这里我们将 ObjectBoxStore 单例包装成 Provider，
/// 方便后续页面通过 ref.watch(objectBoxProvider) 访问数据库。
final objectBoxProvider = Provider<ObjectBoxStore>((ref) {
  return ObjectBoxStore.instance;
});

/// 局域网服务状态
class LanServerState {
  final bool isRunning;
  final String? ipAddress;
  final int? port;
  final String? apiToken;

  const LanServerState({
    this.isRunning = false,
    this.ipAddress,
    this.port,
    this.apiToken,
  });

  LanServerState copyWith({
    bool? isRunning,
    String? ipAddress,
    int? port,
    String? apiToken,
  }) {
    return LanServerState(
      isRunning: isRunning ?? this.isRunning,
      ipAddress: ipAddress ?? this.ipAddress,
      port: port ?? this.port,
      apiToken: apiToken ?? this.apiToken,
    );
  }

  String get url => ipAddress != null && port != null
      ? 'http://$ipAddress:$port'
      : '';
}

/// 局域网服务状态管理器
///
/// 使用 Riverpod 3.x 的 [Notifier] 模式管理 [LocalServerService] 生命周期。
class LanServerNotifier extends Notifier<LanServerState> {
  late final LocalServerService _service;

  @override
  LanServerState build() {
    _service = LocalServerService();
    ref.onDispose(() => _service.dispose());
    return const LanServerState();
  }

  /// 启动服务
  Future<void> start() async {
    final port = await _service.start();
    final ip = await _service.getIpAddress();
    state = LanServerState(
      isRunning: true,
      ipAddress: ip,
      port: port,
      apiToken: _service.apiToken,
    );
  }

  /// 停止服务
  Future<void> stop() async {
    await _service.stop();
    state = const LanServerState();
  }

  /// 刷新 IP（如 WiFi 切换后）
  Future<void> refreshIp() async {
    final ip = await _service.getIpAddress();
    if (state.isRunning) {
      state = state.copyWith(ipAddress: ip);
    }
  }
}

final lanServerProvider =
    NotifierProvider<LanServerNotifier, LanServerState>(
  LanServerNotifier.new,
);

/// 活跃帖子流 — 响应式数据源
///
/// 监听 ObjectBox 中 Post 实体的数据变更，自动推送最新列表。
/// 过滤掉已删除的帖子，按更新时间降序排列。
/// 手机端发布或电脑端通过 API 写入时，UI 自动刷新。
final activePostsProvider = StreamProvider<List<Post>>((ref) {
  final store = ref.watch(objectBoxProvider);

  return store.postBox
      .query(Post_.isDeleted.notEquals(true))
      .order(Post_.updatedAt, flags: Order.descending)
      .watch(triggerImmediately: true)
      .map((query) => query.find());
});