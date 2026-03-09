#include "include/pamina/pamina_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "pamina_plugin.h"

void PaminaPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  pamina::PaminaPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
