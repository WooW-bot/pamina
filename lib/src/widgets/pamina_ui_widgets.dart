import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';

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

/// Pamina 微信样式全屏扫码界面
class PaminaScanner extends StatefulWidget {
  const PaminaScanner({super.key});

  @override
  State<PaminaScanner> createState() => _PaminaScannerState();
}

class _PaminaScannerState extends State<PaminaScanner> {
  final MobileScannerController controller = MobileScannerController();
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _scanFromAlbum() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      final BarcodeCapture? capture = await controller.analyzeImage(image.path);
      if (capture != null && capture.barcodes.isNotEmpty) {
        final String? code = capture.barcodes.first.rawValue;
        if (mounted && code != null) {
          Navigator.pop(context, code);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未发现二维码')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('读取图片失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                final String? code = barcodes.first.rawValue;
                if (code != null) {
                  Navigator.pop(context, code);
                }
              }
            },
          ),
          // 微信样式遮罩层
          _buildOverlay(context),
          // 顶部返回按钮
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 10,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          // 顶部右侧相册按钮
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            right: 15,
            child: TextButton(
              onPressed: _scanFromAlbum,
              child: const Text(
                '相册',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
          // 底部手电筒按钮
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Center(
              child: ValueListenableBuilder(
                valueListenable: controller,
                builder: (context, state, child) {
                  final bool isTorchOn = state.torchState == TorchState.on;
                  return GestureDetector(
                    onTap: () => controller.toggleTorch(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isTorchOn ? Icons.flash_on : Icons.flash_off,
                          color: Colors.white,
                          size: 32,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '轻触照亮',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final double scanAreaSize = MediaQuery.of(context).size.width * 0.7;
    return Stack(
      children: [
        // 四周阴影
        ColorFiltered(
          colorFilter: ColorFilter.mode(
            Colors.black.withAlpha(127),
            BlendMode.srcOut,
          ),
          child: Stack(
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: Colors.black,
                  backgroundBlendMode: BlendMode.dstOut,
                ),
              ),
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: scanAreaSize,
                  height: scanAreaSize,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
        ),
        // 扫描框四个角
        Align(
          alignment: Alignment.center,
          child: Container(
            width: scanAreaSize,
            height: scanAreaSize,
            child: CustomPaint(
              painter: _ScannerOverlayPainter(color: Colors.green.shade400),
            ),
          ),
        ),
        // 提示语
        Positioned(
          top: MediaQuery.of(context).size.height / 2 + scanAreaSize / 2 + 20,
          left: 0,
          right: 0,
          child: const Center(
            child: Text(
              '将二维码/条码放入框内，即可自动扫描',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  final Color color;
  _ScannerOverlayPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    const double cornerSize = 25;

    // 左上角
    canvas.drawLine(const Offset(0, 0), const Offset(cornerSize, 0), paint);
    canvas.drawLine(const Offset(0, 0), const Offset(0, cornerSize), paint);

    // 右上角
    canvas.drawLine(Offset(size.width, 0), Offset(size.width - cornerSize, 0), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, cornerSize), paint);

    // 左下角
    canvas.drawLine(Offset(0, size.height), Offset(cornerSize, size.height), paint);
    canvas.drawLine(Offset(0, size.height), Offset(0, size.height - cornerSize), paint);

    // 右下角
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width - cornerSize, size.height), paint);
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width, size.height - cornerSize), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

