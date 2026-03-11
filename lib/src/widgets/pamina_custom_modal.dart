import 'package:flutter/material.dart';

/// Pamina 微信样式 Modal 弹窗
///
/// @author Parker
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
