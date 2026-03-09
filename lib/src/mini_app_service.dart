import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:path/path.dart' as p;
import 'utils/mini_app_log.dart';


/// 小程序逻辑层服务组件 (AppService)
///
/// 该组件是一个不可见的 WebView，负责运行小程序的逻辑层 JS (service.js)。
/// 它充当了小程序的消息中枢，协调视图层 (Page) 与 Native 之间的通信。
///
/// @author Parker
class MiniAppService extends StatefulWidget {
  final String appId;
  final String sourcePath;
  final Function(String event, String params, String? viewIds)? onPublish;
  final Function(String event, String params, String? callbackId)? onInvoke;

  const MiniAppService({
    super.key,
    required this.appId,
    required this.sourcePath,
    this.onPublish,
    this.onInvoke,
  });

  @override
  State<MiniAppService> createState() => MiniAppServiceState();
}

class MiniAppServiceState extends State<MiniAppService> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  void _initController() {
    _controller =
        WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(const Color(0x00000000))
          ..setNavigationDelegate(
            NavigationDelegate(
              onPageStarted: (String url) {
                // 运行时注入或 HTML 注入
              },
              onPageFinished: (String url) {
                MiniAppLog.i(
                  'Logic layer (service.html) loaded.',
                  tag: 'Service',
                );
              },
            ),
          );

    // 核心修复：开启 Android 的文件访问权限，允许加载相对路径的框架资源
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setAllowFileAccess(true);
      platform.setAllowContentAccess(true);
    }

    // 1. 初始化 UserAgent (模拟 iOS，确保 JS 走 iOS 分支)
    _controller.getUserAgent().then((ua) {
      // 移除可能存在的 Android 关键字，确保 JS 逻辑走 isIOS 路径
      final baseUa = ua ?? "";
      final cleanUa = baseUa.replaceAll('Android', 'MiniAppPlatform');
      final heraUa = "$cleanUa Hera(version/1.0.0) MiniAppFlutter";
      _controller.setUserAgent(heraUa);
    });

    // 2. 注入 JSBridge 核心通道
    // 监听逻辑层发出的 API 调用请求
    _controller.addJavaScriptChannel(
      'invokeHandler',
      onMessageReceived: (JavaScriptMessage message) {
        _handleInvokeMessage(message.message);
      },
    );

    // 监听逻辑层发出的内部事件/数据同步请求
    _controller.addJavaScriptChannel(
      'publishHandler',
      onMessageReceived: (JavaScriptMessage message) {
        _handlePublishMessage(message.message);
      },
    );

    _loadServiceHtml();
  }

  void _handleInvokeMessage(String message) {
    try {
      // 记录原始消息以供调试
      MiniAppLog.d('Service InvokeRaw: $message', tag: 'Service');
      final Map<String, dynamic> data = json.decode(message);
      
      // Hera 框架在 Invoke 时可能使用 'C' 作为 event key (Command)
      final String event = data['C'] ?? data['event'] ?? '';
      final String params = data['paramsString'] ?? '{}';
      final String? callbackId = data['callbackId']?.toString();

      MiniAppLog.d('Invoke: event=$event, callbackId=$callbackId', tag: 'Service');

      if (widget.onInvoke != null) {
        widget.onInvoke!(event, params, callbackId);
      }
    } catch (e) {
      MiniAppLog.e('Handle invoke message error', error: e, tag: 'Service');
    }
  }

  void _handlePublishMessage(String message) {
    try {
      // 记录原始消息以供调试
      MiniAppLog.d('Service PublishRaw: $message', tag: 'Service');
      final Map<String, dynamic> data = json.decode(message);
      
      // 兼容两种可能存在的 key (Hera 有时使用 'C')
      final String event = data['event'] ?? data['C'] ?? '';
      final String params = data['paramsString'] ?? '{}';
      // Hera 逻辑层发出的通常叫 webviewIds
      final String? viewIds = data['webviewIds']?.toString() ?? data['viewIds']?.toString();

      // 专门处理 Hera 的日志上报
      if (event == 'custom_event_H5_LOG_MSG') {
        MiniAppLog.h5(params);
        return;
      }

      MiniAppLog.d('Publish: event=$event, viewIds=$viewIds', tag: 'Service');

      if (widget.onPublish != null) {
        widget.onPublish!(event, params, viewIds);
      }
    } catch (e) {
      MiniAppLog.e('Handle publish message error', error: e, tag: 'Service');
    }
  }

  Future<void> _loadServiceHtml() async {
    final serviceFile = File(p.join(widget.sourcePath, 'service.html'));
    
    if (serviceFile.existsSync()) {
      String content = await serviceFile.readAsString();
      
      // 核心修复：注入一个动态 Shim 到 HTML 头部
      const shim = """
<script id="hera-flutter-shim">
(function() {
  if (!window.webkit || !window.webkit.messageHandlers) {
    window.webkit = {
      messageHandlers: {
        invokeHandler: { postMessage: function(d) { window.invokeHandler.postMessage(JSON.stringify(d)); } },
        publishHandler: { postMessage: function(d) { window.publishHandler.postMessage(JSON.stringify(d)); } }
      }
    };
  }
})();
</script>
""";
      // 插入到 <head> 标签之后
      content = content.replaceFirst('<head>', '<head>$shim');

      MiniAppLog.i('Loading service.html with symlink support.', tag: 'Service');

      _controller.loadHtmlString(
        content,
        // baseUrl 必须是小程序源码根目录，这样才能统一通过 ../../../framework/ 访问引擎
        // 同时也方便访问 script/config.js 等本地资源
        baseUrl: widget.sourcePath.endsWith('/') ? 'file://${widget.sourcePath}' : 'file://${widget.sourcePath}/',
      );

    } else {
      MiniAppLog.e('入口文件 service.html 不存在: ${serviceFile.path}', tag: 'Service');
    }
  }

  /// 向逻辑层发送事件
  void subscribeHandler(String event, String params, dynamic viewId) {
    final js = "window.ServiceJSBridge && window.ServiceJSBridge.subscribeHandler && window.ServiceJSBridge.subscribeHandler('$event', ${params.isEmpty ? '{}' : params}, $viewId)";
    _controller.runJavaScript(js);
  }

  /// 路由切换通知
  void onAppRoute(String openType, String path, int viewId, {String? query}) {
    final params = {
      'openType': openType,
      'path': path,
      'query': query ?? {},
    };
    subscribeHandler('onAppRoute', jsonEncode(params), viewId);
  }

  /// 路由切换完成通知
  void onAppRouteDone(String openType, String path, int viewId) {
    final params = {
      'openType': openType,
      'path': path,
    };
    subscribeHandler('onAppRouteDone', jsonEncode(params), viewId);
  }

  /// 向逻辑层发送 API 回调响应
  void invokeCallbackHandler(String callbackId, String result) {
    final js = "window.ServiceJSBridge && window.ServiceJSBridge.invokeCallbackHandler && window.ServiceJSBridge.invokeCallbackHandler('$callbackId', $result)";
    _controller.runJavaScript(js);
  }

  @override
  Widget build(BuildContext context) {
    // 使用 Offstage 或 SizedBox 使其在 UI 上不可见
    return const SizedBox.shrink();
  }
}
