import 'package:flutter/material.dart';
import 'package:mini_app_flutter/src/sync/mini_app_manager.dart';
import 'src/mini_app_page.dart';
import 'src/utils/mini_app_log.dart';

export 'src/mini_app_page.dart';

/// 小程序插件入口类
///
/// @author Parker
class MiniAppPlugin {
  static Future<bool> initFramework() async {
    try {
      return await MiniAppManager.initFramework();
    } catch (e) {
      MiniAppLog.e(
        'initFramework error (caught at plugin layer)',
        error: e,
        tag: 'Plugin',
      );
      return false;
    }
  }

  static Future<T?> launchApp<T>({
    required BuildContext context,
    required String userId,
    required String appId,
    required String appPath,
  }) {
    return Navigator.push<T>(
      context,
      PageRouteBuilder(
        pageBuilder:
            (context, animation, secondaryAnimation) =>
                MiniAppPage(userId: userId, appId: appId, appPath: appPath),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.ease;

          var tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: curve));

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    );
  }
}
