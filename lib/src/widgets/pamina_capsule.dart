import 'package:flutter/material.dart';

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
          Container(width: 0.5, height: 16, color: contentColor.withAlpha(51)),
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
