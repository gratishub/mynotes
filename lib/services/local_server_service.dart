import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:network_info_plus/network_info_plus.dart';

import 'package:flutter/services.dart' show rootBundle;

import '../services/objectbox_store.dart';

/// CORS 中间件：为所有响应添加跨域头
///
/// 允许来自任何来源的跨域请求，方便开发调试。
final _corsMiddleware = createMiddleware(
  requestHandler: (Request request) {
    // 直接响应 OPTIONS 预检请求
    if (request.method == 'OPTIONS') {
      return Response.ok('', headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      });
    }
    return null; // 其他请求继续处理
  },
  responseHandler: (Response response) {
    return response.change(
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      },
    );
  },
);

/// 安全日志中间件：记录所有 API 请求
final _loggingMiddleware = createMiddleware(
  requestHandler: (Request request) {
    // ignore: avoid_print — 开发服务器日志输出
    print('[LocalServer] ${request.method} ${request.url}');
    return null; // 继续处理请求
  },
);

/// 手机端微型 Web 服务器
///
/// 在同一局域网下，电脑可以通过浏览器访问手机上的日记数据。
/// 使用 shelf + shelf_router 作为 HTTP 引擎，network_info_plus 获取局域网 IP。
class LocalServerService {
  HttpServer? _server;
  late final Router _router;
  int? _port;

  /// 服务器是否正在运行
  bool get isRunning => _server != null;

  /// 服务器监听的端口号（未启动时为 null）
  int? get port => _port;

  /// 构造函数：注册路由
  LocalServerService() {
    _router = Router();
    _setupRoutes();
  }

  /// 注册所有 API 路由
  void _setupRoutes() {
    // 测试连通性
    _router.get('/api/ping', (Request request) {
      return Response.ok('Server is running');
    });

    // 提供 Web 前端页面
    _router.get('/', (Request request) async {
      try {
        final html = await rootBundle.loadString('assets/web/index.html');
        return Response.ok(
          html,
          headers: {'Content-Type': 'text/html; charset=utf-8'},
        );
      } catch (e) {
        return Response.internalServerError(body: 'Failed to load index.html');
      }
    });

    // 获取所有非删除状态的日记列表
    _router.get('/api/posts', (Request request) {
      final posts = ObjectBoxStore.instance.getActivePosts();
      final list = posts.map((post) {
        return {
          'id': post.id,
          'uuid': post.uuid,
          'content': post.content,
          'updatedAt': post.updatedAt.millisecondsSinceEpoch,
          'images': post.images.map((img) {
            return {
              'id': img.id,
              'url': '/api/images/${img.id}',
            };
          }).toList(),
        };
      }).toList();
      return Response.ok(
        jsonEncode(list),
        headers: {'Content-Type': 'application/json'},
      );
    });

    // 提供图片文件流
    _router.get('/api/images/<id>', (Request request, String id) {
      final imageId = int.tryParse(id);
      if (imageId == null) {
        return Response.badRequest(body: 'Invalid image ID');
      }

      final image = ObjectBoxStore.instance.imageBox.get(imageId);
      if (image == null) {
        return Response.notFound('Image not found');
      }

      final file = File(image.localPath);
      if (!file.existsSync()) {
        return Response.notFound('Image file not found');
      }

      // 根据文件扩展名推断 content-type
      final ext = image.localPath.split('.').last.toLowerCase();
      final contentType = switch (ext) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        'bmp' => 'image/bmp',
        _ => 'application/octet-stream',
      };

      return Response.ok(
        file.openRead(),
        headers: {'Content-Type': contentType},
      );
    });
  }

  /// 启动 Web 服务器
  ///
  /// 绑定到 [InternetAddress.anyIPv4] 端口 [port]（默认 8080）。
  /// 如果指定端口被占用，自动尝试下一个端口（最多尝试 10 次）。
  /// 返回实际监听的端口号。
  Future<int> start({int port = 8080}) async {
    if (_server != null) {
      return _port!;
    }

    // 尝试绑定端口，如果被占用则递增
    for (int attempt = 0; attempt < 10; attempt++) {
      try {
        final handler = Pipeline()
            .addMiddleware(_corsMiddleware)
            .addMiddleware(_loggingMiddleware)
            .addHandler(_router.call);

        _server = await shelf_io.serve(
          handler,
          InternetAddress.anyIPv4,
          port + attempt,
        );
        _port = port + attempt;
        break;
      } on SocketException catch (_) {
        // 端口被占用，继续尝试下一个
        continue;
      }
    }

    if (_server == null) {
      throw StateError('无法启动服务器：端口 $port-${port + 9} 均被占用');
    }

    return _port!;
  }

  /// 停止 Web 服务器
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _port = null;
  }

  /// 获取当前手机的局域网 IP 地址
  ///
  /// 使用 [NetworkInfo.getWifiIP] 获取。
  /// 返回 null 表示无法获取（如未连接 WiFi）。
  Future<String?> getIpAddress() async {
    final networkInfo = NetworkInfo();
    try {
      return await networkInfo.getWifiIP();
    } catch (_) {
      return null;
    }
  }

  /// 释放资源
  void dispose() {
    _server?.close(force: true);
    _server = null;
    _port = null;
  }
}
