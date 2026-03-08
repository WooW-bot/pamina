# mini_app_flutter

基于 Flutter 的小程序容器引擎，适配 Hera 框架协议。

## 特性

- **跨平台支持**：使用 Flutter 构建，原生支持 Android 和 iOS。
- **多 Tab 架构**：支持小程序底栏（TabBar）和顶栏架构，支持多 WebView 并行渲染及懒加载。
- **高性能同步**：内置资产同步与解压系统，支持离线包加载与动态更新。
- **双重缓存消息路由**：独特的两级缓冲区设计，彻底解决多标签页初始化时的消息竞争（Race Condition）问题，确保后台 Tab 启动即有数据。
- **动态导航栏**：深度适配小程序 `window` 配置，支持 `setNavigationBarTitle`、`setNavigationBarColor` 等动态 API。
- **iOS 兼容桥接**：内置 JSBridge 模拟层，无需修改小程序源码即可在 Android 上完美运行 iOS 逻辑。

## 核心组件

- **MiniAppPage**: 主容器页面，负责全局配置解析、多页面调度（IndexedStack）及 TabBar 渲染。
- **MiniAppPageView**: 视图层容器，基于 `webview_flutter` 实现，负责单个小程序的 HTML/CSS/JS 渲染及视图层事件转发。
- **MiniAppService**: 逻辑层容器，负责在后台运行小程序的 `service.js` 逻辑，处理核心业务与数据流。
- **MiniAppManager**: 生命周期管理中心，处理离线包同步、解压及资源路径映射。

## 快速开始

### 1. 注册小程序

```dart
final miniApp = MiniApp(
  appId: "demoapp",
  appPath: "assets/demoapp.zip", // 小程序离线包路径
);
```

### 2. 启动页面

```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => MiniAppPage(
      appId: miniApp.appId,
      appPath: miniApp.appPath,
    ),
  ),
);
```

## 技术细节

- **通信机制**：基于 `subscribeHandler` 和 `publishHandler` 的标准 Hera/小程序通信协议。
- **自适应 UI**：导航栏胶囊按钮（Capsule）自动根据背景深浅调整色调（黑/白）。
- **资源加载**：统一采用 `file://` 协议加载本地解压后的资源，确保存储访问效率。

## 开发作者

Parker
