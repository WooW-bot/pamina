import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:pamina/src/widgets/pamina_app_bar.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:path/path.dart' as p;
import 'utils/pamina_log.dart';


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
  final bool showBack;
  final bool enablePullDownRefresh;
  final VoidCallback? onBack;
  final VoidCallback? onDispose;

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
    this.onDispose,
    this.initialTitle,
    this.initialBgColor,
    this.initialTextColor,
    this.showBack = false,
    this.enablePullDownRefresh = false,
    this.onBack,
  });

  @override
  State<PaminaPage> createState() => PaminaPageState();
}

class PaminaPageState extends State<PaminaPage> {
  late final WebViewController _controller;
  bool _isReady = false;
  final List<String> _messageBuffer = [];

  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  Completer<void>? _pullDownRefreshCompleter;

  /// 停止下拉刷新动画
  void stopPullDownRefresh() {
    _pullDownRefreshCompleter?.complete();
    _pullDownRefreshCompleter = null;
  }

  /// 开始下拉刷新动画
  void startPullDownRefresh() {
    _refreshIndicatorKey.currentState?.show();
  }

  // 导航栏状态 (由 MiniAppApp 通过 GlobalKey 修改)
  String _navBarTitle = '';
  String _navBarBgColor = '#F7F7F7';
  String _navBarTextColor = 'black';
  bool _navBarLoading = false;
  bool _showBack = false;
  VoidCallback? _onBack;

  @override
  void initState() {
    super.initState();
    _navBarTitle = widget.initialTitle ?? '';
    _navBarBgColor = widget.initialBgColor ?? '#F7F7F7';
    _navBarTextColor = widget.initialTextColor ?? 'black';
    _showBack = widget.showBack;
    _onBack = widget.onBack;
    _initController();
    if (widget.onReady != null) {
      widget.onReady!();
    }
  }

  @override
  void dispose() {
    if (widget.onDispose != null) {
      widget.onDispose!();
    }
    super.dispose();
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
      PaminaLog.d('Page[${widget.viewId}] InvokeRaw: $message', tag: 'PaminaPage');
      final Map<String, dynamic> data = json.decode(message);
      
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
      PaminaLog.d('Page[${widget.viewId}] PublishRaw: $message', tag: 'PaminaPage');
      final Map<String, dynamic> data = json.decode(message);
      final String event = data['event'] ?? data['C'] ?? '';
      final String params = data['paramsString'] ?? '{}';

      PaminaLog.d('Page[${widget.viewId}] Publish: event=$event', tag: 'PaminaPage');

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
    if (widget.path.isEmpty) return;
    final pageFile = File(
      p.join(
        widget.sourcePath,
        widget.path.endsWith('.html') ? widget.path : '${widget.path}.html',
      ),
    );

    if (pageFile.existsSync()) {
      String content = await pageFile.readAsString();

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
  if (typeof HeraJSCore === 'undefined') {
    window.HeraJSCore = {
      invokeHandler: function(c, p, callbackId) {
        window.webkit.messageHandlers.invokeHandler.postMessage({C: c, paramsString: p, callbackId: callbackId});
      },
      publishHandler: function(e, p, viewIds) {
        window.webkit.messageHandlers.publishHandler.postMessage({event: e, paramsString: p, webviewIds: viewIds});
      }
    };
  }
})();
</script>
""";
      content = content.replaceFirst('<head>', '<head>$shim');

      PaminaLog.i('Page loading ${widget.path} with symlink support.', tag: 'PaminaPage');

      _controller.loadHtmlString(
        content,
        baseUrl: widget.sourcePath.endsWith('/') ? 'file://${widget.sourcePath}' : 'file://${widget.sourcePath}/',
      );

    } else {
      PaminaLog.e('页面文件不存在: ${pageFile.path}', tag: 'PaminaPage');
    }
  }

  void subscribeHandler(String event, String params) {
    final js = "window.HeraJSBridge && window.HeraJSBridge.subscribeHandler && window.HeraJSBridge.subscribeHandler('$event', $params)";
    
    if (!_isReady) {
      PaminaLog.d('Page[${widget.viewId}] Buffering subscribeHandler: $event', tag: 'PaminaPage');
      _messageBuffer.add(js);
      return;
    }
    _controller.runJavaScript(js);
  }

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

  void updateNavigationBar({
    String? title,
    String? backgroundColor,
    String? textColor,
    bool? isLoading,
    bool? showBack,
    VoidCallback? onBack,
  }) {
    if (!mounted) return;
    setState(() {
      if (title != null) _navBarTitle = title;
      if (backgroundColor != null) _navBarBgColor = backgroundColor;
      if (textColor != null) _navBarTextColor = textColor;
      if (isLoading != null) _navBarLoading = isLoading;
      if (showBack != null) _showBack = showBack;
      if (onBack != null) _onBack = onBack;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PaminaAppBar(
        title: _navBarTitle,
        backgroundColor: _navBarBgColor,
        textColor: _navBarTextColor,
        showBack: _showBack,
        isLoading: _navBarLoading,
        onBack: _onBack,
      ),
      body: widget.enablePullDownRefresh
          ? RefreshIndicator(
              key: _refreshIndicatorKey,
              onRefresh: () async {
                if (_pullDownRefreshCompleter != null) return;
                _pullDownRefreshCompleter = Completer<void>();
                if (widget.onPublish != null) {
                  widget.onPublish!('onPullDownRefresh', '{}', widget.viewId);
                }
                return _pullDownRefreshCompleter!.future;
              },
              child: Stack(
                children: [
                  ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height -
                            AppBar().preferredSize.height -
                            MediaQuery.of(context).padding.top,
                        child: WebViewWidget(
                          controller: _controller,
                          gestureRecognizers: {
                            Factory<VerticalDragGestureRecognizer>(() => VerticalDragGestureRecognizer()),
                            Factory<HorizontalDragGestureRecognizer>(() => HorizontalDragGestureRecognizer()),
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          : WebViewWidget(
              controller: _controller,
              gestureRecognizers: {
                Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
              },
            ),
    );
  }
}
