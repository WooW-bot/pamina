import 'package:flutter/foundation.dart';

/// 小程序日志工具类
/// 
/// 提供统一的格式化日志输出，方便在控制台进行调试。
/// 样式参考了 Hera 的 HeraTrace/HRLog 实现。
/// 
/// @author Parker
class PaminaLog {
  static const String _tag = "[Pamina]";

  PaminaLog._();

  /// 调试日志
  static void d(String message, {String? tag}) {
    if (kDebugMode) {
      _print("DEBUG", tag, message);
    }
  }

  /// 信息日志
  static void i(String message, {String? tag}) {
    _print("INFO ", tag, message);
  }

  /// 警告日志
  static void w(String message, {String? tag}) {
    _print("WARN ", tag, message);
  }

  /// 错误日志
  static void e(String message, {Object? error, StackTrace? stackTrace, String? tag}) {
    _print("ERROR", tag, "$message ${error ?? ''}");
    if (stackTrace != null) {
      debugPrint(stackTrace.toString());
    }
  }

  /// 小程序内部 H5 日志上报处理 (H5_LOG_MSG)
  static void h5(String params) {
    // 专门为 custom_event_H5_LOG_MSG 设计的打印样式
    _print("JS_LOG", "H5", params);
  }

  static void _print(String level, String? subTag, String message) {
    final tagPart = subTag != null ? "[$subTag]" : "";
    debugPrint("$_tag$tagPart $level: $message");
  }
}
