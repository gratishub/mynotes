import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/objectbox_store.dart';

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