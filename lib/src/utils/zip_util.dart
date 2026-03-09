import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'pamina_log.dart';

/// 小程序 Zip 解压工具类
///
/// 提供了对字节数组和文件的解压功能，支持解压到指定目录。
///
/// @author Parker
class ZipUtil {
  ZipUtil._();

  /// 解压 Zip 字节数组到指定目录
  ///
  /// [bytes] Zip 文件的字节数据
  /// [outputPath] 解压的目标输出路径
  /// 返回：true 表示解压成功，false 表示失败
  static Future<bool> unzip(List<int> bytes, String outputPath) async {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final file in archive) {
        final filename = file.name;
        final fullPath = p.join(outputPath, filename);

        if (file.isFile) {
          final data = file.content as List<int>;
          File(fullPath)
            ..createSync(recursive: true)
            ..writeAsBytesSync(data);
        } else {
          Directory(fullPath).createSync(recursive: true);
        }
      }
      return true;
    } catch (e) {
      PaminaLog.e('ZipUtil unzip error', error: e, tag: 'Zip');
      return false;
    }
  }

  /// 解压指定路径的 Zip 文件到目标目录
  ///
  /// [zipPath] Zip 文件的本地路径
  /// [outputPath] 解压的目标输出路径
  /// 返回：true 表示解压成功，false 表示失败
  static Future<bool> unzipFile(String zipPath, String outputPath) async {
    final file = File(zipPath);
    if (!await file.exists()) {
      return false;
    }
    final bytes = await file.readAsBytes();
    return unzip(bytes, outputPath);
  }
}
