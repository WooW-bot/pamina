import 'package:flutter/material.dart';
import 'package:pamina/src/sync/pamina_manager.dart';
import 'src/pamina_app.dart';
import 'src/utils/pamina_log.dart';

export 'src/pamina_app.dart';

/// Pamina 插件入口类
///
/// @author Parker
class Pamina {
  static Future<bool> initFramework() async {
    try {
      return await PaminaManager.initFramework();
    } catch (e) {
      PaminaLog.e(
        'initFramework error (caught at plugin layer)',
        error: e,
        tag: 'Pamina',
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
                PaminaApp(userId: userId, appId: appId, appPath: appPath),
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
