import 'package:flutter/material.dart';

/// Pamina 胶囊样式的 AppBar (不再包含胶囊，胶囊改为全局)
class PaminaAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final String title;
  final String backgroundColor;
  final String textColor;
  final bool showBack;
  final bool isLoading;
  final VoidCallback? onBack;

  const PaminaAppBar({
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
      leading:
          showBack
              ? IconButton(
                icon: Icon(
                  Icons.arrow_back_ios_new,
                  color: contentColor,
                  size: 20,
                ),
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
