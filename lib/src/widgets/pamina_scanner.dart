import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Pamina 微信样式全屏扫码界面
///
/// @author Parker
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('未发现二维码')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('读取图片失败: $e')));
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
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = 4
          ..style = PaintingStyle.stroke;

    const double cornerSize = 25;

    // 左上角
    canvas.drawLine(const Offset(0, 0), const Offset(cornerSize, 0), paint);
    canvas.drawLine(const Offset(0, 0), const Offset(0, cornerSize), paint);

    // 右上角
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width - cornerSize, 0),
      paint,
    );
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width, cornerSize),
      paint,
    );

    // 左下角
    canvas.drawLine(
      Offset(0, size.height),
      Offset(cornerSize, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height),
      Offset(0, size.height - cornerSize),
      paint,
    );

    // 右下角
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width - cornerSize, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width, size.height - cornerSize),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
