import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'sync/pamina_manager.dart';
import 'utils/storage_util.dart';
import 'pamina_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'pamina_page.dart';
import 'utils/pamina_log.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'widgets/pamina_ui_widgets.dart';

/// Pamina 容器 (App)
///
/// @author Parker
class PaminaApp extends StatefulWidget {
  final String appId;
  final String appPath;
  final String userId;

  const PaminaApp({
    super.key,
    required this.appId,
    required this.appPath,
    required this.userId,
  });

  @override
  State<PaminaApp> createState() => _PaminaAppState();
}

class _PaminaAppState extends State<PaminaApp> {
  final GlobalKey<PaminaServiceState> _serviceKey = GlobalKey();
  final Map<int, GlobalKey<PaminaPageState>> _pageKeys = {};
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  bool _isSyncing = true;
  bool _syncError = false;
  String? _sourcePath;

  /// 小程序全局配置 (app.json 内容)
  Map<String, dynamic>? _appConfig;

  /// 当前活跃页面 ID
  int _activePageId = 1;

  /// 首页路径
  String? _rootPage;

  /// TabBar 配置
  Map<String, dynamic>? _tabBarConfig;
  int _currentTabIndex = 0;

  /// 页面视图 ID 到路径的映射
  final Map<int, String> _viewIdToPath = {};

  /// 记录每个视图最后一次路由跳转的类型，用于 onAppRouteDone 回复
  final Map<int, String> _viewIdToOpenType = {};

  /// 所有已初始化的 Tab 视图 ID 列表
  final List<int> _tabViewIds = [];

  /// 非 Tab 页面栈 (存储 viewId)
  final List<int> _navigationStack = [];

  /// 下一个可用的 viewId (从 Tab 数量 + 1 开始)
  int _nextViewId = 1;

  /// 小程序所有页面路径列表 (从 app.json 解析)
  final List<String> _allPages = [];

  /// 已正式加载过的 Tab ID (Lazy Loading)
  final Set<int> _initializedTabViewIds = {};

  /// 标记逻辑层是否已经准备好 (serviceReady)
  bool _isServiceReady = false;

  /// 已完成 DOMContentLoaded 的视图 ID
  final Set<int> _readyViewIds = {};

  /// 页面初始化期间的消息缓冲区 (当 GlobalKey.currentState 为 null 时使用)
  final Map<int, List<Map<String, String>>> _pageMessageBuffer = {};

  /// 全局 Toast/Loading 配置
  Map<String, dynamic> _toastConfig = {
    'visible': false,
    'title': '',
    'icon': 'none',
    'mask': false,
  };
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    _initialSetup();
  }

  Future<void> _initialSetup() async {
    // 1. 启动时先清理内部资源目录，保持沙箱整洁
    // 先执行清理，再执行同步，避免两个任务同时操作 source 目录导致 OS Error 39 (Directory not empty)
    await StorageUtil.clearMiniAppInternalResourceDir(widget.appId);
    
    // 2. 然后再执行小程序资源同步
    _syncMiniApp();
  }

  Future<void> _syncMiniApp() async {
    final result = await PaminaManager.syncMiniApp(
      widget.appId,
      widget.appPath,
    );
    if (mounted) {
      String? sourcePath;
      if (result) {
        final dir = await StorageUtil.getMiniAppSourceDir(widget.appId);
        sourcePath = dir.path;
      }
      setState(() {
        _isSyncing = false;
        _syncError = !result;
        _sourcePath = sourcePath;
      });
    }
  }

  /// 处理来自逻辑层 (Service) 的事件
  void _handleServicePublish(String event, String params, String? viewIds) {
    if (event == 'custom_event_serviceReady') {
      _handleServiceReady(params);
      return;
    }

    // 转发给视图层 (Page)
    // viewIds 可能的形式： "1", "1,2", "[1]", "[]", "[\"\"]", "[100000]"
    List<int> targetIds = _parseViewIds(viewIds);

    // 如果 targetIds 为空，或者包含特殊的 100000 (Hera 的广播 ID)，则广播给所有已知的页面
    if (targetIds.isEmpty || targetIds.contains(100000)) {
      targetIds = _pageKeys.keys.toList();
    }

    final String p = params;
    for (final id in targetIds) {
      final pageState = _pageKeys[id]?.currentState;
      if (pageState != null) {
        pageState.subscribeHandler(event, p);
      } else {
        // 如果页面状态尚未就绪 (比如刚加入 IndexedStack 还没渲染)，存入父级缓冲区
        PaminaLog.d(
          'PaminaApp: Buffering message for uninitialized view $id (event: $event)',
          tag: 'PaminaApp',
        );
        _pageMessageBuffer.putIfAbsent(id, () => []).add({
          'event': event,
          'params': p,
        });
      }
    }
  }

  /// 当 PaminaPage 的 initState 执行时回调
  void _onPageReady(int viewId) {
    // 异步执行，确保 currentState 在下一帧可用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _drainPageMessageBuffer(viewId);
    });
  }

  void _onPageDispose(int viewId) {
    _pageKeys.remove(viewId);
    _viewIdToPath.remove(viewId);
    _viewIdToOpenType.remove(viewId);
    _readyViewIds.remove(viewId);
    _pageMessageBuffer.remove(viewId);
    PaminaLog.d('PaminaApp: Disposed state for view $viewId', tag: 'PaminaApp');
  }

  /// 消耗并发送缓冲区中的消息
  void _drainPageMessageBuffer(int viewId) {
    final buffer = _pageMessageBuffer.remove(viewId);
    if (buffer == null || buffer.isEmpty) return;

    final pageState = _pageKeys[viewId]?.currentState;
    if (pageState != null) {
      PaminaLog.i(
        'PaminaApp: Draining ${buffer.length} buffered messages for view $viewId',
        tag: 'PaminaApp',
      );
      for (final msg in buffer) {
        pageState.subscribeHandler(msg['event']!, msg['params']!);
      }
    }
  }

  /// 解析逻辑层传来的 webviewIds 字符串
  List<int> _parseViewIds(String? viewIds) {
    if (viewIds == null || viewIds.isEmpty) return [];

    try {
      // 尝试解析为 JSON 数组 (例如 "[1]" 或 "[\"1\"]")
      if (viewIds.startsWith('[') && viewIds.endsWith(']')) {
        final List list = json.decode(viewIds);
        return list
            .map((e) {
              final s = e.toString().trim();
              if (s.isEmpty) return 0;
              return int.tryParse(s) ?? 0;
            })
            .where((e) => e > 0)
            .toList();
      }
    } catch (e) {
      // 忽略解析错误，尝试逗号分隔解析
    }

    // 尝试逗号分隔解析 (例如 "1,2")
    return viewIds
        .split(',')
        .map((e) => int.tryParse(e.trim()) ?? 0)
        .where((e) => e > 0)
        .toList();
  }

  /// 根据页面路径获取特定配置 (如标题、颜色)
  Map<String, String> _getPageConfig(String path) {
    if (_appConfig == null) return {};
    final window = _appConfig!['window'] as Map<String, dynamic>?;
    if (window == null) return {};

    // 1. 默认值 (全局 window 配置)
    String title = window['navigationBarTitleText']?.toString() ?? '';
    String bgColor =
        window['navigationBarBackgroundColor']?.toString() ?? '#F7F7F7';
    String textColor = window['navigationBarTextStyle']?.toString() ?? 'black';
    bool enableRefresh = window['enablePullDownRefresh'] == true;

    // 2. 页面特定配置 (pages 映射)
    final pages = window['pages'] as Map<String, dynamic>?;
    if (pages != null && pages.containsKey(path)) {
      final pageConfig = pages[path] as Map<String, dynamic>;
      if (pageConfig.containsKey('navigationBarTitleText')) {
        title = pageConfig['navigationBarTitleText'].toString();
      }
      if (pageConfig.containsKey('navigationBarBackgroundColor')) {
        bgColor = pageConfig['navigationBarBackgroundColor'].toString();
      }
      if (pageConfig.containsKey('navigationBarTextStyle')) {
        textColor = pageConfig['navigationBarTextStyle'].toString();
      }
      if (pageConfig.containsKey('enablePullDownRefresh')) {
        enableRefresh = pageConfig['enablePullDownRefresh'] == true;
      }
    }

    return {
      'title': title,
      'backgroundColor': bgColor,
      'textColor': textColor,
      'enablePullDownRefresh': enableRefresh.toString(),
    };
  }

  /// 处理来自视图层 (Page) 的事件
  void _handlePagePublish(String event, String params, int viewId) {
    // 将页面事件转发给 Service (例如 DOMContentLoaded)
    _serviceKey.currentState?.subscribeHandler(event, params, viewId);

    // 如果是 DOMContentLoaded，代表视图层 DOM 加载完成，通知逻辑层
    if (event == 'custom_event_DOMContentLoaded') {
      _readyViewIds.add(viewId);
      final openType = _viewIdToOpenType[viewId] ?? 'appLaunch';
      final path = _viewIdToPath[viewId] ?? '';

      // 尝试触发首屏跳转
      _tryTriggerAppLaunch(viewId);

      _serviceKey.currentState?.onAppRouteDone(openType, path, viewId);
    }
  }

  void _tryTriggerAppLaunch(int viewId) {
    if (_isServiceReady &&
        _readyViewIds.contains(viewId) &&
        _viewIdToOpenType[viewId] == 'appLaunch') {
      final path = _viewIdToPath[viewId] ?? '';
      PaminaLog.i('Triggering $viewId appLaunch (path: $path)', tag: 'PaminaApp');

      // 标记为已启动，防止重复进入此逻辑
      _viewIdToOpenType[viewId] = 'navigating';

      _serviceKey.currentState?.onAppRoute('appLaunch', path, viewId);
    }
  }

  /// 处理来自 Service/Page 的 API 调用 (Invoke)
  void _handleInvoke(
    String event,
    String params,
    String? callbackId, {
    int? fromViewId,
  }) {
    PaminaLog.i('API Invoke: $event (callbackId: $callbackId)', tag: 'PaminaApp');

    switch (event) {
      case 'initReady':
        // 视图层初始化完毕的确认
        _handleInvokeCallback(event, {}, callbackId, fromViewId: fromViewId);
        break;
      case 'getSystemInfo':
        _handleGetSystemInfo(callbackId, fromViewId);
        break;
      case 'setNavigationBarTitle':
        final title = json.decode(params)['title']?.toString() ?? '';
        _pageKeys[fromViewId ?? _activePageId]?.currentState?.updateNavigationBar(title: title);
        _handleInvokeCallback(event, {}, callbackId, fromViewId: fromViewId);
        break;
      case 'setNavigationBarColor':
        final p = json.decode(params);
        final bgColor = p['backgroundColor']?.toString();
        final textColor = p['frontColor']?.toString();
        _pageKeys[fromViewId ?? _activePageId]?.currentState?.updateNavigationBar(
          backgroundColor: bgColor,
          textColor: textColor != null ? (textColor.contains('ffffff') ? 'white' : 'black') : null,
        );
        _handleInvokeCallback(event, {}, callbackId, fromViewId: fromViewId);
        break;
      case 'navigateTo':
        _handleNavigateTo(params, callbackId, fromViewId);
        break;
      case 'redirectTo':
        _handleRedirectTo(params, callbackId, fromViewId);
        break;
      case 'navigateBack':
        _handleNavigateBack(params, callbackId, fromViewId);
        break;
      case 'switchTab':
        _handleSwitchTab(params, callbackId, fromViewId);
        break;
      case 'openLink':
        _handleOpenLink(params, callbackId, fromViewId);
        break;
      case 'showNavigationBarLoading':
        _pageKeys[fromViewId ?? _activePageId]?.currentState?.updateNavigationBar(isLoading: true);
        _handleInvokeCallback(event, {}, callbackId, fromViewId: fromViewId);
        break;
      case 'hideNavigationBarLoading':
        _pageKeys[fromViewId ?? _activePageId]?.currentState?.updateNavigationBar(isLoading: false);
        _handleInvokeCallback(event, {}, callbackId, fromViewId: fromViewId);
        break;
      case 'showToast':
        _handleShowToast(params, callbackId, fromViewId);
        break;
      case 'hideToast':
        _handleHideToast(callbackId, fromViewId);
        break;
      case 'showLoading':
        _handleShowLoading(params, callbackId, fromViewId);
        break;
      case 'hideLoading':
        _handleHideToast(callbackId, fromViewId); // hideLoading typically uses hideToast logic
        break;
      case 'startPullDownRefresh':
        _pageKeys[fromViewId ?? _activePageId]?.currentState?.startPullDownRefresh();
        _handleInvokeCallback(event, {}, callbackId, fromViewId: fromViewId);
        break;
      case 'stopPullDownRefresh':
        _pageKeys[fromViewId ?? _activePageId]?.currentState?.stopPullDownRefresh();
        _handleInvokeCallback(event, {}, callbackId, fromViewId: fromViewId);
        break;
      case 'showActionSheet':
        _handleShowActionSheet(params, callbackId, fromViewId);
        break;
      case 'showModal':
        _handleShowModal(params, callbackId, fromViewId);
        break;
      case 'getNetworkType':
        _handleGetNetworkType(callbackId, fromViewId);
        break;
      case 'makePhoneCall':
        _handleMakePhoneCall(params, callbackId, fromViewId);
        break;
      case 'reportIDKey':
        _handleReportIDKey(params, callbackId, fromViewId);
        break;
      case 'scanCode':
        _handleScanCode(params, callbackId, fromViewId);
        break;
      case 'request':
        _handleRequest(params, callbackId, fromViewId);
        break;
      case 'chooseImage':
        _handleChooseImage(params, callbackId, fromViewId);
        break;
      case 'uploadFile':
        _handleUploadFile(params, callbackId, fromViewId);
        break;
      case 'downloadFile':
        _handleDownloadFile(params, callbackId, fromViewId);
        break;
      case 'saveFile':
        _handleSaveFile(params, callbackId, fromViewId);
        break;
      case 'setStorage':
      case 'setStorageAsync':
      case 'setStorageSync':
        _handleSetStorage(params, callbackId, fromViewId, isSync: event.endsWith('Sync'));
        break;
      case 'getStorage':
      case 'getStorageAsync':
      case 'getStorageSync':
        _handleGetStorage(params, callbackId, fromViewId, isSync: event.endsWith('Sync'));
        break;
      case 'removeStorage':
      case 'removeStorageAsync':
      case 'removeStorageSync':
        _handleRemoveStorage(params, callbackId, fromViewId, isSync: event.endsWith('Sync'));
        break;
      case 'clearStorage':
      case 'clearStorageAsync':
      case 'clearStorageSync':
        _handleClearStorage(params, callbackId, fromViewId, isSync: event.endsWith('Sync'));
        break;
      case 'getStorageInfo':
      case 'getStorageInfoAsync':
      case 'getStorageInfoSync':
        _handleGetStorageInfo(callbackId, fromViewId, isSync: event.endsWith('Sync'));
        break;
      default:
        PaminaLog.w('Unhandled API: $event', tag: 'PaminaApp');
    }
  }

  void _handleInvokeCallback(
    String event,
    Map<String, dynamic> result,
    String? callbackId, {
    int? fromViewId,
  }) {
    if (callbackId == null) return;

    final res = {'errMsg': '$event:ok', ...result};
    final resJson = json.encode(res);

    if (fromViewId != null) {
      _pageKeys[fromViewId]?.currentState?.invokeCallbackHandler(
        callbackId,
        resJson,
      );
    } else {
      _serviceKey.currentState?.invokeCallbackHandler(callbackId, resJson);
    }
  }

  void _handleShowToast(String params, String? callbackId, int? fromViewId) {
    final Map<String, dynamic> data = json.decode(params);
    final String title = data['title']?.toString() ?? '';
    final String icon = data['icon']?.toString() ?? 'success';
    final int duration = data['duration'] is int ? data['duration'] : 1500;
    final bool mask = data['mask'] == true;

    PaminaLog.d('Showing toast: title=$title, icon=$icon, duration=$duration, mask=$mask', tag: 'PaminaApp');

    _toastTimer?.cancel();
    setState(() {
      _toastConfig = {
        'visible': true,
        'title': title,
        'icon': icon,
        'mask': mask,
      };
    });

    if (duration > 0) {
      _toastTimer = Timer(Duration(milliseconds: duration), () {
        if (mounted) {
          PaminaLog.d('Toast auto-hiding after $duration ms', tag: 'PaminaApp');
          setState(() {
            _toastConfig = Map.from(_toastConfig)..['visible'] = false;
          });
        }
      });
    }

    _handleInvokeCallback('showToast', {}, callbackId, fromViewId: fromViewId);
  }

  void _handleShowLoading(String params, String? callbackId, int? fromViewId) {
    final Map<String, dynamic> data = json.decode(params);
    final String title = data['title']?.toString() ?? '';
    final bool mask = data['mask'] == true;

    PaminaLog.d('Showing loading: title=$title, mask=$mask', tag: 'PaminaApp');

    _toastTimer?.cancel();
    setState(() {
      _toastConfig = {
        'visible': true,
        'title': title,
        'icon': 'loading',
        'mask': mask,
      };
    });

    _handleInvokeCallback('showLoading', {}, callbackId, fromViewId: fromViewId);
  }

  void _handleHideToast(String? callbackId, int? fromViewId) {
    PaminaLog.d('Hiding toast/loading', tag: 'PaminaApp');
    _toastTimer?.cancel();
    setState(() {
      _toastConfig = Map.from(_toastConfig)..['visible'] = false;
    });
    _handleInvokeCallback('hideToast', {}, callbackId, fromViewId: fromViewId);
  }

  void _handleShowActionSheet(String params, String? callbackId, int? fromViewId) {
    try {
      final Map<String, dynamic> data = json.decode(params);
      final List itemList = data['itemList'] ?? [];
      final String itemColorStr = data['itemColor']?.toString() ?? '#000000';
      final String cancelText = data['cancelText']?.toString() ?? '取消';
      final String cancelColorStr = data['cancelColor']?.toString() ?? '#000000';

      PaminaLog.i('Showing action sheet: ${itemList.length} items', tag: 'PaminaApp');

      final Color itemColor = _parseColor(itemColorStr);
      final Color cancelColor = _parseColor(cancelColorStr);

      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...List.generate(itemList.length, (index) {
                    return Column(
                      children: [
                        InkWell(
                          onTap: () {
                            PaminaLog.i('Action sheet item $index selected', tag: 'PaminaApp');
                            Navigator.pop(context, index);
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            alignment: Alignment.center,
                            child: Text(
                              itemList[index].toString(),
                              style: TextStyle(color: itemColor, fontSize: 18),
                            ),
                          ),
                        ),
                        if (index < itemList.length - 1)
                          const Divider(
                            height: 0.5,
                            thickness: 0.5,
                            color: Colors.black12,
                          ),
                      ],
                    );
                  }),
                  Container(height: 8, color: Colors.black12.withOpacity(0.05)),
                  InkWell(
                    onTap: () {
                      PaminaLog.i('Action sheet cancelled', tag: 'PaminaApp');
                      Navigator.pop(context);
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      alignment: Alignment.center,
                      child: Text(
                        cancelText,
                        style: TextStyle(color: cancelColor, fontSize: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ).then((index) {
        if (index != null && index is int) {
          _handleInvokeCallback('showActionSheet', {'tapIndex': index}, callbackId, fromViewId: fromViewId);
        } else {
          _handleInvokeCallback('showActionSheet', {'errMsg': 'showActionSheet:fail cancel'}, callbackId, fromViewId: fromViewId);
        }
      });
    } catch (e) {
      PaminaLog.e('Handle showActionSheet error', error: e, tag: 'PaminaApp');
      _handleInvokeCallback('showActionSheet', {'errMsg': 'showActionSheet:fail $e'}, callbackId, fromViewId: fromViewId);
    }
  }

  void _handleShowModal(String params, String? callbackId, int? fromViewId) {
    try {
      final Map<String, dynamic> data = json.decode(params);
      final String title = data['title']?.toString() ?? '';
      final String content = data['content']?.toString() ?? '';
      final bool showCancel = data['showCancel'] ?? true;
      final String cancelText = data['cancelText']?.toString() ?? '取消';
      final String cancelColorStr = data['cancelColor']?.toString() ?? '#000000';
      final String confirmText = data['confirmText']?.toString() ?? '确定';
      final String confirmColorStr = data['confirmColor']?.toString() ?? '#3CC51F';

      PaminaLog.i('Showing custom modal: $title', tag: 'PaminaApp');

      final Color cancelColor = _parseColor(cancelColorStr);
      final Color confirmColor = _parseColor(confirmColorStr);

      showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return PaminaCustomModal(
            title: title,
            content: content,
            showCancel: showCancel,
            cancelText: cancelText,
            cancelColor: cancelColor,
            confirmText: confirmText,
            confirmColor: confirmColor,
            onAction: (confirmed) => Navigator.pop(context, confirmed),
          );
        },
      ).then((confirmed) {
        final bool isConfirm = confirmed == true;
        _handleInvokeCallback(
          'showModal',
          {'confirm': isConfirm, 'cancel': !isConfirm},
          callbackId,
          fromViewId: fromViewId,
        );
      });
    } catch (e) {
      PaminaLog.e('Handle showModal error', error: e, tag: 'PaminaApp');
      _handleInvokeCallback('showModal', {'errMsg': 'showModal:fail $e'}, callbackId, fromViewId: fromViewId);
    }
  }

  Color _parseColor(String colorStr, {Color defaultColor = Colors.black}) {
    if (colorStr.isEmpty) return defaultColor;
    String hex = colorStr.replaceAll('#', '');
    if (hex.length == 6) {
      hex = 'FF$hex';
    } else if (hex.length == 3) {
      final r = hex[0];
      final g = hex[1];
      final b = hex[2];
      hex = 'FF$r$r$g$g$b$b';
    } else if (hex.length == 8) {
      // already has alpha
    } else {
      return defaultColor;
    }
    try {
      return Color(int.parse(hex, radix: 16));
    } catch (e) {
      return defaultColor;
    }
  }

  void _handleGetSystemInfo(String? callbackId, int? fromViewId) async {
    final media = MediaQuery.of(context);
    final deviceInfo = DeviceInfoPlugin();
    String brand = 'Unknown';
    String model = 'Virtual Device';
    String system = 'Unknown';
    String platform = Theme.of(context).platform == TargetPlatform.iOS ? 'ios' : 'android';

    try {
      if (Theme.of(context).platform == TargetPlatform.android) {
        final androidInfo = await deviceInfo.androidInfo;
        brand = androidInfo.brand;
        model = androidInfo.model;
        system = 'Android ${androidInfo.version.release}';
      } else if (Theme.of(context).platform == TargetPlatform.iOS) {
        final iosInfo = await deviceInfo.iosInfo;
        brand = 'Apple';
        model = iosInfo.utsname.machine; 
        system = '${iosInfo.systemName} ${iosInfo.systemVersion}';
      }
    } catch (e) {
      PaminaLog.w('Failed to get device info: $e', tag: 'PaminaApp');
    }

    // WeChat values are rounded to logical pixels
    final double pixelRatio = media.devicePixelRatio;
    final double screenWidth = media.size.width;
    final double screenHeight = media.size.height;
    
    // Calculate windowHeight correctly
    // Available height = screenHeight - statusBar - navigationBar (56) - tabBar (if any)
    double windowHeight = screenHeight;
    windowHeight -= media.padding.top; // statusBar
    windowHeight -= 56; // navigationBar (PaminaPage AppBar height)
    
    // TabBar height
    bool hasTabBar = _navigationStack.isEmpty && _tabBarConfig != null;
    if (hasTabBar) {
      // BottomNavigationBar height is roughly 56 + bottom padding
      windowHeight -= (56 + media.padding.bottom);
    } else {
       // On sub-pages, we still might have bottom padding (home indicator)
       windowHeight -= media.padding.bottom;
    }

    final data = {
      'brand': brand,
      'model': model,
      'pixelRatio': pixelRatio, 
      'screenWidth': screenWidth.round(),
      'screenHeight': screenHeight.round(),
      'windowWidth': screenWidth.round(),
      'windowHeight': windowHeight.round(),
      'statusBarHeight': media.padding.top.round(),
      'language': 'zh_CN',
      'version': '1.0.0',
      'system': system,
      'platform': platform,
      'fontSizeSetting': 16,
      'SDKVersion': '1.0.0',
      'safeArea': {
        'top': media.padding.top.round(),
        'left': media.padding.left.round(),
        'right': (screenWidth - media.padding.right).round(),
        'bottom': (screenHeight - media.padding.bottom).round(),
        'width': screenWidth.round(),
        'height': (screenHeight - media.padding.top - media.padding.bottom).round(),
      }
    };

    _handleInvokeCallback(
      'getSystemInfo',
      data,
      callbackId,
      fromViewId: fromViewId,
    );
  }

  void _handleGetNetworkType(String? callbackId, int? fromViewId) async {
    try {
      final List<ConnectivityResult> connectivityResults = await Connectivity().checkConnectivity();
      String networkType = 'unknown';

      if (connectivityResults.contains(ConnectivityResult.none)) {
        networkType = 'none';
      } else if (connectivityResults.contains(ConnectivityResult.wifi)) {
        networkType = 'wifi';
      } else if (connectivityResults.contains(ConnectivityResult.mobile)) {
        // Standard mini-app returns '2g', '3g', '4g', '5g'. 
        // connectivity_plus doesn't distinguish easily without more plugins.
        // Defaulting to '4g' or 'mobile' is common for simple bridges.
        networkType = 'mobile';
      } else if (connectivityResults.contains(ConnectivityResult.ethernet)) {
        networkType = 'ethernet';
      }

      PaminaLog.i('Network type: $networkType', tag: 'PaminaApp');
      _handleInvokeCallback('getNetworkType', {'networkType': networkType}, callbackId, fromViewId: fromViewId);
    } catch (e) {
      PaminaLog.e('Handle getNetworkType error', error: e, tag: 'PaminaApp');
      _handleInvokeCallback('getNetworkType', {'errMsg': 'getNetworkType:fail $e'}, callbackId, fromViewId: fromViewId);
    }
  }

  void _handleMakePhoneCall(String params, String? callbackId, int? fromViewId) async {
    try {
      final Map<String, dynamic> data = json.decode(params);
      final String phoneNumber = data['phoneNumber']?.toString() ?? '';
      
      if (phoneNumber.isEmpty) {
        _handleInvokeCallback('makePhoneCall', {'errMsg': 'makePhoneCall:fail invalid phoneNumber'}, callbackId, fromViewId: fromViewId);
        return;
      }

      final Uri url = Uri.parse('tel:$phoneNumber');
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
        _handleInvokeCallback('makePhoneCall', {}, callbackId, fromViewId: fromViewId);
      } else {
        _handleInvokeCallback('makePhoneCall', {'errMsg': 'makePhoneCall:fail cannot launch tel protocol'}, callbackId, fromViewId: fromViewId);
      }
    } catch (e) {
      PaminaLog.e('Handle makePhoneCall error', error: e, tag: 'PaminaApp');
      _handleInvokeCallback('makePhoneCall', {'errMsg': 'makePhoneCall:fail $e'}, callbackId, fromViewId: fromViewId);
    }
  }

  void _handleReportIDKey(String params, String? callbackId, int? fromViewId) {
    // Stub for analytics: just log & return ok
    PaminaLog.d('Analytics reportIDKey: $params', tag: 'PaminaApp');
    _handleInvokeCallback('reportIDKey', {}, callbackId, fromViewId: fromViewId);
  }

  void _handleScanCode(String params, String? callbackId, int? fromViewId) async {
    try {
      PaminaLog.i('Opening scanner...', tag: 'PaminaApp');
      final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (context) => const PaminaScanner()),
      );

      if (result != null) {
        _handleInvokeCallback('scanCode', {
          'result': result,
          'scanType': 'QR_CODE', // Default for now
          'charSet': 'UTF-8',
          'errMsg': 'scanCode:ok'
        }, callbackId, fromViewId: fromViewId);
      } else {
        _handleInvokeCallback('scanCode', {'errMsg': 'scanCode:fail cancel'}, callbackId, fromViewId: fromViewId);
      }
    } catch (e) {
      PaminaLog.e('Handle scanCode error', error: e, tag: 'PaminaApp');
      _handleInvokeCallback('scanCode', {'errMsg': 'scanCode:fail $e'}, callbackId, fromViewId: fromViewId);
    }
  }

  void _handleRequest(String params, String? callbackId, int? fromViewId) async {
    try {
      final Map<String, dynamic> data = json.decode(params);
      final String url = data['url']?.toString() ?? '';
      final String method = (data['method']?.toString() ?? 'GET').toUpperCase();
      final dynamic body = data['data'];
      final Map<String, String> headers = {};
      if (data['header'] is Map) {
        (data['header'] as Map).forEach((key, value) {
          headers[key.toString()] = value.toString();
        });
      }

      PaminaLog.i('HTTP Request: $method $url', tag: 'PaminaApp');

      http.Response response;
      final uri = Uri.parse(url);

      switch (method) {
        case 'POST':
          response = await http.post(uri, headers: headers, body: body is String ? body : json.encode(body));
          break;
        case 'PUT':
          response = await http.put(uri, headers: headers, body: body is String ? body : json.encode(body));
          break;
        case 'DELETE':
          response = await http.delete(uri, headers: headers, body: body is String ? body : json.encode(body));
          break;
        case 'GET':
        default:
          // For GET, standard wx.request might append data to query params, 
          // but usually it's already in the URL provided.
          response = await http.get(uri, headers: headers);
          break;
      }

      // WeChat returns data as either String or Map depending on Content-Type
      dynamic responseData = response.body;
      final contentType = response.headers['content-type'] ?? '';
      if (contentType.contains('application/json')) {
        try {
          responseData = json.decode(response.body);
        } catch (e) {
          // keep as string if decode fails
        }
      }

      _handleInvokeCallback('request', {
        'data': responseData,
        'statusCode': response.statusCode,
        'header': response.headers,
      }, callbackId, fromViewId: fromViewId);
    } catch (e) {
      PaminaLog.e('Handle request error', error: e, tag: 'PaminaApp');
      _handleInvokeCallback('request', {'errMsg': 'request:fail $e'}, callbackId, fromViewId: fromViewId);
    }
  }

  void _handleChooseImage(String params, String? callbackId, int? fromViewId) async {
    try {
      final Map<String, dynamic> data = json.decode(params);
      final int count = data['count'] is int ? data['count'] : 9;
      final List sourceType = data['sourceType'] ?? ['album', 'camera'];

      PaminaLog.i('Choosing image: count=$count, sourceType=$sourceType', tag: 'PaminaApp');

      final picker = ImagePicker();
      final List<XFile> files = [];

      // If both album and camera are allowed, we might need to show an action sheet first 
      // or rely on image_picker's behavior if it supports multiple sources.
      // But standard image_picker requires picking one source.
      
      String? selectedSource;
      if (sourceType.length > 1) {
        // Show action sheet to choose source
        final index = await showModalBottomSheet<int>(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (context) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () => Navigator.pop(context, 0),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        alignment: Alignment.center,
                        child: const Text('从相册选择', style: TextStyle(fontSize: 18)),
                      ),
                    ),
                    const Divider(height: 0.5),
                    InkWell(
                      onTap: () => Navigator.pop(context, 1),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        alignment: Alignment.center,
                        child: const Text('拍照', style: TextStyle(fontSize: 18)),
                      ),
                    ),
                    Container(height: 8, color: Colors.black12.withOpacity(0.05)),
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        alignment: Alignment.center,
                        child: const Text('取消', style: TextStyle(fontSize: 18)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );

        if (index == 0) selectedSource = 'album';
        else if (index == 1) selectedSource = 'camera';
        else {
          _handleInvokeCallback('chooseImage', {'errMsg': 'chooseImage:fail cancel'}, callbackId, fromViewId: fromViewId);
          return;
        }
      } else {
        selectedSource = sourceType.first.toString();
      }

      if (selectedSource == 'camera') {
        final XFile? photo = await picker.pickImage(source: ImageSource.camera);
        if (photo != null) files.add(photo);
      } else {
        if (count > 1) {
          // 明确传递 limit 参数，有助于某些平台弹出支持多选的 UI
          files.addAll(await picker.pickMultiImage(limit: count));
          PaminaLog.i('PickMultiImage returned ${files.length} files', tag: 'PaminaApp');
          // 兜底截断
          if (files.length > count) {
            files.removeRange(count, files.length);
          }
        } else {
          final XFile? image = await picker.pickImage(source: ImageSource.gallery);
          if (image != null) files.add(image);
        }
      }

      if (files.isEmpty) {
        _handleInvokeCallback('chooseImage', {'errMsg': 'chooseImage:fail cancel'}, callbackId, fromViewId: fromViewId);
        return;
      }

      final List<String> tempFilePaths = [];
      final List<Map<String, dynamic>> tempFiles = [];

      final resourceDir = await StorageUtil.getMiniAppInternalResourceDir(widget.appId);
      final random = DateTime.now().microsecondsSinceEpoch;

      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        // 将文件拷贝到 source 目录下的受控资源目录中，以绕过 WebView 同源策略限制
        // 使用微秒戳 + 循环索引 + 原始名称后缀，确保在高速循环中文件名绝对唯一
        final extension = p.extension(file.path);
        final fileName = 'res_${random}_${i}${extension}';
        final targetFile = File(p.join(resourceDir.path, fileName));
        await File(file.path).copy(targetFile.path);

        // 使用 Uri.file 会自动处理中文字符等特殊路径的 URL 编码
        final path = Uri.file(targetFile.path).toString();
        final size = await targetFile.length();
        tempFilePaths.add(path);
        tempFiles.add({
          'path': path,
          'size': size,
        });
      }

      PaminaLog.i('ChooseImage results: $tempFilePaths', tag: 'PaminaApp');

      _handleInvokeCallback('chooseImage', {
        'tempFilePaths': tempFilePaths,
        'tempFiles': tempFiles,
      }, callbackId, fromViewId: fromViewId);
    } catch (e) {
      PaminaLog.e('Handle chooseImage error', error: e, tag: 'PaminaApp');
      _handleInvokeCallback('chooseImage', {'errMsg': 'chooseImage:fail $e'}, callbackId, fromViewId: fromViewId);
    }
  }

  void _handleUploadFile(String params, String? callbackId, int? fromViewId) async {
    try {
      final Map<String, dynamic> data = json.decode(params);
      final String url = data['url']?.toString() ?? '';
      String filePath = data['filePath']?.toString() ?? '';
      
      // 处理 file:// 协议头，http.MultipartFile.fromPath 需要原始路径
      if (filePath.startsWith('file://')) {
        filePath = filePath.replaceFirst('file://', '');
      }
      
      final String name = data['name']?.toString() ?? 'file';
      final Map<String, String> headers = {};
      if (data['header'] is Map) {
        (data['header'] as Map).forEach((key, value) {
          headers[key.toString()] = value.toString();
        });
      }
      final Map<String, String> formData = {};
      if (data['formData'] is Map) {
        (data['formData'] as Map).forEach((key, value) {
          formData[key.toString()] = value.toString();
        });
      }

      PaminaLog.i('HTTP Upload: $url, file: $filePath', tag: 'PaminaApp');

      final uri = Uri.parse(url);
      final request = http.MultipartRequest('POST', uri);
      
      request.headers.addAll(headers);
      request.fields.addAll(formData);
      
      final file = await http.MultipartFile.fromPath(name, filePath);
      request.files.add(file);

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      PaminaLog.i('Upload response: ${response.statusCode}', tag: 'PaminaApp');

      _handleInvokeCallback('uploadFile', {
        'data': response.body,
        'statusCode': response.statusCode,
      }, callbackId, fromViewId: fromViewId);
    } catch (e) {
      PaminaLog.e('Handle uploadFile error', error: e, tag: 'PaminaApp');
      _handleInvokeCallback('uploadFile', {'errMsg': 'uploadFile:fail $e'}, callbackId, fromViewId: fromViewId);
    }
  }

  void _handleDownloadFile(String params, String? callbackId, int? fromViewId) async {
    try {
      final Map<String, dynamic> data = json.decode(params);
      final String url = data['url']?.toString() ?? '';
      final Map<String, String> headers = {};
      if (data['header'] is Map) {
        (data['header'] as Map).forEach((key, value) {
          headers[key.toString()] = value.toString();
        });
      }

      PaminaLog.i('HTTP Download: $url', tag: 'PaminaApp');

      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode == 200) {
        final resourceDir = await StorageUtil.getMiniAppInternalResourceDir(widget.appId);
        final random = DateTime.now().microsecondsSinceEpoch;
        final extension = p.extension(Uri.parse(url).path);
        final fileName = 'dl_${random}${extension}';
        final file = File(p.join(resourceDir.path, fileName));
        await file.writeAsBytes(response.bodyBytes);

        PaminaLog.i('Downloaded file saved to internal resource: ${file.path}', tag: 'PaminaApp');

        _handleInvokeCallback('downloadFile', {
          'tempFilePath': Uri.file(file.path).toString(),
          'statusCode': response.statusCode,
        }, callbackId, fromViewId: fromViewId);
      } else {
        _handleInvokeCallback('downloadFile', {
          'errMsg': 'downloadFile:fail status code ${response.statusCode}',
          'statusCode': response.statusCode,
        }, callbackId, fromViewId: fromViewId);
      }
    } catch (e) {
      PaminaLog.e('Handle downloadFile error', error: e, tag: 'PaminaApp');
      _handleInvokeCallback('downloadFile', {'errMsg': 'downloadFile:fail $e'}, callbackId, fromViewId: fromViewId);
    }
  }

  void _handleSaveFile(String params, String? callbackId, int? fromViewId) async {
    try {
      final Map<String, dynamic> data = json.decode(params);
      String tempFilePath = data['tempFilePath']?.toString() ?? '';

      if (tempFilePath.startsWith('file://')) {
        tempFilePath = Uri.parse(tempFilePath).toFilePath();
      }

      final file = File(tempFilePath);
      if (!file.existsSync()) {
        _handleInvokeCallback('saveFile', {'errMsg': 'saveFile:fail file not found'}, callbackId, fromViewId: fromViewId);
        return;
      }

      final storeDir = await StorageUtil.getMiniAppStoreDir(widget.appId);
      final fileName = 'store_${DateTime.now().microsecondsSinceEpoch}${p.extension(tempFilePath)}';
      final targetPath = p.join(storeDir.path, fileName);

      await file.copy(targetPath);

      _handleInvokeCallback('saveFile', {
        'savedFilePath': Uri.file(targetPath).toString(),
      }, callbackId, fromViewId: fromViewId);
    } catch (e) {
      PaminaLog.e('Handle saveFile error', error: e, tag: 'PaminaApp');
      _handleInvokeCallback('saveFile', {'errMsg': 'saveFile:fail $e'}, callbackId, fromViewId: fromViewId);
    }
  }

  Future<Map<String, dynamic>> _readStorage() async {
    try {
      final file = await StorageUtil.getMiniAppStorageFile(widget.appId);
      if (file.existsSync()) {
        final content = await file.readAsString();
        return json.decode(content) as Map<String, dynamic>;
      }
    } catch (e) {
      PaminaLog.e('Read storage error', error: e, tag: 'PaminaApp');
    }
    return {};
  }

  Future<void> _writeStorage(Map<String, dynamic> data) async {
    try {
      final file = await StorageUtil.getMiniAppStorageFile(widget.appId);
      await file.writeAsString(json.encode(data));
    } catch (e) {
      PaminaLog.e('Write storage error', error: e, tag: 'PaminaApp');
    }
  }

  void _handleSetStorage(String params, String? callbackId, int? fromViewId, {bool isSync = false}) async {
    final eventName = isSync ? 'setStorageSync' : 'setStorage';
    try {
      final Map<String, dynamic> data = json.decode(params);
      final String key = data['key']?.toString() ?? '';
      final dynamic value = data['data'];

      final storage = await _readStorage();
      storage[key] = value;
      await _writeStorage(storage);

      _handleInvokeCallback(eventName, {'errMsg': '$eventName:ok'}, callbackId, fromViewId: fromViewId);
    } catch (e) {
      _handleInvokeCallback(eventName, {'errMsg': '$eventName:fail $e'}, callbackId, fromViewId: fromViewId);
    }
  }

  void _handleGetStorage(String params, String? callbackId, int? fromViewId, {bool isSync = false}) async {
    final eventName = isSync ? 'getStorageSync' : 'getStorage';
    try {
      final Map<String, dynamic> data = json.decode(params);
      final String key = data['key']?.toString() ?? '';

      final storage = await _readStorage();
      final dynamic value = storage[key];

      _handleInvokeCallback(eventName, {
        'data': value,
        'errMsg': '$eventName:ok'
      }, callbackId, fromViewId: fromViewId);
    } catch (e) {
      _handleInvokeCallback(eventName, {'errMsg': '$eventName:fail $e'}, callbackId, fromViewId: fromViewId);
    }
  }

  void _handleRemoveStorage(String params, String? callbackId, int? fromViewId, {bool isSync = false}) async {
    final eventName = isSync ? 'removeStorageSync' : 'removeStorage';
    try {
      final Map<String, dynamic> data = json.decode(params);
      final String key = data['key']?.toString() ?? '';

      final storage = await _readStorage();
      storage.remove(key);
      await _writeStorage(storage);

      _handleInvokeCallback(eventName, {'errMsg': '$eventName:ok'}, callbackId, fromViewId: fromViewId);
    } catch (e) {
      _handleInvokeCallback(eventName, {'errMsg': '$eventName:fail $e'}, callbackId, fromViewId: fromViewId);
    }
  }

  void _handleClearStorage(String params, String? callbackId, int? fromViewId, {bool isSync = false}) async {
    final eventName = isSync ? 'clearStorageSync' : 'clearStorage';
    try {
      await _writeStorage({});
      _handleInvokeCallback(eventName, {'errMsg': '$eventName:ok'}, callbackId, fromViewId: fromViewId);
    } catch (e) {
      _handleInvokeCallback(eventName, {'errMsg': '$eventName:fail $e'}, callbackId, fromViewId: fromViewId);
    }
  }

  void _handleGetStorageInfo(String? callbackId, int? fromViewId, {bool isSync = false}) async {
    final eventName = isSync ? 'getStorageInfoSync' : 'getStorageInfo';
    try {
      final storage = await _readStorage();
      final keys = storage.keys.toList();
      final currentSize = json.encode(storage).length; // Rough estimate in bytes

      _handleInvokeCallback(eventName, {
        'keys': keys,
        'currentSize': (currentSize / 1024).round(), // in KB
        'limitSize': 10240, // 10MB limit
        'errMsg': '$eventName:ok'
      }, callbackId, fromViewId: fromViewId);
    } catch (e) {
      _handleInvokeCallback(eventName, {'errMsg': '$eventName:fail $e'}, callbackId, fromViewId: fromViewId);
    }
  }

  void _handleNavigateTo(String params, String? callbackId, int? fromViewId) {
    final Map<String, dynamic> data = json.decode(params);
    String url = data['url']?.toString() ?? '';
    final path = _normalizeUrl(url, fromViewId: fromViewId);

    final int viewId = _nextViewId++;
    _viewIdToPath[viewId] = path;
    _viewIdToOpenType[viewId] = 'navigateTo';
    _pageKeys[viewId] = GlobalKey<PaminaPageState>();

    setState(() {
      _navigationStack.add(viewId);
      _activePageId = viewId;
    });

    _navigatorKey.currentState?.pushNamed('/page', arguments: viewId);

    _handleInvokeCallback('navigateTo', {}, callbackId, fromViewId: fromViewId);

    // 发送路由事件给 Service (使用原始 path 以支持框架内部解析)
    _serviceKey.currentState?.onAppRoute('navigateTo', path, viewId);
  }

  void _handleRedirectTo(String params, String? callbackId, int? fromViewId) {
    final Map<String, dynamic> data = json.decode(params);
    String url = data['url']?.toString() ?? '';
    final path = _normalizeUrl(url, fromViewId: fromViewId);

    final bool wasSubPage = _navigationStack.isNotEmpty;

    if (wasSubPage) {
      _navigationStack.removeLast();
      // Note: We keep the old state in _viewIdToPath/etc for a moment
      // to avoid errors during Navigator transition rebuilds.
      // But we remove the GlobalKey to prevent logic conflicts.
      // Actually, it's safer to just let the old page rebuild with its old path
      // until it's actually unmounted.
    }

    final int viewId = _nextViewId++;
    _viewIdToPath[viewId] = path;
    _viewIdToOpenType[viewId] = 'redirectTo';
    _pageKeys[viewId] = GlobalKey<PaminaPageState>();

    setState(() {
      _navigationStack.add(viewId);
      _activePageId = viewId;
    });

    if (wasSubPage) {
      _navigatorKey.currentState?.pushReplacementNamed('/page', arguments: viewId);
    } else {
      _navigatorKey.currentState?.pushNamed('/page', arguments: viewId);
    }

    _handleInvokeCallback('redirectTo', {}, callbackId, fromViewId: fromViewId);

    // 发送路由事件给 Service
    _serviceKey.currentState?.onAppRoute('redirectTo', path, viewId);
  }

  void _handleNavigateBack(String params, String? callbackId, int? fromViewId) {
    if (_navigationStack.isEmpty) return;

    final int delta = json.decode(params)['delta'] ?? 1;
    for (int i = 0; i < delta && _navigationStack.isNotEmpty; i++) {
      _navigationStack.removeLast();
      // We don't remove from _viewIdToPath immediately here to avoid .html errors
      // during the pop transition rebuild.
    }

    // 确定新的活跃页面 ID (栈顶或当前 Tab)
    final int nextActiveId =
        _navigationStack.isNotEmpty
            ? _navigationStack.last
            : (_tabViewIds.isNotEmpty ? _tabViewIds[_currentTabIndex] : 1);

    final String nextPath = _viewIdToPath[nextActiveId] ?? '';

    setState(() {
      _activePageId = nextActiveId;
    });

    _navigatorKey.currentState?.pop();

    _handleInvokeCallback(
      'navigateBack',
      {},
      callbackId,
      fromViewId: fromViewId,
    );

    // 发送路由事件给 Service (通知当前真正活跃的页面)
    _serviceKey.currentState?.onAppRoute('navigateBack', nextPath, nextActiveId);
    _serviceKey.currentState?.onAppRouteDone(
      'navigateBack',
      nextPath,
      nextActiveId,
    );
  }

  void _handleSwitchTab(String params, String? callbackId, int? fromViewId) {
    final Map<String, dynamic> data = json.decode(params);
    String url = data['url']?.toString() ?? '';
    final path = _normalizeUrl(url, fromViewId: fromViewId);

    // 清空堆栈并清理关联状态
    for (final viewId in _navigationStack) {
      _pageKeys.remove(viewId);
      _viewIdToPath.remove(viewId);
      _viewIdToOpenType.remove(viewId);
      _readyViewIds.remove(viewId);
      _pageMessageBuffer.remove(viewId);
    }
    _navigationStack.clear();

    // 查找目标 Tab 索引
    final List list = _tabBarConfig?['list'] ?? [];
    int targetIndex = -1;
    for (int i = 0; i < list.length; i++) {
      if (list[i]['pagePath'] == path) {
        targetIndex = i;
        break;
      }
    }

    if (targetIndex != -1) {
      _onTabSwitch(targetIndex);
    }

    _handleInvokeCallback('switchTab', {}, callbackId, fromViewId: fromViewId);
  }

  void _handleOpenLink(String params, String? callbackId, int? fromViewId) async {
    final Map<String, dynamic> data = json.decode(params);
    final String urlString = data['url']?.toString() ?? '';
    if (urlString.isEmpty) {
      _handleInvokeCallback('openLink', {'errMsg': 'openLink:fail url is empty'}, callbackId, fromViewId: fromViewId);
      return;
    }

    final Uri url = Uri.parse(urlString);
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        _handleInvokeCallback('openLink', {}, callbackId, fromViewId: fromViewId);
      } else {
        _handleInvokeCallback('openLink', {'errMsg': 'openLink:fail cannot launch $urlString'}, callbackId, fromViewId: fromViewId);
      }
    } catch (e) {
      _handleInvokeCallback('openLink', {'errMsg': 'openLink:fail $e'}, callbackId, fromViewId: fromViewId);
    }
  }

  /// 规范化页面路径 (处理相对路径和 app.json 匹配)
  String _normalizeUrl(String url, {int? fromViewId}) {
    // 1. 去掉查询参数和 .html 后缀
    String path = url.split('?').first.replaceAll('.html', '');
    if (path.startsWith('/')) path = path.substring(1);

    // 2. 如果已经在 _allPages 或者是 Tab 路径，直接返回
    if (_allPages.contains(path) || _viewIdToPath.values.contains(path)) {
      return path;
    }

    // 3. 尝试相对路径解析
    String fromPath = '';
    if (fromViewId != null) {
      fromPath = _viewIdToPath[fromViewId] ?? '';
    } else {
      fromPath = _viewIdToPath[_activePageId] ?? '';
    }

    if (fromPath.isNotEmpty) {
      final baseUrl = p.dirname(fromPath);
      final resolved = p.normalize(p.join(baseUrl, path));
      final sanitized =
          resolved.startsWith('/') ? resolved.substring(1) : resolved;
      if (_allPages.contains(sanitized)) return sanitized;
    }

    // 4. 尝试后缀匹配 (兜底方案，例如 pages/view/view 匹配 page/component/pages/view/view)
    for (final p in _allPages) {
      if (p.endsWith(path)) return p;
    }

    return path;
  }

  /// 处理逻辑层就绪事件
  void _handleServiceReady(String params) {
    try {
      final config = json.decode(params);
      if (config is Map<String, dynamic>) {
        setState(() {
          _appConfig = config;
          final root = config['root']?.toString() ?? '';
          _rootPage = root;

          // 解析所有页面列表
          if (config['pages'] is List) {
            _allPages.clear();
            for (var p in config['pages']) {
              _allPages.add(p.toString());
            }
          }

          // 解析 TabBar 配置
          if (config['tabBar'] is Map<String, dynamic>) {
            _tabBarConfig = config['tabBar'];
            final List list = _tabBarConfig!['list'] ?? [];

            // 为每个 Tab 预分配 viewId (1-indexed)
            for (int i = 0; i < list.length; i++) {
              final int viewId = i + 1;
              final String path = list[i]['pagePath'] ?? '';
              _tabViewIds.add(viewId);
              _viewIdToPath[viewId] = path;
              _viewIdToOpenType[viewId] = 'appLaunch'; // 初始都是 launch
              _pageKeys[viewId] = GlobalKey<PaminaPageState>();

              if (path == root) {
                _currentTabIndex = i;
                _activePageId = viewId;
                _initializedTabViewIds.add(viewId);
              }
            }
            _nextViewId = _tabViewIds.length + 1;
          }


          // 如果没有 TabBar，或者首页不在 TabBar 里（理论上不该发生）
          if (_tabViewIds.isEmpty) {
            _activePageId = 1;
            _viewIdToPath[1] = root;
            _viewIdToOpenType[1] = 'appLaunch';
            _pageKeys[1] = GlobalKey<PaminaPageState>();
            _initializedTabViewIds.add(1);
            _nextViewId = 2;
          }

          _isServiceReady = true;
          // 尝试触发首屏跳转
          _tryTriggerAppLaunch(_activePageId);
        });

        PaminaLog.i(
          'App Configuration loaded. Root: $_rootPage, Tabs: ${_tabViewIds.length}',
          tag: 'PaminaApp',
        );

        // 尝试触发首屏跳转 (逻辑层变动可能比视图层慢，也可能快)
        _tryTriggerAppLaunch(_activePageId);
      }
    } catch (e) {
      PaminaLog.e('Parse serviceReady params error', error: e, tag: 'PaminaApp');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        if (_navigationStack.isNotEmpty) {
          _handleNavigateBack('{"delta":1}', null, null);
        } else {
          Navigator.pop(context);
        }
      },
      child: Material(
        color: const Color(0xFFF7F7F7),
        child: Stack(
          children: [
            // 1. 逻辑层 (后台运行)
            if (_sourcePath != null)
              Offstage(
                offstage: true,
                child: PaminaService(
                  key: _serviceKey,
                  appId: widget.appId,
                  sourcePath: _sourcePath!,
                  onPublish: _handleServicePublish,
                  onInvoke: (event, params, callbackId) =>
                      _handleInvoke(event, params, callbackId),
                ),
              ),

            Column(
              children: [
                if (_tabBarConfig != null &&
                    _tabBarConfig!['position'] == 'top')
                  _buildTopTabBar(),
                Expanded(
                  child: _appConfig == null || _sourcePath == null
                      ? const SizedBox.shrink()
                      : Navigator(
                          key: _navigatorKey,
                          initialRoute: '/',
                          onGenerateRoute: (settings) {
                            if (settings.name == '/') {
                              return PageRouteBuilder(
                                pageBuilder: (context, anim1, anim2) =>
                                    _buildTabStack(),
                                settings: settings,
                              );
                            }

                            final int? viewId = settings.arguments as int?;
                            if (viewId == null) return null;

                            return CupertinoPageRoute(
                              builder: (context) => _buildSubPage(viewId),
                              settings: settings,
                            );
                          },
                        ),
                ),
              ],
            ),

            if (_syncError)
              const Center(
                child: Text('小程序加载失败', style: TextStyle(color: Colors.red)),
              )
            else if (_isSyncing || _appConfig == null)
              PaminaSplashScreen(
                appName: widget.appId == 'demoapp' ? 'Pamina 示例' : widget.appId,
              ),

            // TabBar 现在是全局悬浮在底部的
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
                child: _buildTabBar() ?? const SizedBox.shrink(),
            ),

            // 全局弹窗
            Positioned.fill(
              child: PaminaToast(
                visible: _toastConfig['visible'] ?? false,
                title: _toastConfig['title'] ?? '',
                icon: _toastConfig['icon'] ?? 'none',
                mask: _toastConfig['mask'] ?? false,
              ),
            ),

            // 全局胶囊按钮 (WeChat Style)
            Positioned(
              right: 16,
              top: MediaQuery.of(context).padding.top + 8,
              child: PaminaCapsule(
                onClose: () => Navigator.pop(context),
                onMenu: () {
                   PaminaLog.i('Global menu clicked', tag: 'PaminaApp');
                   // TODO: Implement global menu (e.g., share, about, etc.)
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabStack() {
    return IndexedStack(
      index: _currentTabIndex,
      children: (_tabViewIds.isNotEmpty ? _tabViewIds : [1]).map((id) {
        if (!_initializedTabViewIds.contains(id)) {
          return const SizedBox.shrink();
        }
        final path = _viewIdToPath[id] ?? '';
        final config = _getPageConfig(path);
        return PaminaPage(
          key: _pageKeys[id],
          appId: widget.appId,
          viewId: id,
          path: path,
          sourcePath: _sourcePath!,
          onPublish: _handlePagePublish,
          onInvoke: (event, params, callbackId) =>
              _handleInvoke(event, params, callbackId, fromViewId: id),
          onReady: () => _onPageReady(id),
          onClose: () => Navigator.pop(context),
          onDispose: () => _onPageDispose(id),
          initialTitle: config['title'],
          initialBgColor: config['backgroundColor'],
          initialTextColor: config['textColor'],
          showBack: false,
          enablePullDownRefresh: config['enablePullDownRefresh'] == 'true',
        );
      }).toList(),
    );
  }

  Widget _buildSubPage(int viewId) {
    final path = _viewIdToPath[viewId];
    if (path == null || path.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final config = _getPageConfig(path);
    return PaminaPage(
      key: _pageKeys[viewId],
      appId: widget.appId,
      viewId: viewId,
      path: path,
      sourcePath: _sourcePath!,
      onPublish: _handlePagePublish,
      onInvoke: (event, params, callbackId) =>
          _handleInvoke(event, params, callbackId, fromViewId: viewId),
      onReady: () => _onPageReady(viewId),
      onClose: () => Navigator.pop(context),
      onDispose: () => _onPageDispose(viewId),
      initialTitle: config['title'],
      initialBgColor: config['backgroundColor'],
      initialTextColor: config['textColor'],
      showBack: true,
      enablePullDownRefresh: config['enablePullDownRefresh'] == 'true',
      onBack: () => _handleNavigateBack('{"delta":1}', null, null),
    );
  }

  void _onTabSwitch(int index) {
    if (index == _currentTabIndex) return;
    final List list = _tabBarConfig?['list'] ?? [];
    if (index >= list.length) return;

    final tab = list[index];
    final String? pagePath = tab['pagePath'];
    if (pagePath != null) {
      final int nextViewId = index + 1;

      setState(() {
        _currentTabIndex = index;
        _activePageId = nextViewId;
        _viewIdToOpenType[nextViewId] = 'switchTab';
        _initializedTabViewIds.add(nextViewId);

        _serviceKey.currentState?.onAppRoute('switchTab', pagePath, nextViewId);
        if (_readyViewIds.contains(nextViewId)) {
          _serviceKey.currentState
              ?.onAppRouteDone('switchTab', pagePath, nextViewId);
        }
      });
    }
  }

  Widget? _buildTabBar() {
    // 如果当前有非 Tab 页面在栈顶，隐藏底栏
    if (_navigationStack.isNotEmpty) return null;

    if (_tabBarConfig == null) return null;
    final String position = _tabBarConfig!['position']?.toString() ?? 'bottom';
    if (position == 'top') return null;
    return _buildBottomTabBar();
  }

  Widget _buildTopTabBar() {
    final List list = _tabBarConfig!['list'] ?? [];
    final colorHex = _tabBarConfig!['color']?.toString() ?? '#7A7E83';
    final selectedColorHex =
        _tabBarConfig!['selectedColor']?.toString() ?? '#3cc51f';
    final backgroundColorHex =
        _tabBarConfig!['backgroundColor']?.toString() ?? '#ffffff';

    Color parseColor(String hex) {
      hex = hex.replaceAll('#', '');
      if (hex.length == 6) hex = 'FF$hex';
      return Color(int.parse(hex, radix: 16));
    }

    final Color bgColor = parseColor(backgroundColorHex);
    final Color textColor = parseColor(colorHex);
    final Color selectedColor = parseColor(selectedColorHex);

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          bottom: BorderSide(color: Colors.grey.withAlpha(51), width: 0.5),
        ),
      ),
      child: Row(
        children:
            list.asMap().entries.map((entry) {
              final int idx = entry.key;
              final item = entry.value;
              final bool isSelected = idx == _currentTabIndex;

              return Expanded(
                child: InkWell(
                  onTap: () => _onTabSwitch(idx),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom:
                            isSelected
                                ? BorderSide(color: selectedColor, width: 2)
                                : BorderSide.none,
                      ),
                    ),
                    child: Text(
                      item['text'] ?? '',
                      style: TextStyle(
                        color: isSelected ? selectedColor : textColor,
                        fontSize: 14,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }

  Widget _buildBottomTabBar() {
    final List list = _tabBarConfig!['list'] ?? [];
    if (list.isEmpty) return const SizedBox.shrink();

    final colorHex = _tabBarConfig!['color']?.toString() ?? '#7A7E83';
    final selectedColorHex =
        _tabBarConfig!['selectedColor']?.toString() ?? '#3cc51f';

    Color parseColor(String hex) {
      hex = hex.replaceAll('#', '');
      if (hex.length == 6) hex = 'FF$hex';
      return Color(int.parse(hex, radix: 16));
    }

    return BottomNavigationBar(
      currentIndex: _currentTabIndex,
      selectedItemColor: parseColor(selectedColorHex),
      unselectedItemColor: parseColor(colorHex),
      backgroundColor: parseColor(
        _tabBarConfig!['backgroundColor']?.toString() ?? '#ffffff',
      ),
      type: BottomNavigationBarType.fixed,
      onTap: _onTabSwitch,
      items:
          list.map<BottomNavigationBarItem>((item) {
            final String iconPath = item['iconPath'] ?? '';
            final String selectedIconPath = item['selectedIconPath'] ?? '';
            final String text = item['text'] ?? '';

            Widget buildIcon(String path, bool isSelected) {
              if (path.isEmpty || _sourcePath == null) {
                return const Icon(Icons.circle, size: 24);
              }
              final file = File(p.join(_sourcePath!, path));
              if (file.existsSync()) {
                return Image.file(
                  file,
                  width: 24,
                  height: 24,
                  fit: BoxFit.contain,
                  color: isSelected ? parseColor(selectedColorHex) : null,
                );
              }
              return const Icon(Icons.error_outline, size: 24);
            }

            return BottomNavigationBarItem(
              icon: buildIcon(iconPath, false),
              activeIcon: buildIcon(selectedIconPath, true),
              label: text,
            );
          }).toList(),
    );
  }
}
