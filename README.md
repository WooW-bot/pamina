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

当前容器基于 Hera 协议实现，深度兼容微信小程序官方协议。以下是详细的 API 支持清单（参考微信官方文档 v2.0+）：

### 1. 基础 (Base)
<details>
<summary>查看详情</summary>

| API | 状态 | 说明 |
| :--- | :--- | :--- |
| `wx.canIUse` | 🟢 | |
| `wx.base64ToArrayBuffer` | 🟢 | |
| `wx.arrayBufferToBase64` | 🟢 | |
| `wx.getSystemInfo` / `Sync` | 🟢 | 适配屏幕/品牌/SDK级别等 |
| `wx.getWindowInfo` | 🟡 | 部分字段通过 SystemInfo 映射 |
| `wx.getDeviceInfo` | 🟡 | |
| `wx.getAppBaseInfo` | 🟡 | |
| `wx.getUpdateManager` | 🔴 | |
| `wx.getLaunchOptionsSync` | 🟢 | |
| `wx.onAppShow` / `onAppHide` | 🟢 | |
| `wx.onError` | 🟢 | |
| `wx.onThemeChange` | 🔴 | |
</details>

### 2. 路由 (Route)
<details>
<summary>查看详情</summary>

| API | 状态 | 说明 |
| :--- | :--- | :--- |
| `wx.switchTab` | 🟢 | 支持多 Tab 状态保持 |
| `wx.reLaunch` | � | |
| `wx.redirectTo` | 🟢 | |
| `wx.navigateTo` | 🟢 | 支持 10 层页面栈 |
| `wx.navigateBack` | � | |
</details>

### 3. 界面 (UI)
<details>
<summary>查看详情</summary>

| 类别 | API | 状态 | 说明 |
| :--- | :--- | :---: | :--- |
| **交互** | `wx.showToast` / `hideToast` | 🟢 | 仿微信样式 |
| | `wx.showLoading` / `hideLoading` | 🟢 | |
| | `wx.showModal` | 🟢 | 支持多种交互模式 |
| | `wx.showActionSheet` | 🟢 | |
| **导航栏** | `wx.setNavigationBarTitle` | 🟢 | |
| | `wx.setNavigationBarColor` | 🟢 | |
| | `wx.showNavigationBarLoading` | 🟢 | |
| | `wx.hideNavigationBarLoading` | 🟢 | |
| **Tab Bar** | `wx.setTabBarItem` | 🔴 | |
| | `wx.setTabBarStyle` | 🔴 | |
| | `wx.showTabBar` / `hideTabBar` | 🔴 | |
| | `wx.setTabBarBadge` | 🔴 | |
| **刷新/滚动** | `wx.startPullDownRefresh` | � | |
| | `wx.stopPullDownRefresh` | 🟢 | |
| | `wx.pageScrollTo` | 🟡 | 依赖 WebView 表现 |
| **动画** | `wx.createAnimation` | � | 支持核心动画属性 |
</details>

### 4. 网络 (Network)
<details>
<summary>查看详情</summary>

| API | 状态 | 说明 |
| :--- | :--- | :--- |
| `wx.request` | 🟢 | 支持 HTTPS, Cookie 隔离 |
| `wx.downloadFile` | 🟢 | |
| `wx.uploadFile` | 🟢 | 支持 Form 表单上传 |
| `wx.connectSocket` | 🔴 | |
| `mDNS` | 🔴 | |
| `TCP/UDP` | 🔴 | |
</details>

### 5. 媒体 (Media)
<details>
<summary>查看详情</summary>

| 类别 | API | 状态 | 说明 |
| :--- | :--- | :---: | :--- |
| **图片** | `wx.chooseImage` | 🟢 | 支持 相册/拍摄 |
| | `wx.previewImage` | 🔴 | |
| | `wx.getImageInfo` | 🟢 | |
| | `wx.saveImageToPhotosAlbum` | 🟡 | 需权限申请 |
| **音视频** | `wx.startRecord` / `stopRecord` | � | |
| | `wx.createInnerAudioContext` | 🟡 | 基础播放支持 |
| | `wx.createVideoContext` | 🟡 | |
| **相机/直播** | `wx.createCameraContext` | 🔴 | |
| | `wx.createLivePusherContext` | 🔴 | |
| **地图** | `wx.createMapContext` | 🔴 | |
</details>

### 6. 数据缓存 (Storage)
<details>
<summary>查看详情</summary>

| API | 状态 | 说明 |
| :--- | :--- | :--- |
| `wx.setStorage` / `setStorageSync` | � | |
| `wx.getStorage` / `getStorageSync` | � | |
| `wx.removeStorage` / `removeStorageSync` | � | |
| `wx.clearStorage` / `clearStorageSync` | 🟢 | |
| `wx.getStorageInfo` / `Sync` | � | |
</details>

### 7. 位置 (Location)
<details>
<summary>查看详情</summary>

| API | 状态 | 说明 |
| :--- | :--- | :--- |
| `wx.getLocation` | � | |
| `wx.chooseLocation` | � | |
| `wx.openLocation` | � | |
</details>

### 8. 设备 (Device)
<details>
<summary>查看详情</summary>

| 类别 | API | 状态 | 说明 |
| :--- | :--- | :---: | :--- |
| **系统** | `wx.getNetworkType` | 🟢 | |
| | `wx.onNetworkStatusChange` | 🟢 | |
| **硬件** | `wx.makePhoneCall` | 🟢 | |
| | `wx.scanCode` | 🟢 | 支持 QR/条码 |
| | `wx.vibrateShort` / `vibrateLong` | � | |
| **剪贴板** | `wx.setClipboardData` | 🟡 | |
| | `wx.getClipboardData` | � | |
| **屏幕** | `wx.setScreenBrightness` | 🔴 | |
| | `wx.setKeepScreenOn` | 🔴 | |
| **传感器** | `加速度/罗盘/陀螺仪` | 🔴 | |
</details>

### 9. 开放接口 (Open API)
<details>
<summary>查看详情</summary>

| API | 状态 | 说明 |
| :--- | :--- | :--- |
| `wx.login` | 🔴 | 需 Mock 环境 |
| `wx.checkSession` | 🔴 | |
| `wx.getUserInfo` | 🔴 | |
| `wx.requestPayment` | 🔴 | |
| `wx.authorize` | 🔴 | |
| `wx.openSetting` | 🔴 | |
| `wx.getSetting` | 🔴 | |
| `wx.shareToWeRun` | 🔴 | |
</details>

### 10. 文件 (File)
<details>
<summary>查看详情</summary>

| API | 状态 | 说明 |
| :--- | :--- | :--- |
| `wx.saveFile` | � | |
| `wx.getSavedFileList` | 🟢 | |
| `wx.removeSavedFile` | � | |
| `wx.getFileInfo` | 🟢 | |
| `wx.getFileSystemManager` | � | 部分标准 IO 支持 |
</details>

### 11. 其他能力
- **Canvas**: 🟢 支持标准 Canvas 2D
- **AI**: 🔴 暂无集成计划
- **Worker**: 🔴
- **WXML (SelectorQuery)**: 🟢 深度支持

---

## 开发作者

Parker
