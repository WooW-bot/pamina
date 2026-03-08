import 'package:flutter/material.dart';
import 'sync/mini_app_manager.dart';

class MiniAppPage extends StatefulWidget {
  final String appId;
  final String appPath;
  final String userId;

  const MiniAppPage({
    super.key,
    required this.appId,
    required this.appPath,
    required this.userId,
  });

  @override
  State<MiniAppPage> createState() => _MiniAppPageState();
}

class _MiniAppPageState extends State<MiniAppPage> {
  bool _isSyncing = true;
  bool _syncError = false;

  @override
  void initState() {
    super.initState();
    _syncMiniApp();
  }

  Future<void> _syncMiniApp() async {
    final result = await MiniAppManager.syncMiniApp(widget.appId, widget.appPath);
    if (mounted) {
      setState(() {
        _isSyncing = false;
        _syncError = !result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: const MiniAppCapsuleAppBar(),
      body: SafeArea(
        top: false, // AppBar already handles top safe area usually
        child: Stack(children: [
          if (_syncError)
            const Center(child: Text('小程序加载失败', style: TextStyle(color: Colors.red)))
          else if (_isSyncing)
            const MiniAppSplashScreen(appName: '小程序示例')
          else
            const Center(child: Text('应该显示小程序WebView内容')), // 这里后续将替换为真正的 WebView 内容
        ]),
      ),
    );
  }
}

class MiniAppSplashScreen extends StatelessWidget {
  final Widget? appIcon;
  final String appName;

  const MiniAppSplashScreen({super.key, this.appIcon, required this.appName});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: Column(
        children: [
          const Spacer(flex: 1),
          // Reduced top whitespace (moving content UP)
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 60,
                height: 60,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.green.shade400,
                  ),
                  backgroundColor: Colors.grey.shade100,
                ),
              ),
              appIcon ??
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: Color(0xFF333333),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.all_inclusive,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            appName,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const Spacer(flex: 2),
          // Bottom white space (significantly more than top)
        ],
      ),
    );
  }
}

class MiniAppCapsuleAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const MiniAppCapsuleAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: const Color(0xFFF7F7F7),
      elevation: 0,
      toolbarHeight: 56,
      automaticallyImplyLeading: false,
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.black12, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 14),
              Row(
                children: List.generate(
                  3,
                  (index) => Container(
                    width: index == 1 ? 6 : 4,
                    height: index == 1 ? 6 : 4,
                    margin: EdgeInsets.only(right: index == 2 ? 0 : 3),
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Container(width: 0.5, height: 18, color: Colors.black12),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black, width: 2),
                        shape: BoxShape.circle,
                        color: Colors.transparent,
                      ),
                    ),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(56);
}
