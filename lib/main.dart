import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'services/objectbox_store.dart';
import 'ui/publish_screen.dart';

void main() async {
  // 确保 Flutter 框架初始化完成（使用原生插件前必须调用）
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 ObjectBox 数据库
  // 此操作会打开或创建数据库文件，完成索引加载等准备工作。
  // 必须在 runApp 之前完成，因为 UI 依赖数据库实例。
  await ObjectBoxStore.init();

  // ProviderScope 是 Riverpod 的顶层容器
  // 所有 Provider 的实例都存储在这个容器中。
  // 必须包裹在整个应用的最外层。
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'mynotes',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      // 直接以发布页作为首页（后续阶段会添加路由导航）
      home: const PublishScreen(),
    );
  }
}