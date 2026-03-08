import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:path/path.dart' as p;
import 'utils/mini_app_log.dart';

/// 小程序视图层组件 (Page View)
/// 
/// 负责渲染小程序的 UI 界面，每个页面对应一个独立的 WebView。
/// 
/// @author Parker
class MiniAppPageView extends StatefulWidget {
  final String appId;
  final int viewId;
  final String path;
  final String sourcePath;
  final Function(String event, String params, int viewId)? onPublish;
  final Function(String event, String params, String? callbackId)? onInvoke;
  final VoidCallback? onReady;

  const MiniAppPageView({
    super.key,
    required this.appId,
    required this.viewId,
    required this.path,
    required this.sourcePath,
    this.onPublish,
    this.onInvoke,
    this.onReady,
  });

  @override
  State<MiniAppPageView> createState() => MiniAppPageViewState();
}

class MiniAppPageViewState extends State<MiniAppPageView> {
  late final WebViewController _controller;
  bool _isReady = false;
  final List<String> _messageBuffer = [];

  @override
  void initState() {
    super.initState();
    _initController();
    if (widget.onReady != null) {
      widget.onReady!();
    }
  }

  void _initController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            // 运行时注入或 HTML 注入
          },
          onPageFinished: (String url) {
            MiniAppLog.i('Page layer (${widget.path}) loaded.', tag: 'PageView');
          },
        ),
      );

    // 核心修复：开启 Android 的文件访问权限
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setAllowFileAccess(true);
      platform.setAllowContentAccess(true);
    }

    // 1. 初始化 UserAgent (模拟 iOS)
    _controller.getUserAgent().then((ua) {
      final baseUa = ua ?? "";
      final cleanUa = baseUa.replaceAll('Android', 'MiniAppPlatform');
      final heraUa = "$cleanUa Hera(version/1.0.0) MiniAppFlutter";
      _controller.setUserAgent(heraUa);
    });

    // 2. 注入 JSBridge 核心通道
    _controller.addJavaScriptChannel(
      'invokeHandler',
      onMessageReceived: (JavaScriptMessage message) {
        _handleInvokeMessage(message.message);
      },
    );

    _controller.addJavaScriptChannel(
      'publishHandler',
      onMessageReceived: (JavaScriptMessage message) {
        _handlePublishMessage(message.message);
      },
    );

    _loadPage();
  }

  @override
  void didUpdateWidget(covariant MiniAppPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path || oldWidget.sourcePath != widget.sourcePath) {
      _loadPage();
    }
  }

  void _handleInvokeMessage(String message) {
    try {
      // 记录原始消息以供调试
      MiniAppLog.d('PageView[${widget.viewId}] InvokeRaw: $message', tag: 'PageView');
      final Map<String, dynamic> data = json.decode(message);
      
      // Hera 框架在 Invoke 时可能使用 'C' 作为 event key (Command)
      final String event = data['C'] ?? data['event'] ?? '';
      final String params = data['paramsString'] ?? '{}';
      final String? callbackId = data['callbackId']?.toString();

      MiniAppLog.d('PageView[${widget.viewId}] Invoke: event=$event', tag: 'PageView');

      if (widget.onInvoke != null) {
        widget.onInvoke!(event, params, callbackId);
      }
    } catch (e) {
      MiniAppLog.e('Handle PageView invoke error', error: e, tag: 'PageView');
    }
  }

  void _handlePublishMessage(String message) {
    try {
      // 记录原始消息以供调试
      MiniAppLog.d('PageView[${widget.viewId}] PublishRaw: $message', tag: 'PageView');
      final Map<String, dynamic> data = json.decode(message);
      // 兼容两种可能存在的 key (Hera 有时使用 'C')
      final String event = data['event'] ?? data['C'] ?? '';
      final String params = data['paramsString'] ?? '{}';

      MiniAppLog.d('PageView[${widget.viewId}] Publish: event=$event', tag: 'PageView');

      // 如果是 DOMContentLoaded，代表视图层 DOM 加载完成，通知逻辑层
      if (event == 'custom_event_DOMContentLoaded') {
        _isReady = true;
        _flushMessageBuffer();
      }

      if (widget.onPublish != null) {
        widget.onPublish!(event, params, widget.viewId);
      }
    } catch (e) {
      MiniAppLog.e('Handle PageView publish error', error: e, tag: 'PageView');
    }
  }

  void _flushMessageBuffer() {
    if (_messageBuffer.isEmpty) return;
    MiniAppLog.i('PageView[${widget.viewId}] Flushing ${_messageBuffer.length} buffered messages', tag: 'PageView');
    for (final js in _messageBuffer) {
      _controller.runJavaScript(js);
    }
    _messageBuffer.clear();
  }

  Future<void> _loadPage() async {
    // 页面 HTML 路径通常是 appId/source/path.html
    final pageFile = File(
      p.join(
        widget.sourcePath,
        widget.path.endsWith('.html') ? widget.path : '${widget.path}.html',
      ),
    );

    if (pageFile.existsSync()) {
      String content = await pageFile.readAsString();

      // 核心修复：不再进行全量内联，而是注入一个动态 Shim 到 HTML 头部
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

      MiniAppLog.i('PageView loading ${widget.path} with native file access enabled.', tag: 'PageView');

      _controller.loadHtmlString(
        content,
        // baseUrl 改为源码根目录，统一路径计算逻辑
        baseUrl: widget.sourcePath.endsWith('/') ? 'file://${widget.sourcePath}' : 'file://${widget.sourcePath}/',
      );
    } else {
      MiniAppLog.e('页面文件不存在: ${pageFile.path}', tag: 'PageView');
    }
  }

  /// 向视图层发送事件 (由逻辑层发出)
  void subscribeHandler(String event, String params) {
    // Hera 的视图层统一使用 HeraJSBridge
    final js = "window.HeraJSBridge && window.HeraJSBridge.subscribeHandler && window.HeraJSBridge.subscribeHandler('$event', $params)";
    
    if (!_isReady) {
      MiniAppLog.d('PageView[${widget.viewId}] Buffering subscribeHandler: $event', tag: 'PageView');
      _messageBuffer.add(js);
      return;
    }
    _controller.runJavaScript(js);
  }

  /// 向视图层发送监听回调 (API 回调)
  void invokeCallbackHandler(String callbackId, String result) {
    final js = "window.HeraJSBridge && window.HeraJSBridge.invokeCallbackHandler && window.HeraJSBridge.invokeCallbackHandler('$callbackId', $result)";
    
    if (!_isReady) {
      MiniAppLog.d('PageView[${widget.viewId}] Buffering invokeCallbackHandler: $callbackId', tag: 'PageView');
      _messageBuffer.add(js);
      return;
    }
    _controller.runJavaScript(js);
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
