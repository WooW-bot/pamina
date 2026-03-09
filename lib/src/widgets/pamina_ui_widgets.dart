import 'package:flutter/material.dart';

/// Pamina 启动闪屏
class PaminaSplashScreen extends StatelessWidget {
  final Widget? appIcon;
  final String appName;

  const PaminaSplashScreen({super.key, this.appIcon, required this.appName});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
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

/// Pamina 胶囊样式的 AppBar
class PaminaCapsuleAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String backgroundColor;
  final String textColor;
  final bool showBack;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  const PaminaCapsuleAppBar({
    super.key,
    this.title = '',
    this.backgroundColor = '#F7F7F7',
    this.textColor = 'black',
    this.showBack = false,
    this.onBack,
    this.onClose,
  });

  Color _parseColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) {
      hex = 'FF$hex';
    } else if (hex.length == 3) {
      final r = hex[0];
      final g = hex[1];
      final b = hex[2];
      hex = 'FF$r$r$g$g$b$b';
    }
    try {
      return Color(int.parse(hex, radix: 16));
    } catch (e) {
      return const Color(0xFFF7F7F7);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color bgColor = _parseColor(backgroundColor);
    final Color contentColor =
        textColor == 'white' ? Colors.white : Colors.black;

    return AppBar(
      backgroundColor: bgColor,
      elevation: 0,
      toolbarHeight: 56,
      automaticallyImplyLeading: false,
      leading: showBack
          ? IconButton(
              icon: Icon(Icons.arrow_back_ios_new, color: contentColor, size: 20),
              onPressed: onBack,
            )
          : null,
      centerTitle: true,
      title: Text(
        title,
        style: TextStyle(
          color: contentColor,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
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
                    decoration: BoxDecoration(
                      color: contentColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 0.5,
                height: 16,
                color: contentColor.withAlpha(51),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: onClose,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        border: Border.all(color: contentColor, width: 2),
                        shape: BoxShape.circle,
                        color: Colors.transparent,
                      ),
                    ),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: contentColor,
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
