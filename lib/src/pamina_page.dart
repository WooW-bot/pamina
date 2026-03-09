import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:path/path.dart' as p;
import 'utils/pamina_log.dart';
import 'widgets/pamina_ui_widgets.dart';


/// Pamina 页面组件 (Page)
///
/// 负责渲染小程序的 UI 界面，每个页面对应一个独立的 WebView。
///
/// @author Parker
class PaminaPage extends StatefulWidget {
  final String appId;
  final int viewId;
  final String path;
  final String sourcePath;
  final Function(String event, String params, int viewId)? onPublish;
  final Function(String event, String params, String? callbackId)? onInvoke;
  final VoidCallback? onReady;
  final VoidCallback? onClose; // 整个小程序的关闭回调
  final String? initialTitle;
  final String? initialBgColor;
  final String? initialTextColor;
  final bool? showBack;
  final VoidCallback? onBack;

  const PaminaPage({
    super.key,
    required this.appId,
    required this.viewId,
    required this.path,
    required this.sourcePath,
    this.onPublish,
    this.onInvoke,
    this.onReady,
    this.onClose,
    this.initialTitle,
    this.initialBgColor,
    this.initialTextColor,
    this.showBack,
    this.onBack,
  });

  @override
  State<PaminaPage> createState() => PaminaPageState();
}

class PaminaPageState extends State<PaminaPage> {
  late final WebViewController _controller;
  bool _isReady = false;
  final List<String> _messageBuffer = [];

  // 导航栏状态 (由 MiniAppApp 通过 GlobalKey 修改)
  String _navBarTitle = '';
  String _navBarBgColor = '#F7F7F7';
  String _navBarTextColor = 'black';
  bool _showBack = false;
  VoidCallback? _onBack;

  @override
  void initState() {
    super.initState();
    _navBarTitle = widget.initialTitle ?? '';
    _navBarBgColor = widget.initialBgColor ?? '#F7F7F7';
    _navBarTextColor = widget.initialTextColor ?? 'black';
    _showBack = widget.showBack ?? false;
    _onBack = widget.onBack;
    _initController();
    if (widget.onReady != null) {
      widget.onReady!();
    }
  }

  void _initController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            // 运行时注入或 HTML 注入
          },
          onPageFinished: (String url) {
            PaminaLog.i('Page layer (${widget.path}) loaded.', tag: 'PaminaPage');
            // 核心修复：强制注入 CSS 允许页面滚动，并确保 -webkit-overflow-scrolling 为 touch
            // 许多小程序框架在 body/html 上禁用了滚动，通过注入覆盖这些样式。
            _controller.runJavaScript("""
              (function() {
                var style = document.createElement('style');
                style.innerHTML = 'html, body { overflow: auto !important; height: auto !important; -webkit-overflow-scrolling: touch !important; }';
                document.head.appendChild(style);
              })();
            """);
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
  void didUpdateWidget(covariant PaminaPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path || oldWidget.sourcePath != widget.sourcePath) {
      _loadPage();
    }
  }

  void _handleInvokeMessage(String message) {
    try {
      // 记录原始消息以供调试
      PaminaLog.d('Page[${widget.viewId}] InvokeRaw: $message', tag: 'PaminaPage');
      final Map<String, dynamic> data = json.decode(message);
      
      // Hera 框架在 Invoke 时可能使用 'C' 作为 event key (Command)
      final String event = data['C'] ?? data['event'] ?? '';
      final String params = data['paramsString'] ?? '{}';
      final String? callbackId = data['callbackId']?.toString();

      PaminaLog.d('Page[${widget.viewId}] Invoke: event=$event', tag: 'PaminaPage');

      if (widget.onInvoke != null) {
        widget.onInvoke!(event, params, callbackId);
      }
    } catch (e) {
      PaminaLog.e('Handle Page invoke error', error: e, tag: 'PaminaPage');
    }
  }

  void _handlePublishMessage(String message) {
    try {
      // 记录原始消息以供调试
      PaminaLog.d('Page[${widget.viewId}] PublishRaw: $message', tag: 'PaminaPage');
      final Map<String, dynamic> data = json.decode(message);
      // 兼容两种可能存在的 key (Hera 有时使用 'C')
      final String event = data['event'] ?? data['C'] ?? '';
      final String params = data['paramsString'] ?? '{}';

      PaminaLog.d('Page[${widget.viewId}] Publish: event=$event', tag: 'PaminaPage');

      // 如果是 DOMContentLoaded，代表视图层 DOM 加载完成，通知逻辑层
      if (event == 'custom_event_DOMContentLoaded') {
        _isReady = true;
        _flushMessageBuffer();
      }

      if (widget.onPublish != null) {
        widget.onPublish!(event, params, widget.viewId);
      }
    } catch (e) {
      PaminaLog.e('Handle Page publish error', error: e, tag: 'PaminaPage');
    }
  }

  void _flushMessageBuffer() {
    if (_messageBuffer.isEmpty) return;
    PaminaLog.i('Page[${widget.viewId}] Flushing ${_messageBuffer.length} buffered messages', tag: 'PaminaPage');
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

      // 核心修复：注入动态 Shim
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

      PaminaLog.i('Page loading ${widget.path} with symlink support.', tag: 'PaminaPage');

      _controller.loadHtmlString(
        content,
        // baseUrl 改为源码根目录，统一路径计算逻辑
        baseUrl: widget.sourcePath.endsWith('/') ? 'file://${widget.sourcePath}' : 'file://${widget.sourcePath}/',
      );

    } else {
      PaminaLog.e('页面文件不存在: ${pageFile.path}', tag: 'PaminaPage');
    }
  }

  /// 向视图层发送事件 (由逻辑层发出)
  void subscribeHandler(String event, String params) {
    // Hera 的视图层统一使用 HeraJSBridge
    final js = "window.HeraJSBridge && window.HeraJSBridge.subscribeHandler && window.HeraJSBridge.subscribeHandler('$event', $params)";
    
    if (!_isReady) {
      PaminaLog.d('Page[${widget.viewId}] Buffering subscribeHandler: $event', tag: 'PaminaPage');
      _messageBuffer.add(js);
      return;
    }
    _controller.runJavaScript(js);
  }

  /// 向视图层发送监听回调 (API 回调)
  void invokeCallbackHandler(String callbackId, String result) {
    final js =
        "window.HeraJSBridge && window.HeraJSBridge.invokeCallbackHandler && window.HeraJSBridge.invokeCallbackHandler('$callbackId', $result)";

    if (!_isReady) {
      PaminaLog.d(
        'Page[${widget.viewId}] Buffering invokeCallbackHandler: $callbackId',
        tag: 'PaminaPage',
      );
      _messageBuffer.add(js);
      return;
    }
    _controller.runJavaScript(js);
  }

  /// 更新导航栏配置
  void updateNavigationBar({
    String? title,
    String? backgroundColor,
    String? textColor,
    bool? showBack,
    VoidCallback? onBack,
  }) {
    if (!mounted) return;
    setState(() {
      if (title != null) _navBarTitle = title;
      if (backgroundColor != null) _navBarBgColor = backgroundColor;
      if (textColor != null) _navBarTextColor = textColor;
      if (showBack != null) _showBack = showBack;
      if (onBack != null) _onBack = onBack;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PaminaCapsuleAppBar(
        title: _navBarTitle,
        backgroundColor: _navBarBgColor,
        textColor: _navBarTextColor,
        showBack: _showBack,
        onBack: _onBack,
        onClose: widget.onClose,
      ),
      body: WebViewWidget(
        controller: _controller,
        gestureRecognizers: {
          Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
        },
      ),
    );
  }
}
