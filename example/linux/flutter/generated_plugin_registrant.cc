//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <mini_app_flutter/mini_app_flutter_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) mini_app_flutter_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "MiniAppFlutterPlugin");
  mini_app_flutter_plugin_register_with_registrar(mini_app_flutter_registrar);
}
