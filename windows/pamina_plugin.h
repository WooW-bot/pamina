#ifndef FLUTTER_PLUGIN_PAMINA_PLUGIN_H_
#define FLUTTER_PLUGIN_PAMINA_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace pamina {

class PaminaPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  PaminaPlugin();

  virtual ~PaminaPlugin();

  // Disallow copy and assign.
  PaminaPlugin(const PaminaPlugin&) = delete;
  PaminaPlugin& operator=(const PaminaPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace pamina

#endif  // FLUTTER_PLUGIN_PAMINA_PLUGIN_H_
