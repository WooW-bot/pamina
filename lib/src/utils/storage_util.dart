import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'pamina_log.dart';

/// 小程序存储路径管理工具类
///
/// 目录结构设计：
/// ../mini_apps/                 - 根目录
/// ../mini_apps/framework/       - 存放引擎/框架 JS 代码的目录
/// ../mini_apps/app/             - 存储所有小程序的目录
/// ../mini_apps/app/$appId/      - 特定小程序的主目录
/// ../mini_apps/app/$appId/source/ - 小程序解压后的源码目录
/// ../mini_apps/app/$appId/store/  - 小程序的持久化资源存储目录
/// ../mini_apps/app/$appId/temp/   - 小程序的临时文件存储目录
///
/// @author Parker
class StorageUtil {
  static const String _rootName = 'mini_apps';

  StorageUtil._();

  /// 获取小程序数据的根目录
  /// 使用 getApplicationSupportDirectory 而不是 getApplicationDocumentsDirectory，
  /// 因为小程序源码和引擎属于应用支持文件，不应出现在用户的文档目录中，且在 iOS 上默认不备份到 iCloud。
  static Future<Directory> getRootDir() async {
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(supportDir.path, _rootName));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// 获取存储框架（引擎）JS 代码的目录
  static Future<Directory> getFrameworkDir() async {
    final root = await getRootDir();
    final dir = Directory(p.join(root.path, 'framework'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// 获取指定小程序的主目录
  static Future<Directory> getMiniAppDir(String appId) async {
    final root = await getRootDir();
    final dir = Directory(p.join(root.path, 'app', appId));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// 获取指定小程序的源码存放目录（解压后的内容）
  static Future<Directory> getMiniAppSourceDir(String appId) async {
    final appDir = await getMiniAppDir(appId);
    final dir = Directory(p.join(appDir.path, 'source'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// 获取指定小程序的持久化资源存储目录
  static Future<Directory> getMiniAppStoreDir(String appId) async {
    final appDir = await getMiniAppDir(appId);
    final dir = Directory(p.join(appDir.path, 'store'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// 获取指定小程序的临时文件存储目录
  static Future<Directory> getMiniAppTempDir(String appId) async {
    final appDir = await getMiniAppDir(appId);
    final dir = Directory(p.join(appDir.path, 'temp'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// 获取指定小程序内部受控的资源目录（位于 source 目录下，用于规避 WebView 跨域限制）
  static Future<Directory> getMiniAppInternalResourceDir(String appId) async {
    final sourceDir = await getMiniAppSourceDir(appId);
    final dir = Directory(p.join(sourceDir.path, '.pamina_res'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// 清除指定小程序的临时目录文件
  static Future<void> clearAppTempDir(String appId) async {
    final tempDir = await getMiniAppTempDir(appId);
    if (tempDir.existsSync()) {
      final files = tempDir.listSync();
      for (final file in files) {
        if (file is File) {
          file.deleteSync();
        }
      }
    }
  }

  /// 清除指定小程序的受控资源目录文件
  static Future<void> clearMiniAppInternalResourceDir(String appId) async {
    try {
      final resDir = await getMiniAppInternalResourceDir(appId);
      if (resDir.existsSync()) {
        await resDir.delete(recursive: true);
        await resDir.create(recursive: true);
      }
    } catch (e) {
      PaminaLog.e('Clear internal resource dir error', error: e, tag: 'StorageUtil');
    }
  }

  /// 获取指定小程序的 KV 存储文件路径
  static Future<File> getMiniAppStorageFile(String appId) async {
    final storeDir = await getMiniAppStoreDir(appId);
    return File(p.join(storeDir.path, 'storage.json'));
  }

  /// 检查框架（引擎）文件是否存在且不为空
  static Future<bool> isFrameworkExists() async {
    final dir = await getFrameworkDir();
    if (!dir.existsSync()) return false;
    return dir.listSync().isNotEmpty;
  }
}
