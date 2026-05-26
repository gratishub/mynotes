import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:network_info_plus/network_info_plus.dart';

import 'package:flutter/services.dart' show rootBundle;
import 'package:uuid/uuid.dart';

import '../services/objectbox_store.dart';
import '../models/post.dart';

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
  String? _cachedHtml; // 缓存 Web 页面
  String? _apiToken; // API 鉴权 Token

  /// 服务器是否正在运行
  bool get isRunning => _server != null;

  /// 当前 API 鉴权 Token（8 位随机字符串，用于桌面端请求鉴权）
  String? get apiToken => _apiToken;

  /// 服务器监听的端口号（未启动时为 null）
  int? get port => _port;

  /// 构造函数：注册路由
  LocalServerService() {
    _router = Router();
    _setupRoutes();
  }

  /// API 鉴权中间件
  ///
  /// 除 `/`（Web 主页）和 `/api/ping`（连通性测试）外，
  /// 所有 `/api/*` 请求必须携带 `Authorization: Bearer <_apiToken>` 头。
  /// Token 不匹配或缺失时返回 401 Unauthorized。
  Middleware _authMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        // 放行 Web 主页和 ping
        final path = request.requestedUri.path;
        if (path == '/' || path == '/api/ping') {
          return innerHandler(request);
        }

        // 仅对 /api/* 路径检查鉴权
        if (path.startsWith('/api/')) {
          final authHeader = request.headers['authorization'];
          if (authHeader == null || !authHeader.startsWith('Bearer ')) {
            return Response.unauthorized('Missing or invalid Authorization header');
          }

          final token = authHeader.substring('Bearer '.length).trim();
          if (token != _apiToken) {
            return Response.unauthorized('Invalid API token');
          }
        }

        return innerHandler(request);
      };
    };
  }

  /// 注册所有 API 路由
  void _setupRoutes() {
    // 测试连通性
    _router.get('/api/ping', (Request request) {
      return Response.ok('Server is running');
    });

    // 提供 Web 前端页面
    _router.get('/', (Request request) async {
      final html = await _loadHtml();
      if (html == null) {
        return Response.internalServerError(
          body: 'Failed to load index.html (asset not found or not bundled)',
        );
      }
      return Response.ok(
        html,
        headers: {'Content-Type': 'text/html; charset=utf-8'},
      );
    });

    // 获取所有非删除状态的日记列表
    _router.get('/api/posts', (Request request) {
      final posts = ObjectBoxStore.instance.getActivePosts();
      final list = posts.map((post) {
        return {
          'uuid': post.uuid,
          'content': post.content,
          'tags': post.tags.map((tag) => tag.name).toList(),
          'createdAt': post.createdAt.millisecondsSinceEpoch,
          'updatedAt': post.updatedAt.millisecondsSinceEpoch,
          'images': post.images.map((img) {
            return {
              'localPath': img.localPath,
              'remoteUrl': '',
            };
          }).toList(),
        };
      }).toList();
      return Response.ok(
        jsonEncode(list),
        headers: {'Content-Type': 'application/json'},
      );
    });

    // 从电脑端创建新日记
    _router.post('/api/posts', (Request request) async {
      try {
        final body = await request.readAsString();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final content = data['content'] as String? ?? '';

        final post = Post(
          uuid: const Uuid().v4(),
          content: content,
          updatedAt: DateTime.now(),
          isDeleted: false,
        );

        ObjectBoxStore.instance.putPost(post);

        return Response.ok(
          jsonEncode({'success': true, 'id': post.id}),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.badRequest(
          body: jsonEncode({'success': false, 'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
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

  /// 加载内置 Web 页面，优先使用缓存
  Future<String?> _loadHtml() async {
    if (_cachedHtml != null) return _cachedHtml;

    try {
      _cachedHtml = await rootBundle.loadString('assets/web/index.html');
      return _cachedHtml;
    } catch (e) {
      // ignore: avoid_print
      print('[LocalServer] 加载 index.html 失败: $e');
      return null;
    }
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

    // 预加载 HTML，确保 asset 可用
    final html = await _loadHtml();
    if (html == null) {
      throw StateError('无法加载内置 Web 页面，请确认 assets/web/index.html 已正确打包');
    }

    // 生成新的 API Token
    _apiToken = const Uuid().v4().substring(0, 8);

    // 尝试绑定端口，如果被占用则递增
    for (int attempt = 0; attempt < 10; attempt++) {
      try {
        final handler = Pipeline()
            .addMiddleware(_corsMiddleware)
            .addMiddleware(_authMiddleware())
            .addMiddleware(_loggingMiddleware)
            .addHandler(_router.call);

        _server = await shelf_io.serve(
          handler,
          InternetAddress.anyIPv4,
          port + attempt,
        );
        _port = port + attempt;
        // ignore: avoid_print
        print('[LocalServer] 已启动: ${_server?.address.host}:$_port');
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
    _apiToken = null;
  }

  /// 获取当前手机的局域网 IP 地址
  ///
  /// 优先使用 [NetworkInfo.getWifiIP]，如果返回的是虚拟网卡 IP（如 Docker 的 172.x.x.x），
  /// 则退而枚举所有网络接口，寻找真实的 WiFi IP。
  Future<String?> getIpAddress() async {
    // 方法1：使用 network_info_plus
    try {
      final networkInfo = NetworkInfo();
      final wifiIp = await networkInfo.getWifiIP();
      if (wifiIp != null && wifiIp.isNotEmpty && !_isVirtualIp(wifiIp)) {
        return wifiIp;
      }
    } catch (_) {}

    // 方法2：枚举所有网络接口，寻找真实 IP
    try {
      final interfaces = await NetworkInterface.list();
      // 优先返回 192.168.x.x 或 10.x.x.x（典型的 WiFi 网段）
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 &&
              _isLikelyWifiIp(addr.address)) {
            return addr.address;
          }
        }
      }
      // 兜底：返回第一个非 loopback 的 IPv4 地址
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {}

    return null;
  }

  /// Docker 等虚拟网卡常用 172.16.0.0/12 网段
  bool _isVirtualIp(String ip) {
    if (ip.startsWith('172.')) {
      final parts = ip.split('.');
      if (parts.length == 4) {
        final second = int.tryParse(parts[1]) ?? 0;
        if (second >= 16 && second <= 31) return true;
      }
    }
    return false;
  }

  /// 判断是否属于典型家庭/办公 WiFi 网段
  bool _isLikelyWifiIp(String ip) {
    return ip.startsWith('192.168.') || ip.startsWith('10.');
  }

  /// 获取所有局域网 IP 地址（用于 UI 展示多个地址）
  Future<List<String>> getAllLocalIps() async {
    final ips = <String>{};

    // 从 network_info_plus 获取
    try {
      final networkInfo = NetworkInfo();
      final wifiIp = await networkInfo.getWifiIP();
      if (wifiIp != null && wifiIp.isNotEmpty && !_isVirtualIp(wifiIp)) {
        ips.add(wifiIp);
      }
    } catch (_) {}

    // 枚举所有接口
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            ips.add(addr.address);
          }
        }
      }
    } catch (_) {}

    return ips.toList();
  }

  /// 释放资源
  void dispose() {
    _server?.close(force: true);
    _server = null;
    _port = null;
  }
}
