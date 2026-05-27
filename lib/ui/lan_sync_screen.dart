import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../providers.dart';

/// 局域网同步/桌面连接 — 控制面板
///
/// 在手机上启动微型 Web 服务器，电脑浏览器可直接访问和管理日记。
class LanSyncScreen extends ConsumerStatefulWidget {
  const LanSyncScreen({super.key});

  @override
  ConsumerState<LanSyncScreen> createState() => _LanSyncScreenState();
}

class _LanSyncScreenState extends ConsumerState<LanSyncScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  List<Map<String, dynamic>> _clients = [];
  Timer? _clientTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _startClientPolling();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _clientTimer?.cancel();
    super.dispose();
  }

  void _startClientPolling() {
    _clientTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _fetchClients();
    });
  }

  Future<void> _fetchClients() async {
    final state = ref.read(lanServerProvider);
    if (!state.isRunning || state.url.isEmpty) {
      if (_clients.isNotEmpty) setState(() => _clients = []);
      return;
    }
    try {
      final http = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final req = await http.getUrl(Uri.parse('${state.url}/api/clients'));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      http.close();
      if (res.statusCode == 200) {
        final list = (jsonDecode(body) as List).cast<Map<String, dynamic>>();
        if (mounted) setState(() => _clients = list);
      }
    } catch (_) {}
  }

  void _toggleServer() async {
    final state = ref.read(lanServerProvider);
    if (state.isRunning) {
      await ref.read(lanServerProvider.notifier).stop();
      FlutterBackgroundService().invoke('stopService');
      _pulseController.stop();
    } else {
      _pulseController.repeat(reverse: true);
      try {
        await ref.read(lanServerProvider.notifier).start();
        FlutterBackgroundService().startService();
      } catch (e) {
        _pulseController.stop();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('启动服务器失败: $e')),
          );
        }
      }
    }
  }

  void _copyUrl() {
    final state = ref.read(lanServerProvider);
    if (state.url.isEmpty) return;
    Clipboard.setData(ClipboardData(text: state.url));
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('地址已复制到剪贴板'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _copyToken() {
    final state = ref.read(lanServerProvider);
    if (state.apiToken == null || state.apiToken!.isEmpty) return;
    Clipboard.setData(ClipboardData(text: state.apiToken!));
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Token 已复制到剪贴板'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _refreshToken() async {
    await ref.read(lanServerProvider.notifier).refreshToken();
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Token 已刷新'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lanServerProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'LAN 同步',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 40),

            // ——— 状态图标 & 大开关 ———
            GestureDetector(
              onTap: _toggleServer,
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) {
                  final pulse = state.isRunning
                      ? 1.0 + _pulseController.value * 0.08
                      : 1.0;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // 外圈脉冲光晕
                      if (state.isRunning)
                        Container(
                          width: 180 * pulse,
                          height: 180 * pulse,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF00D2FF)
                                .withAlpha((20 * (1 - _pulseController.value * 0.5)).toInt()),
                          ),
                        ),
                      // 主圆
                      Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: state.isRunning
                              ? const Color(0xFF00D2FF)
                              : Colors.white.withAlpha(30),
                          boxShadow: state.isRunning
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF00D2FF).withAlpha(100),
                                    blurRadius: 30,
                                    spreadRadius: 8,
                                  ),
                                ]
                              : null,
                        ),
                        child: Icon(
                          state.isRunning
                              ? Icons.wifi_rounded
                              : Icons.wifi_off_rounded,
                          size: 60,
                          color: state.isRunning ? Colors.white : Colors.white38,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 24),

            // ——— 状态文字 ———
            Text(
              state.isRunning ? '服务器运行中' : '点击启动',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: state.isRunning ? Colors.white : Colors.white38,
              ),
            ),

            const SizedBox(height: 40),

            // ——— 地址卡片 ———
            if (state.isRunning) ...[
              // ——— 地址卡片 ———
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withAlpha(25)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.link_rounded,
                        size: 18, color: const Color(0xFF00D2FF)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SelectableText(
                        state.url,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF00D2FF).withAlpha(30),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        color: const Color(0xFF00D2FF),
                        onPressed: _copyUrl,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '在电脑浏览器中打开此地址',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withAlpha(100),
                ),
              ),
              const SizedBox(height: 24),
              // ——— API Token 卡片 ———
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withAlpha(25)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.vpn_key_rounded,
                        size: 18, color: const Color(0xFF00D2FF)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SelectableText(
                        state.apiToken ?? '',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF00D2FF).withAlpha(30),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        color: const Color(0xFF00D2FF),
                        tooltip: '刷新 Token',
                        onPressed: _refreshToken,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF00D2FF).withAlpha(30),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        color: const Color(0xFF00D2FF),
                        onPressed: _copyToken,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '在桌面端 Obsidian 插件中配置此 Token',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withAlpha(100),
                ),
              ),
              const SizedBox(height: 24),
              // ——— 已连接客户端 ———
              _buildClientsSection(),
            ],

            const SizedBox(height: 32),

            // ——— 底部温馨提示 ———
            Container(
              margin: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(8),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withAlpha(15)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 16, color: Colors.white.withAlpha(100)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '请确保手机与电脑连接在同一 Wi-Fi 网络下。'
                      '连接期间请保持 App 在前台运行以防被系统休眠。',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: Colors.white.withAlpha(120),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClientsSection() {
    final count = _clients.length;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.devices_rounded,
                  size: 18, color: const Color(0xFF00D2FF)),
              const SizedBox(width: 12),
              Text(
                '已连接 $count 台设备',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          if (_clients.isNotEmpty) ...[
            const SizedBox(height: 12),
            ..._clients.map((c) {
              final ua = _parseUserAgent(c['userAgent'] ?? '');
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF22C55E),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ua,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withAlpha(200),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '活跃中',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withAlpha(100),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  /// 从 User-Agent 提取浏览器和系统信息
  String _parseUserAgent(String ua) {
    if (ua.isEmpty || ua == 'Unknown') return '未知客户端';
    // 提取浏览器
    String browser = '浏览器';
    if (ua.contains('Edg/')) {
      browser = 'Edge';
    } else if (ua.contains('Chrome/') && !ua.contains('Chromium')) {
      browser = 'Chrome';
    } else if (ua.contains('Firefox/')) {
      browser = 'Firefox';
    } else if (ua.contains('Safari/') && !ua.contains('Chrome')) {
      browser = 'Safari';
    }
    // 提取系统
    String os = '';
    if (ua.contains('Windows')) {
      os = 'Windows';
    } else if (ua.contains('Mac OS')) {
      os = 'macOS';
    } else if (ua.contains('Linux')) {
      os = 'Linux';
    } else if (ua.contains('Android')) {
      os = 'Android';
    } else if (ua.contains('iPhone') || ua.contains('iPad')) {
      os = 'iOS';
    }
    return os.isNotEmpty ? '$browser · $os' : browser;
  }
}
