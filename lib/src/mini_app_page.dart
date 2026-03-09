import 'dart:convert';
import 'package:flutter/material.dart';
import 'sync/mini_app_manager.dart';
import 'utils/storage_util.dart';
import 'mini_app_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'mini_app_page_view.dart';
import 'utils/mini_app_log.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

/// 小程序页面容器
///
/// @author Parker
class MiniAppPage extends StatefulWidget {
  final String appId;
  final String appPath;
  final String userId;

  const MiniAppPage({
    super.key,
    required this.appId,
    required this.appPath,
    required this.userId,
  });

  @override
  State<MiniAppPage> createState() => _MiniAppPageState();
}

class _MiniAppPageState extends State<MiniAppPage> {
  final GlobalKey<MiniAppServiceState> _serviceKey = GlobalKey();
  final Map<int, GlobalKey<MiniAppPageViewState>> _pageKeys = {};

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

  /// 导航栏状态
  String _navBarTitle = '';
  String _navBarBgColor = '#F7F7F7';
  String _navBarTextColor = 'black'; // black or white

  @override
  void initState() {
    super.initState();
    _syncMiniApp();
  }

  Future<void> _syncMiniApp() async {
    final result = await MiniAppManager.syncMiniApp(
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
        MiniAppLog.d(
          'MiniAppPage: Buffering message for uninitialized view $id (event: $event)',
          tag: 'Page',
        );
        _pageMessageBuffer.putIfAbsent(id, () => []).add({
          'event': event,
          'params': p,
        });
      }
    }
  }

  /// 当 MiniAppPageView 的 initState 执行时回调
  void _onPageReady(int viewId) {
    // 异步执行，确保 currentState 在下一帧可用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _drainPageMessageBuffer(viewId);
    });
  }

  /// 消耗并发送缓冲区中的消息
  void _drainPageMessageBuffer(int viewId) {
    final buffer = _pageMessageBuffer.remove(viewId);
    if (buffer == null || buffer.isEmpty) return;

    final pageState = _pageKeys[viewId]?.currentState;
    if (pageState != null) {
      MiniAppLog.i(
        'MiniAppPage: Draining ${buffer.length} buffered messages for view $viewId',
        tag: 'Page',
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

  /// 根据页面路径应用特定配置 (如标题、颜色)
  void _applyPageConfig(String path) {
    if (_appConfig == null) return;
    final window = _appConfig!['window'] as Map<String, dynamic>?;
    if (window == null) return;

    // 1. 默认值 (全局 window 配置)
    String title = window['navigationBarTitleText']?.toString() ?? '';
    String bgColor =
        window['navigationBarBackgroundColor']?.toString() ?? '#F7F7F7';
    String textColor = window['navigationBarTextStyle']?.toString() ?? 'black';

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
    }

    MiniAppLog.i('Applying config for page $path: title=$title', tag: 'Page');
    setState(() {
      _navBarTitle = title;
      _navBarBgColor = bgColor;
      _navBarTextColor = textColor;
    });
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
      MiniAppLog.i('Triggering $viewId appLaunch (path: $path)', tag: 'Page');

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
    MiniAppLog.i('API Invoke: $event (callbackId: $callbackId)', tag: 'Page');

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
        setState(() => _navBarTitle = title);
        _handleInvokeCallback(event, {}, callbackId, fromViewId: fromViewId);
        break;
      case 'setNavigationBarColor':
        final p = json.decode(params);
        final bgColor = p['backgroundColor']?.toString();
        final textColor = p['frontColor']?.toString(); // 通常是 #ffffff 或 #000000
        setState(() {
          if (bgColor != null) _navBarBgColor = bgColor;
          if (textColor != null) {
            _navBarTextColor = textColor.contains('ffffff') ? 'white' : 'black';
          }
        });
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
      default:
        MiniAppLog.w('Unhandled API: $event', tag: 'Page');
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

  void _handleGetSystemInfo(String? callbackId, int? fromViewId) {
    final media = MediaQuery.of(context);
    final data = {
      'model': 'MiniApp Virtual Device',
      'pixelRatio': media.devicePixelRatio,
      'windowWidth': media.size.width,
      'windowHeight': media.size.height,
      'screenWidth': media.size.width,
      'screenHeight': media.size.height,
      'language': 'zh_CN',
      'version': '1.0.0',
      'system': 'MiniAppOS 1.0',
      'platform':
          Theme.of(context).platform == TargetPlatform.iOS ? 'ios' : 'android',
      'fontSizeSetting': 16,
      'SDKVersion': '1.0.0',
    };
    _handleInvokeCallback(
      'getSystemInfo',
      data,
      callbackId,
      fromViewId: fromViewId,
    );
  }

  void _handleNavigateTo(String params, String? callbackId, int? fromViewId) {
    final Map<String, dynamic> data = json.decode(params);
    String url = data['url']?.toString() ?? '';
    final path = _normalizeUrl(url, fromViewId: fromViewId);

    final int viewId = _nextViewId++;
    _viewIdToPath[viewId] = path;
    _viewIdToOpenType[viewId] = 'navigateTo';
    _pageKeys[viewId] = GlobalKey<MiniAppPageViewState>();

    _applyPageConfig(path);

    setState(() {
      _navigationStack.add(viewId);
      _activePageId = viewId;
    });

    _handleInvokeCallback('navigateTo', {}, callbackId, fromViewId: fromViewId);

    // 发送路由事件给 Service (使用原始 path 以支持框架内部解析)
    _serviceKey.currentState?.onAppRoute('navigateTo', path, viewId);
  }

  void _handleRedirectTo(String params, String? callbackId, int? fromViewId) {
    final Map<String, dynamic> data = json.decode(params);
    String url = data['url']?.toString() ?? '';
    final path = _normalizeUrl(url, fromViewId: fromViewId);

    if (_navigationStack.isNotEmpty) {
      final int oldViewId = _navigationStack.removeLast();
      _pageKeys.remove(oldViewId);
      _viewIdToPath.remove(oldViewId);
      _viewIdToOpenType.remove(oldViewId);
      _readyViewIds.remove(oldViewId);
      _pageMessageBuffer.remove(oldViewId);
    }

    final int viewId = _nextViewId++;
    _viewIdToPath[viewId] = path;
    _viewIdToOpenType[viewId] = 'redirectTo';
    _pageKeys[viewId] = GlobalKey<MiniAppPageViewState>();

    _applyPageConfig(path);

    setState(() {
      _navigationStack.add(viewId);
      _activePageId = viewId;
    });

    _handleInvokeCallback('redirectTo', {}, callbackId, fromViewId: fromViewId);

    // 发送路由事件给 Service
    _serviceKey.currentState?.onAppRoute('redirectTo', path, viewId);
  }

  void _handleNavigateBack(String params, String? callbackId, int? fromViewId) {
    if (_navigationStack.isEmpty) return;

    final int delta = json.decode(params)['delta'] ?? 1;
    for (int i = 0; i < delta && _navigationStack.isNotEmpty; i++) {
      final int viewId = _navigationStack.removeLast();
      _pageKeys.remove(viewId);
      _viewIdToPath.remove(viewId);
      _viewIdToOpenType.remove(viewId);
      _readyViewIds.remove(viewId);
      _pageMessageBuffer.remove(viewId);
    }

    // 确定新的活跃页面 ID (栈顶或当前 Tab)
    final int nextActiveId =
        _navigationStack.isNotEmpty
            ? _navigationStack.last
            : (_tabViewIds.isNotEmpty ? _tabViewIds[_currentTabIndex] : 1);

    final String nextPath = _viewIdToPath[nextActiveId] ?? '';
    _applyPageConfig(nextPath);

    setState(() {
      _activePageId = nextActiveId;
    });

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
              _pageKeys[viewId] = GlobalKey<MiniAppPageViewState>();

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
            _pageKeys[1] = GlobalKey<MiniAppPageViewState>();
            _initializedTabViewIds.add(1);
            _nextViewId = 2;
          }

          _isServiceReady = true;
          // 初始化导航栏 (根据首页路径查找配置)
          _applyPageConfig(root);
        });

        MiniAppLog.i(
          'App Configuration loaded. Root: $_rootPage, Tabs: ${_tabViewIds.length}',
          tag: 'Page',
        );

        // 尝试触发首屏跳转 (逻辑层变动可能比视图层慢，也可能快)
        _tryTriggerAppLaunch(_activePageId);
      }
    } catch (e) {
      MiniAppLog.e('Parse serviceReady params error', error: e, tag: 'Page');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: MiniAppCapsuleAppBar(
        title: _navBarTitle,
        backgroundColor: _navBarBgColor,
        textColor: _navBarTextColor,
        showBack: _navigationStack.isNotEmpty,
        onBack: () => _handleNavigateBack('{"delta":1}', null, null),
        onClose: () => Navigator.pop(context),
      ),
      body: SafeArea(
        top: false, // AppBar already handles top safe area usually
        child: Stack(
          children: [
            // 1. 逻辑层 (后台运行) - 使用 Offstage 彻底避免其参与 UI 渲染或干扰手势拦截
            if (_sourcePath != null)
              Offstage(
                offstage: true,
                child: MiniAppService(
                  key: _serviceKey,
                  appId: widget.appId,
                  sourcePath: _sourcePath!,
                  onPublish: _handleServicePublish,
                  onInvoke:
                      (event, params, callbackId) =>
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
                      : Stack(
                          children: [
                            // 2.1 Tab 页面 (IndexedStack)
                            Positioned.fill(
                              child: IndexedStack(
                                index: _currentTabIndex,
                                children:
                                    (_tabViewIds.isNotEmpty ? _tabViewIds : [1])
                                        .map((id) {
                                if (!_initializedTabViewIds.contains(id)) {
                                  return const SizedBox.shrink();
                                }
                                return MiniAppPageView(
                                  key: _pageKeys[id],
                                  appId: widget.appId,
                                  viewId: id,
                                  path: _viewIdToPath[id] ?? '',
                                  sourcePath: _sourcePath!,
                                  onPublish: _handlePagePublish,
                                  onInvoke: (event, params, callbackId) =>
                                      _handleInvoke(event, params, callbackId,
                                          fromViewId: id),
                                  onReady: () => _onPageReady(id),
                                );
                              }).toList(),
                              ),
                            ),
 // 2.2 非 Tab 页面栈 (覆盖在 IndexedStack 之上)
                            ..._navigationStack.map((id) {
                              return Positioned.fill(
                                child: MiniAppPageView(
                                  key: _pageKeys[id],
                                  appId: widget.appId,
                                  viewId: id,
                                  path: _viewIdToPath[id] ?? '',
                                  sourcePath: _sourcePath!,
                                  onPublish: _handlePagePublish,
                                  onInvoke: (event, params, callbackId) =>
                                      _handleInvoke(event, params, callbackId,
                                          fromViewId: id),
                                  onReady: () => _onPageReady(id),
                                ),
                              );
                            }),
                          ],
                        ),
                ),
              ],
            ),

            // 3. 状态盖层 (Loading/Error/SplashScreen)
            if (_syncError)
              const Center(
                child: Text('小程序加载失败', style: TextStyle(color: Colors.red)),
              )
            else if (_isSyncing || _appConfig == null)
              MiniAppSplashScreen(
                appName: widget.appId == 'demoapp' ? '小程序示例' : widget.appId,
              ),
          ],
        ),
      ),
      bottomNavigationBar: _buildTabBar(),
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

      // 应用页面特定配置
      _applyPageConfig(pagePath);

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

class MiniAppSplashScreen extends StatelessWidget {
  final Widget? appIcon;
  final String appName;

  const MiniAppSplashScreen({super.key, this.appIcon, required this.appName});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: Column(
        children: [
          const Spacer(flex: 1),
          // Reduced top whitespace (moving content UP)
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 60,
                height: 60,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.green.shade400,
                  ),
                  backgroundColor: Colors.grey.shade100,
                ),
              ),
              appIcon ??
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: Color(0xFF333333),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.all_inclusive,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            appName,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const Spacer(flex: 2),
          // Bottom white space (significantly more than top)
        ],
      ),
    );
  }
}

class MiniAppCapsuleAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final String title;
  final String backgroundColor;
  final String textColor;
  final bool showBack;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  const MiniAppCapsuleAppBar({
    super.key,
    this.title = '',
    this.backgroundColor = '#F7F7F7',
    this.textColor = 'black',
    this.showBack = false,
    this.onBack,
    this.onClose,
  });

  Color _parseColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final Color bgColor = _parseColor(backgroundColor);
    final Color contentColor =
        textColor == 'white' ? Colors.white : Colors.black;

    return AppBar(
      backgroundColor: bgColor,
      elevation: 0,
      toolbarHeight: 56,
      automaticallyImplyLeading: false,
      leading: showBack
          ? IconButton(
              icon: Icon(Icons.arrow_back_ios_new, color: contentColor, size: 20),
              onPressed: onBack,
            )
          : null,
      centerTitle: true,
      title: Text(
        title,
        style: TextStyle(
          color: contentColor,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.black12, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 14),
              Row(
                children: List.generate(
                  3,
                  (index) => Container(
                    width: index == 1 ? 6 : 4,
                    height: index == 1 ? 6 : 4,
                    margin: EdgeInsets.only(right: index == 2 ? 0 : 3),
                    decoration: BoxDecoration(
                      color: contentColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 0.5,
                height: 16,
                color: contentColor.withAlpha(51),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: onClose ?? () => Navigator.pop(context),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        border: Border.all(color: contentColor, width: 2),
                        shape: BoxShape.circle,
                        color: Colors.transparent,
                      ),
                    ),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: contentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(56);
}
