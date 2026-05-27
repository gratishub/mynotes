import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../services/objectbox_store.dart';
import '../services/image_processor.dart';
import '../models/post.dart';
import '../models/tag.dart';
import '../models/image_meta.dart';

/// CORS 中间件：为所有响应添加跨域头
///
/// 允许来自任何来源的跨域请求，支持 Obsidian Electron 环境。
final _corsMiddleware = createMiddleware(
  requestHandler: (Request request) {
    // 直接响应 OPTIONS 预检请求（不走鉴权和业务逻辑）
    if (request.method == 'OPTIONS') {
      return Response.ok('', headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Origin, Content-Type, Authorization',
        'Access-Control-Max-Age': '86400', // 缓存 24 小时，减少预检频率
      });
    }
    return null; // 其他请求继续处理
  },
  responseHandler: (Response response) {
    return response.change(
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Origin, Content-Type, Authorization',
        'Access-Control-Expose-Headers': 'Content-Length, Content-Type',
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
  String? _apiToken; // API 鉴权 Token
  String? _imagesDirPath; // 图片目录绝对路径缓存

  /// 已连接客户端追踪（IP → 客户端信息）
  final Map<String, _ClientInfo> _clients = {};

  /// Token 仅在首次启动时生成，之后复用
  static String? _persistentToken;

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

  /// 从 Content-Type 中提取 boundary
  static String? _extractBoundary(String contentType) {
    final match = RegExp(r'boundary=([^\s;]+)').firstMatch(contentType);
    return match?.group(1);
  }

  /// 解析 multipart 数据，提取文件列表
  static List<Map<String, dynamic>> _parseMultipart(List<int> bytes, String boundary) {
    final files = <Map<String, dynamic>>[];
    final boundaryBytes = '--$boundary'.codeUnits;
    final endBoundaryBytes = '--$boundary--'.codeUnits;

    int start = 0;
    while (start < bytes.length) {
      int boundaryPos = _indexOfBytes(bytes, boundaryBytes, start);
      if (boundaryPos == -1) break;

      start = boundaryPos + boundaryBytes.length;
      if (start < bytes.length && bytes[start] == 13) start++;
      if (start < bytes.length && bytes[start] == 10) start++;

      if (_indexOfBytes(bytes, endBoundaryBytes, start - 2) == start - 2) break;

      int nextBoundary = _indexOfBytes(bytes, boundaryBytes, start);
      if (nextBoundary == -1) break;

      final partBytes = bytes.sublist(start, nextBoundary - 2);
      final partStr = utf8.decode(partBytes, allowMalformed: true);
      final filenameMatch = RegExp(r'filename="([^"]+)"').firstMatch(partStr);
      if (filenameMatch != null) {
        int bodyStart = 0;
        for (int i = 0; i < partBytes.length - 3; i++) {
          if (partBytes[i] == 13 && partBytes[i + 1] == 10 &&
              partBytes[i + 2] == 13 && partBytes[i + 3] == 10) {
            bodyStart = i + 4;
            break;
          }
        }
        files.add({
          'filename': filenameMatch.group(1)!,
          'data': partBytes.sublist(bodyStart),
        });
      }
      start = nextBoundary + boundaryBytes.length;
    }
    return files;
  }

  /// 在字节数组中查找模式的位置
  static int _indexOfBytes(List<int> bytes, List<int> pattern, int start) {
    outer:
    for (int i = start; i <= bytes.length - pattern.length; i++) {
      for (int j = 0; j < pattern.length; j++) {
        if (bytes[i + j] != pattern[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  /// 客户端追踪中间件
  ///
  /// 记录每个请求的 IP、User-Agent 和最后活跃时间。
  /// 超过 60 秒未请求的客户端会被自动清理。
  Middleware _clientTrackingMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        final ua = request.headers['user-agent'] ?? 'Unknown';
        final ip = _extractClientIp(request);
        // ignore: avoid_print
        print('[LocalServer] Client: ip=$ip ua=${ua.substring(0, ua.length.clamp(0, 50))}');

        // 过滤本机请求
        if (ip != '127.0.0.1' && ip != '::1') {
          final key = '$ip|$ua';
          _clients[key] = _ClientInfo(
            ip: ip,
            userAgent: ua,
            lastSeen: DateTime.now(),
          );
        }
        return innerHandler(request);
      };
    };
  }

  /// 提取客户端 IP（多重降级策略）
  static String _extractClientIp(Request request) {
    // 1. 代理头
    final forwarded = request.headers['x-forwarded-for'];
    if (forwarded != null && forwarded.isNotEmpty) return forwarded.split(',').first.trim();
    final realIp = request.headers['x-real-ip'];
    if (realIp != null && realIp.isNotEmpty) return realIp;
    // 2. shelf 连接信息
    try {
      final info = request.context['shelf.io.connection_info'];
      if (info != null) {
        final addr = (info as dynamic).remoteAddress;
        if (addr != null) return addr.toString();
      }
    } catch (_) {}
    // 3. 降级：用 User-Agent 哈希作为伪标识
    final ua = request.headers['user-agent'] ?? '';
    return 'client-${ua.hashCode.toRadixString(16)}';
  }

  /// API 鉴权中间件
  ///
  /// 除 `/`（Web 主页）和 `/api/ping`（连通性测试）外，
  /// 所有 `/api/*` 请求必须携带 `Authorization: Bearer <_apiToken>` 头。
  /// Token 不匹配或缺失时返回 401 Unauthorized。
  Middleware _authMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        // 放行 Web 主页、ping、status 和调试端点
        final path = request.requestedUri.path;
        if (path == '/' ||
            path == '/api/ping' ||
            path == '/api/status' ||
            path.startsWith('/api/debug')) {
          return innerHandler(request);
        }

        // 仅对非图片下载的 /api/* 路径检查鉴权（/api/upload 需要 auth）
        if (path.startsWith('/api/') &&
            !path.startsWith('/api/images/') &&
            !path.startsWith('/api/assets')) {
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

  /// 将 Markdown 内容中的绝对图片路径替换为服务器相对路径
  ///
  /// 匹配格式：`![](绝对路径)` 或 `<img src="绝对路径">`
  /// 替换为：`![](/images/文件名)`
  String _rewriteImagePaths(String content) {
    if (_imagesDirPath == null) return content;
    // 匹配 Markdown 图片语法中的绝对路径
    return content.replaceAllMapped(
      RegExp(r'!\[([^\]]*)\]\(([^)]+)\)'),
      (match) {
        final alt = match.group(1) ?? '';
        final path = match.group(2) ?? '';
        // 提取文件名（处理 Windows 和 Unix 路径）
        final fileName = path.split(RegExp(r'[/\\]')).last;
        if (fileName.isEmpty) return match.group(0)!;
        return '![$alt](/images/$fileName)';
      },
    );
  }

  /// 注册所有 API 路由
  void _setupRoutes() {
    // 获取已连接客户端列表
    _router.get('/api/clients', (Request request) {
      // 清理超过 60 秒未活动的客户端
      final now = DateTime.now();
      _clients.removeWhere(
        (key, client) => now.difference(client.lastSeen).inSeconds > 60,
      );
      final list = _clients.values.map((c) => c.toJson()).toList();
      return Response.ok(
        jsonEncode(list),
        headers: {'Content-Type': 'application/json'},
      );
    });

    // 测试连通性
    _router.get('/api/ping', (Request request) {
      return Response.ok('Server is running');
    });

    // 获取所有标签列表
    _router.get('/api/tags', (Request request) {
      final tags = ObjectBoxStore.instance.getAllTags();
      return Response.ok(
        jsonEncode(tags.map((t) => t.name).toList()),
        headers: {'Content-Type': 'application/json'},
      );
    });

    // 心跳检测 - 返回设备状态
    _router.get('/api/status', (Request request) {
      return Response.ok(
        jsonEncode({'status': 'ok', 'device': 'MyNotes'}),
        headers: {'Content-Type': 'application/json'},
      );
    });

    // 同步端点（Obsidian 插件专用）
    _router.get('/api/sync', (Request request) {
      final posts = ObjectBoxStore.instance.getSyncablePosts();

      // 直接从 imageBox 查询所有图片，按 postId 建索引
      final allImages = ObjectBoxStore.instance.imageBox.getAll();
      final imageMap = <int, List<ImageMeta>>{};
      for (final img in allImages) {
        imageMap.putIfAbsent(img.post.targetId, () => []);
        imageMap[img.post.targetId]!.add(img);
      }

      final list = posts.map((post) {
        return {
          'uuid': post.uuid,
          'content': post.content,
          'tags': post.tags.map((tag) => tag.name).toList(),
          'createdAt': post.createdAt.millisecondsSinceEpoch > 946684800000
              ? post.createdAt.millisecondsSinceEpoch
              : post.updatedAt.millisecondsSinceEpoch,
          'updatedAt': post.updatedAt.millisecondsSinceEpoch,
          'images': (imageMap[post.id] ?? []).map((img) {
            return {
              'localPath': img.localPath,
              'remoteUrl': '',
              'downloadUrl': '/api/images/${img.id}/download',
            };
          }).toList(),
        };
      }).toList();
      return Response.ok(
        jsonEncode(list),
        headers: {'Content-Type': 'application/json'},
      );
    });

    // 提供 Web 前端页面（注入 API Token）
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

    // 获取日记列表（支持日期和标签筛选）
    _router.get('/api/posts', (Request request) {
      final params = request.url.queryParameters;
      DateTime? startDate;
      DateTime? endDate;
      List<String>? selectedTags;

      if (params['startDate'] != null) {
        startDate = DateTime.tryParse(params['startDate']!);
      }
      if (params['endDate'] != null) {
        endDate = DateTime.tryParse(params['endDate']!);
      }
      if (params['tag'] != null && params['tag']!.isNotEmpty) {
        selectedTags = [params['tag']!];
      }

      final posts = ObjectBoxStore.instance.getFilteredPosts(
        startDate: startDate,
        endDate: endDate,
        selectedTags: selectedTags,
      ).reversed.toList();
      final list = posts.map((post) {
        return {
          'uuid': post.uuid,
          'content': _rewriteImagePaths(post.content),
          'tags': post.tags.map((tag) => tag.name).toList(),
          'createdAt': post.createdAt.millisecondsSinceEpoch > 946684800000
              ? post.createdAt.millisecondsSinceEpoch
              : post.updatedAt.millisecondsSinceEpoch,
          'updatedAt': post.updatedAt.millisecondsSinceEpoch,
          'images': post.images.map((img) {
            final fileName = img.localPath.split(RegExp(r'[/\\]')).last;
            return {
              'localPath': img.localPath,
              'url': '/images/$fileName',
              'downloadUrl': '/api/images/${img.id}/download',
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
        final tagsRaw = data['tags'] as List<dynamic>? ?? [];
        final uuid = data['uuid'] as String?;

        final post = Post(
          uuid: uuid ?? const Uuid().v4(),
          content: content,
          updatedAt: DateTime.now(),
          isDeleted: false,
        );

        // 处理标签关联
        for (final tagName in tagsRaw) {
          if (tagName is String && tagName.isNotEmpty) {
            var tag = ObjectBoxStore.instance.getTagByName(tagName);
            if (tag == null) {
              tag = Tag(name: tagName);
              ObjectBoxStore.instance.putTag(tag);
            }
            post.tags.add(tag);
          }
        }

        ObjectBoxStore.instance.putPost(post);

        return Response.ok(
          jsonEncode({'success': true, 'id': post.id, 'uuid': post.uuid}),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.badRequest(
          body: jsonEncode({'success': false, 'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    // 上传图片（multipart/form-data）
    _router.post('/api/upload', (Request request) async {
      try {
        // 从请求中解析 multipart 数据
        final contentType = request.headers['content-type'] ?? '';
        if (!contentType.contains('multipart/form-data')) {
          return Response.badRequest(
            body: jsonEncode({'success': false, 'error': 'Expected multipart/form-data'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        // 读取原始请求体
        final bytes = await request.read().expand((x) => x).toList();
        final boundary = _extractBoundary(contentType);
        if (boundary == null) {
          return Response.badRequest(
            body: jsonEncode({'success': false, 'error': 'No boundary found'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        // 解析 multipart 数据，提取文件
        final files = _parseMultipart(bytes, boundary);
        if (files.isEmpty) {
          return Response.badRequest(
            body: jsonEncode({'success': false, 'error': 'No file in request'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        // 只处理第一个文件
        final fileData = files.first;
        final fileName = fileData['filename'] as String? ?? 'upload.jpg';
        final fileBytes = fileData['data'] as List<int>;

        // 创建临时 XFile 用于 ImageProcessor
        final tempDir = Directory.systemTemp;
        final tempPath = '${tempDir.path}/${const Uuid().v4()}_$fileName';
        final tempFile = File(tempPath);
        await tempFile.writeAsBytes(fileBytes);

        // 调用 ImageProcessor.process 保存图片
        final savedPath = await ImageProcessor.process(XFile(tempPath));

        // 清理临时文件
        if (tempFile.existsSync()) tempFile.deleteSync();

        // 构建可访问的图片 URL（使用 /images/ 静态代理）
        final savedFileName = savedPath.split(RegExp(r'[/\\]')).last;
        final imageUrl = '/images/$savedFileName';

        return Response.ok(
          jsonEncode({
            'success': true,
            'url': imageUrl,
            'localPath': savedPath,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.badRequest(
          body: jsonEncode({'success': false, 'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    // 调试端点：返回 posts 及其关联图片的详细信息
    _router.get('/api/debug/posts', (Request request) {
      // 直接从 imageBox 查询所有图片，再按 postId 分组
      final allImages = ObjectBoxStore.instance.imageBox.getAll();
      final imageMap = <int, List<Map<String, dynamic>>>{};
      for (final img in allImages) {
        final pid = img.post.targetId;
        imageMap.putIfAbsent(pid, () => []);
        imageMap[pid]!.add({
          'id': img.id,
          'localPath': img.localPath,
          'postId': pid,
        });
      }

      final posts = ObjectBoxStore.instance.getSyncablePosts();
      final list = posts.map((post) {
        return {
          'postId': post.id,
          'uuid': post.uuid,
          'createdAt': post.createdAt.millisecondsSinceEpoch > 946684800000
              ? post.createdAt.millisecondsSinceEpoch
              : post.updatedAt.millisecondsSinceEpoch,
          'updatedAt': post.updatedAt.millisecondsSinceEpoch,
          'imageCount': imageMap[post.id]?.length ?? 0,
          'images': imageMap[post.id] ?? [],
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

    // 静态资源下载路由（通过 path 查询参数指定本地绝对路径）
    _router.get('/api/assets', (Request request) async {
      final rawPath = request.url.queryParameters['path'];
      if (rawPath == null || rawPath.isEmpty) {
        return Response.notFound('Missing or empty path parameter');
      }

      // 解码 URL 编码的路径
      final localPath = Uri.decodeComponent(rawPath);
      final file = File(localPath);

      if (!file.existsSync()) {
        return Response.notFound('File not found: $localPath');
      }

      // 根据文件扩展名推断 content-type
      final ext = localPath.split('.').last.toLowerCase();
      final contentType = switch (ext) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        'bmp' => 'image/bmp',
        'svg' => 'image/svg+xml',
        'pdf' => 'application/pdf',
        'mp4' => 'video/mp4',
        'mp3' => 'audio/mpeg',
        _ => 'application/octet-stream',
      };

      final bytes = await file.readAsBytes();
      final fileName = localPath.split(RegExp(r'[/\\]')).last;

      return Response.ok(
        bytes,
        headers: {
          'Content-Type': contentType,
          'Content-Disposition': 'inline; filename="$fileName"',
          'Content-Length': bytes.length.toString(),
        },
      );
    });

    // 静态图片代理：/images/<filename> → 应用沙盒 images 目录
    _router.get('/images/<filename>', (Request request, String filename) async {
      if (_imagesDirPath == null) {
        return Response.internalServerError(body: 'Images directory not initialized');
      }
      final file = File('$_imagesDirPath/$filename');
      if (!file.existsSync()) {
        return Response.notFound('Image not found: $filename');
      }
      final ext = filename.split('.').last.toLowerCase();
      final contentType = switch (ext) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        'bmp' => 'image/bmp',
        _ => 'application/octet-stream',
      };
      final bytes = await file.readAsBytes();
      return Response.ok(
        bytes,
        headers: {
          'Content-Type': contentType,
          'Content-Length': bytes.length.toString(),
          'Cache-Control': 'public, max-age=86400',
        },
      );
    });

    // 下载图片（Obsidian 插件同步图片用，返回原始文件字节流）
    _router.get('/api/images/<id>/download', (Request request, String id) async {
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

      // 返回原始文件数据，不做 content-type 转换
      final bytes = await file.readAsBytes();
      final fileName = image.localPath.split('/').last;

      return Response.ok(
        bytes,
        headers: {
          'Content-Type': 'application/octet-stream',
          'Content-Disposition': 'attachment; filename="$fileName"',
        },
      );
    });
  }

  /// 加载内置 Web 页面
  Future<String?> _loadHtml() async {
    try {
      return await rootBundle.loadString('assets/web/index.html');
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

    // 缓存图片目录路径
    final appDir = await getApplicationDocumentsDirectory();
    _imagesDirPath = '${appDir.path}/images';
    // ignore: avoid_print
    print('[LocalServer] 图片目录: $_imagesDirPath');

    // 加载或生成 API Token（持久化）
    if (_persistentToken == null) {
      final prefs = await SharedPreferences.getInstance();
      _persistentToken = prefs.getString('lan_api_token');
      if (_persistentToken == null) {
        _persistentToken = const Uuid().v4().substring(0, 8);
        await prefs.setString('lan_api_token', _persistentToken!);
      }
    }
    _apiToken = _persistentToken;

    // 尝试绑定端口，如果被占用则递增
    for (int attempt = 0; attempt < 10; attempt++) {
      try {
        final targetPort = port + attempt;
        // ignore: avoid_print
        print('[LocalServer] 尝试绑定端口 $targetPort...');

        final handler = Pipeline()
            .addMiddleware(_corsMiddleware)
            .addMiddleware(_clientTrackingMiddleware())
            .addMiddleware(_authMiddleware())
            .addMiddleware(_loggingMiddleware)
            .addHandler(_router.call);

        _server = await shelf_io.serve(
          handler,
          InternetAddress.anyIPv4,
          targetPort,
        );
        _port = targetPort;
        // ignore: avoid_print
        print('[LocalServer] 绑定端口 $targetPort 成功!');
        break;
      } catch (e) {
        // ignore: avoid_print
        print('[LocalServer] 端口 ${port + attempt} 绑定失败: $e');
        if (attempt < 9) continue;
      }
    }

    if (_server == null) {
      throw StateError('无法启动服务器：端口 $port-${port + 9} 均无法绑定');
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

  /// 刷新 Token（手动重新生成并持久化）
  Future<void> refreshToken() async {
    final newToken = const Uuid().v4().substring(0, 8);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lan_api_token', newToken);
    _persistentToken = newToken;
    _apiToken = newToken;
  }
}

/// 已连接客户端信息
class _ClientInfo {
  final String ip;
  final String userAgent;
  final DateTime lastSeen;

  _ClientInfo({
    required this.ip,
    required this.userAgent,
    required this.lastSeen,
  });

  Map<String, dynamic> toJson() => {
        'ip': ip,
        'userAgent': userAgent,
        'lastSeen': lastSeen.millisecondsSinceEpoch,
      };
}
