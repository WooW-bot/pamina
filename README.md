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

## 架构与支持情况

当前容器基于 Hera 协议实现，深度兼容微信小程序官方协议。以下是按官方示例分类的详细支持清单：

### 1. 核心能力 (Core Capability)

| 分类 | 状态 | 说明 |
| :--- | :--- | :--- |
| **基础组件 (Components)** | 🟢 深度支持 | WXML 标准组件适配 |
| **交互动画 (Animation)** | 🟡 部分支持 | 支持 CSS3 & Web Animation API |
| **API 接口 (Interfaces)** | 🟢 深度支持 | 适配 40+ 核心业务接口 |
| **云开发 (Cloud)** | 🔴 不支持 | 暂无集成计划 |
| **广告 (Ads)** | 🔴 不支持 | 容器层不提供原生插件 |

---

### 2. 组件支持详情 (Components)

| 类别 | 组件 (Item) | 状态 | 备注 |
| :--- | :--- | :---: | :--- |
| **视图容器** | `view`, `scroll-view`, `swiper`, `movable-view`, `cover-view` | 🟢 | 基于 WebView 标准实现 |
| **基础内容** | `icon`, `text`, `progress`, `rich-text` | 🟢 | |
| **表单组件** | `button`, `checkbox`, `form`, `input`, `picker`, `radio`, `slider`, `switch`, `textarea` | 🟢 | 支持原生样式适配 |
| **导航** | `navigator` | 🟢 | |
| **媒体组件** | `image` | 🟢 | 支持 WebP/缩放模式 |
| | `video`, `audio`, `camera` | 🟡 | 依赖 WebView 表现，暂无原生增强 |
| **地图** | `map` | 🔴 | 暂未集成第三方地图 SDK |
| **画布** | `canvas` | 🟢 | 支持标准 Canvas 2D |
| **开放能力** | `web-view` | 🟢 | 支持业务域名配置 |

---

### 3. API 接口支持详情 (Interfaces)

<details>
<summary>点击展开：网络 (Network)</summary>

| API | 状态 | 备注 |
| :--- | :--- | :--- |
| `request` | 🟢 | 支持 HTTPS, Cookie 隔离 |
| `uploadFile` | 🟢 | 支持多文件字段 |
| `downloadFile` | 🟢 | 支持断点续传 |
| `connectSocket` | 🔴 | 规划中 |
</details>

<details>
<summary>点击展开：媒体 (Media)</summary>

| API | 状态 | 备注 |
| :--- | :--- | :--- |
| `chooseImage` | 🟢 | 支持 相册/相机 |
| `previewImage` | 🟢 | |
| `getImageInfo` | 🟢 | |
| `saveImageToPhotosAlbum` | 🟡 | 需权限申请 |
| `saveFile` | 🟢 | 持久化至沙箱 |
| `getSavedFileList` | 🟢 | |
| `removeSavedFile` | 🟢 | |
</details>

<details>
<summary>点击展开：存储 (Storage)</summary>

| API | 状态 | 备注 |
| :--- | :--- | :--- |
| `setStorage` / `setStorageSync` | 🟢 | |
| `getStorage` / `getStorageSync` | 🟢 | |
| `removeStorage` / `removeStorageSync` | 🟢 | |
| `clearStorage` / `clearStorageSync` | 🟢 | |
| `getStorageInfo` / `getStorageInfoSync` | 🟢 | |
</details>

<details>
<summary>点击展开：设备 (Device)</summary>

| API | 状态 | 备注 |
| :--- | :--- | :--- |
| `getSystemInfo` / `Sync` | 🟢 | 适配 屏幕/品牌/版本 |
| `getNetworkType` | 🟢 | |
| `onNetworkStatusChange` | 🟢 | |
| `makePhoneCall` | 🟢 | |
| `scanCode` | 🟢 | 支持 条码/二维码 |
| `setClipboardData` | 🟡 | 适配中 |
</details>

<details>
<summary>点击展开：界面 (UI)</summary>

| API | 状态 | 备注 |
| :--- | :--- | :--- |
| `showToast` / `hideToast` | 🟢 | |
| `showLoading` / `hideLoading` | 🟢 | |
| `showModal` | 🟢 | |
| `showActionSheet` | 🟢 | |
| `setNavigationBarTitle` | 🟢 | |
| `setNavigationBarColor` | 🟢 | |
| `navigateTo` / `redirectTo` | 🟢 | 层级限制 10 层 |
| `switchTab` / `reLaunch` | 🟢 | |
| `startPullDownRefresh` | 🟢 | |
| `stopPullDownRefresh` | 🟢 | |
</details>

## 开发作者

Parker
