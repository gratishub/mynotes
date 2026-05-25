import 'dart:async';
import 'dart:io';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const _channelId = 'mynotes_lan_channel';
const _channelName = 'Mynotes 局域网服务';
const _notificationId = 888;

final _notificationsPlugin = FlutterLocalNotificationsPlugin();

/// 配置并初始化后台前台服务
///
/// 当用户启动局域网 Web Server 后，激活此前台服务。
/// 前台服务会在通知栏显示常驻通知，阻止 Android 系统杀掉进程。
/// 必须在 runApp() 之前调用（需在 main 中执行）。
Future<void> configureBackgroundService() async {
  // 创建 Android 通知渠道（Android 8+ 必须）
  if (Platform.isAndroid) {
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: '局域网 Web 服务器后台运行通知',
      importance: Importance.low,
    );

    await _notificationsPlugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: _channelId,
      initialNotificationTitle: 'Mynotes',
      initialNotificationContent: '局域网服务运行中…',
      foregroundServiceNotificationId: _notificationId,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
    ),
  );
}

/// 前台服务主入口
///
/// 在后台 isolate 中执行（@pragma 确保 AOT 编译保留此入口）。
/// - 监听 UI 层发来的停止指令
/// - 定期更新通知栏信息，向系统发送存活信号
@pragma('vm:entry-point')
void onStart(ServiceInstance service) {
  // 监听 UI 层发来的停止指令
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // 定期更新通知内容，向系统表明服务存活
  // setForegroundNotificationInfo 仅在 Android 上可用
  Timer.periodic(const Duration(seconds: 10), (_) {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'Mynotes',
        content: '局域网服务运行中…',
      );
    }
  });
}
