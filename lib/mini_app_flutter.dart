import 'package:flutter/material.dart';

import 'mini_app_flutter.dart';

export 'src/mini_app_page.dart';

class MiniAppPlugin {
  static void launchApp({
    required BuildContext context,
    required String userId,
    required String appId,
    required String appPath,
  }) => Navigator.push(
    context,
    MaterialPageRoute(
      builder:
          (context) =>
              MiniAppPage(userId: userId, appId: appId, appPath: appPath),
    ),
  );
}
