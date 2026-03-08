import 'package:flutter/material.dart';
import 'src/mini_app_page.dart';

export 'src/mini_app_page.dart';

class MiniAppPlugin {
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
