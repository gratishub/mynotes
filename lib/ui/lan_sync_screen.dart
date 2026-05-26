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

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
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
        child: Column(
          children: [
            const Spacer(flex: 2),

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
            ],

            const Spacer(flex: 2),

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
    );
  }
}
