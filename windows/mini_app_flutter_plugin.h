#ifndef FLUTTER_PLUGIN_MINI_APP_FLUTTER_PLUGIN_H_
#define FLUTTER_PLUGIN_MINI_APP_FLUTTER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace mini_app_flutter {

class MiniAppFlutterPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  MiniAppFlutterPlugin();

  virtual ~MiniAppFlutterPlugin();

  // Disallow copy and assign.
  MiniAppFlutterPlugin(const MiniAppFlutterPlugin&) = delete;
  MiniAppFlutterPlugin& operator=(const MiniAppFlutterPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace mini_app_flutter

#endif  // FLUTTER_PLUGIN_MINI_APP_FLUTTER_PLUGIN_H_
