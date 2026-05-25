import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'services/objectbox_store.dart';
import 'services/background_service.dart';
import 'ui/home_screen.dart';

void main() async {
  // 确保 Flutter 框架初始化完成（使用原生插件前必须调用）
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 ObjectBox 数据库
  // 此操作会打开或创建数据库文件，完成索引加载等准备工作。
  // 必须在 runApp 之前完成，因为 UI 依赖数据库实例。
  await ObjectBoxStore.init();

  // 配置后台前台服务（通知渠道 + Service 回调注册）
  // 不自动启动，仅在用户开启局域网同步时由 LanSyncScreen 激活。
  await configureBackgroundService();

  // ProviderScope 是 Riverpod 的顶层容器
  // 所有 Provider 的实例都存储在这个容器中。
  // 必须包裹在整个应用的最外层。
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const warmOrange = Color(0xFFFF9472);

    return MaterialApp(
      title: 'mynotes',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: warmOrange,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'DiaryFont',
        scaffoldBackgroundColor: const Color(0xFFF8F7F4),

        textTheme: const TextTheme(
          bodyLarge: TextStyle(
            fontSize: 16,
            height: 1.8,
            letterSpacing: 0.5,
            color: Color(0xFF3A3A3A),
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            height: 1.7,
            letterSpacing: 0.4,
            color: Color(0xFF3A3A3A),
          ),
        ),

        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Color(0xFF3A3A3A),
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
          iconTheme: IconThemeData(color: Color(0xFF3A3A3A)),
        ),

        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}