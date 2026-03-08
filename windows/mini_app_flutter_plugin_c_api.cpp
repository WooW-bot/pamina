#include "include/mini_app_flutter/mini_app_flutter_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "mini_app_flutter_plugin.h"

void MiniAppFlutterPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  mini_app_flutter::MiniAppFlutterPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
