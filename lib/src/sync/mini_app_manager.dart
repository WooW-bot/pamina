import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../utils/storage_util.dart';
import '../utils/zip_util.dart';

/// 小程序资源管理类
///
/// 负责小程序的同步（下载/解压）以及资源校验。
///
/// @author Parker
class MiniAppManager {
  MiniAppManager._();

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
          print('MiniAppManager: 资源加载失败 - assets/$appId.zip error: $e');
        }
      }

      if (!unzipSuccess) {
        return false;
      }

      // 4. 校验：检查 service.html（小程序核心入口文件）
      final serviceHtml = File(p.join(outputPath, 'service.html'));
      return await serviceHtml.exists();
    } catch (e) {
      print('MiniAppManager synchronization error: $e');
      return false;
    }
  }
}
