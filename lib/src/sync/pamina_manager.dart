import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../utils/storage_util.dart';
import '../utils/zip_util.dart';
import '../utils/pamina_log.dart';

/// Pamina 资源管理类
///
/// 负责小程序的同步（下载/解压）以及资源校验。
///
/// @author Parker
class PaminaManager {
  /// 插件包名，用于加载插件内部的资源文件 (Assets)
  static const String _packageName = 'pamina';

  PaminaManager._();

  /// 初始化框架引擎
  ///
  /// 建议在 App 启动时（如 main 函数中）调用此方法。
  /// 它会检查框架资源是否已解压，如果没有，则从插件内置的 assets/framework.zip 解压到本地。
  static Future<bool> initFramework() async {
    try {
      final frameworkDir = await StorageUtil.getFrameworkDir();

      // 1. 检查框架目录是否已经有内容
      if (await StorageUtil.isFrameworkExists()) {
        PaminaLog.i(
          'Framework already exists.',
          tag: 'PaminaManager',
        );
        return true;
      }

      PaminaLog.i(
        'Initializing framework to ${frameworkDir.path}',
        tag: 'PaminaManager',
      );

      // 2. 从插件内置 assets 加载 framework.zip
      try {
        // 注意：插件内部资源路径必须以 packages/包名/ 开头
        final data = await rootBundle.load(
          'packages/$_packageName/assets/framework.zip',
        );
        final bytes = data.buffer.asUint8List();

        // 3. 解压到框架目录
        final success = await ZipUtil.unzip(bytes, frameworkDir.path);
        if (success) {
          PaminaLog.i('Framework initialized.', tag: 'PaminaManager');
        }
        return success;
      } catch (e) {
        PaminaLog.e(
          '引擎资源加载失败。请确保插件 assets/framework.zip 存在。',
          error: e,
          tag: 'PaminaManager',
        );
        return false;
      }
    } catch (e) {
      PaminaLog.e('initFramework error', error: e, tag: 'PaminaManager');
      return false;
    }
  }

  /// 同步小程序资源
  ///
  /// [appId] 小程序唯一标识
  /// [appPath] 小程序 zip 包的本地路径（可选）
  /// 如果 [appPath] 为空，则尝试从 assets 中加载。
  static Future<bool> syncMiniApp(String appId, String appPath) async {
    try {
      final outDir = await StorageUtil.getMiniAppSourceDir(appId);
      final outputPath = outDir.path;

      // 1. 清理旧目录以确保干净的同步
      if (outDir.existsSync()) {
        await outDir.delete(recursive: true);
      }
      await outDir.create(recursive: true);

      bool unzipSuccess = false;

      // 2. 尝试从指定路径解压
      if (appPath.isNotEmpty) {
        unzipSuccess = await ZipUtil.unzipFile(appPath, outputPath);
      }

      // 3. 兜底逻辑：尝试从 assets 加载（匹配原版 Hera 行为）
      if (!unzipSuccess) {
        try {
          final data = await rootBundle.load('assets/$appId.zip');
          List<int> bytes = data.buffer.asUint8List();
          unzipSuccess = await ZipUtil.unzip(bytes, outputPath);
        } catch (e) {
          PaminaLog.w('资源加载失败 - assets/$appId.zip', tag: 'PaminaManager');
        }
      }

      if (!unzipSuccess) {
        return false;
      }

      // 4. 核心：通过符号链接（Symlink）让小程序能访问到框架资源，
      // 这样既不需要进行物理镜像拷贝，也不需要修改 HTML 源码（保持相对路径有效）。
      final frameworkLink = Link(p.join(outputPath, 'framework'));
      final frameworkPageLink = Link(p.join(outputPath, 'page', 'framework'));
      
      final frameworkSrcDir = await StorageUtil.getFrameworkDir();
      if (frameworkSrcDir.existsSync()) {
        // 如果已存在则先删除，确保重新同步时路径正确
        if (await frameworkLink.exists()) await frameworkLink.delete();
        if (await frameworkPageLink.exists()) await frameworkPageLink.delete();
        
        await frameworkLink.create(frameworkSrcDir.path);
        await frameworkPageLink.create(frameworkSrcDir.path);
      }

      // 5. 校验：检查 service.html（小程序核心入口文件）
      final serviceHtml = File(p.join(outputPath, 'service.html'));
      return await serviceHtml.exists();
    } catch (e) {
      PaminaLog.e('synchronization error', error: e, tag: 'PaminaManager');
      return false;
    }
  }
}

