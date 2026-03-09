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

/// Pamina 胶囊按钮 (独立组件)
class PaminaCapsule extends StatelessWidget {
  final VoidCallback? onClose;
  final VoidCallback? onMenu;
  final Color contentColor;

  const PaminaCapsule({
    super.key,
    this.onClose,
    this.onMenu,
    this.contentColor = Colors.black,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
          GestureDetector(
            onTap: onMenu,
            child: Row(
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
    );
  }
}

/// Pamina 胶囊样式的 AppBar (不再包含胶囊，胶囊改为全局)
class PaminaCapsuleAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String backgroundColor;
  final String textColor;
  final bool showBack;
  final bool isLoading;
  final VoidCallback? onBack;

  const PaminaCapsuleAppBar({
    super.key,
    this.title = '',
    this.backgroundColor = '#F7F7F7',
    this.textColor = 'black',
    this.showBack = false,
    this.isLoading = false,
    this.onBack,
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
      leadingWidth: 48,
      leading: showBack
          ? IconButton(
              icon: Icon(Icons.arrow_back_ios_new, color: contentColor, size: 20),
              onPressed: onBack,
            )
          : null,
      centerTitle: true,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLoading)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(contentColor),
                ),
              ),
            ),
          Flexible(
            child: Text(
              title,
              style: TextStyle(
                color: contentColor,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      // 胶囊现在移到了 App 层的 Stack 中，不再通过 AppBar 展示
      actions: const [
         SizedBox(width: 100), // 为胶囊按钮留白
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(56);
}

/// Pamina 微信样式 Modal 弹窗
class PaminaCustomModal extends StatelessWidget {
  final String title;
  final String content;
  final bool showCancel;
  final String cancelText;
  final Color cancelColor;
  final String confirmText;
  final Color confirmColor;
  final Function(bool confirmed) onAction;

  const PaminaCustomModal({
    super.key,
    required this.title,
    required this.content,
    this.showCancel = true,
    this.cancelText = '取消',
    this.cancelColor = Colors.black,
    this.confirmText = '确定',
    this.confirmColor = const Color(0xFF576B95),
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                children: [
                  if (title.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  if (content.isNotEmpty)
                    Text(
                      content,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black54,
                        fontWeight: FontWeight.normal,
                        decoration: TextDecoration.none,
                        height: 1.5,
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 0.5, thickness: 0.5, color: Colors.black12),
            Row(
              children: [
                if (showCancel)
                  Expanded(
                    child: GestureDetector(
                      onTap: () => onAction(false),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        alignment: Alignment.center,
                        child: Text(
                          cancelText,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: cancelColor,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (showCancel)
                  Container(width: 0.5, height: 50, color: Colors.black12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => onAction(true),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      alignment: Alignment.center,
                      child: Text(
                        confirmText,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: confirmColor,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Pamina 全局 Toast/Loading 弹窗
class PaminaToast extends StatelessWidget {
  final bool visible;
  final String title;
  final String icon; // 'success', 'loading', 'none', 'error'
  final bool mask;

  const PaminaToast({
    super.key,
    required this.visible,
    this.title = '',
    this.icon = 'none',
    this.mask = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    Widget content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(204), // 80% black
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != 'none') ...[
            _buildIcon(),
            const SizedBox(height: 12),
          ],
          if (title.isNotEmpty)
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                decoration: TextDecoration.none,
              ),
            ),
        ],
      ),
    );

    if (mask) {
      return Container(
        color: Colors.transparent,
        width: double.infinity,
        height: double.infinity,
        alignment: Alignment.center,
        child: content,
      );
    }

    return Center(child: content);
  }

  Widget _buildIcon() {
    switch (icon) {
      case 'success':
        return const Icon(Icons.check_circle_outline, color: Colors.white, size: 40);
      case 'error':
        return const Icon(Icons.error_outline, color: Colors.white, size: 40);
      case 'loading':
        return const SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            strokeWidth: 3,
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

