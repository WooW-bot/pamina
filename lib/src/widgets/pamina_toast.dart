import 'package:flutter/material.dart';

/// Pamina 全局 Toast/Loading 弹窗
///
/// @author Parker
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
          if (icon != 'none') ...[_buildIcon(), const SizedBox(height: 12)],
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
        return const Icon(
          Icons.check_circle_outline,
          color: Colors.white,
          size: 40,
        );
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
