#include "addko_kodi_engine.h"

#include <dlfcn.h>

#include <array>
#include <cstring>
#include <mutex>
#include <string>

namespace {
struct Capability {
  const char* id;
  const char* version;
};

// Values copied from Kodi Omega's
// xbmc/addons/kodi-dev-kit/include/kodi/versions.h.
constexpr std::array<Capability, 18> kCapabilities{{
    {"kodi.binary.global.main", "2.0.2"},
    {"kodi.binary.global.general", "1.0.5"},
    {"kodi.binary.global.gui", "5.15.0"},
    {"kodi.binary.global.audioengine", "1.1.1"},
    {"kodi.binary.global.filesystem", "1.1.9"},
    {"kodi.binary.global.network", "1.0.4"},
    {"kodi.binary.global.tools", "1.0.4"},
    {"kodi.binary.instance.audiodecoder", "4.0.0"},
    {"kodi.binary.instance.audioencoder", "3.0.0"},
    {"kodi.binary.instance.game", "3.0.2"},
    {"kodi.binary.instance.imagedecoder", "3.0.1"},
    {"kodi.binary.instance.inputstream", "3.3.0"},
    {"kodi.binary.instance.peripheral", "3.0.2"},
    {"kodi.binary.instance.pvr", "8.3.0"},
    {"kodi.binary.instance.screensaver", "2.2.0"},
    {"kodi.binary.instance.vfs", "3.0.1"},
    {"kodi.binary.instance.visualization", "4.0.0"},
    {"kodi.binary.instance.videocodec", "2.1.0"},
}};

std::mutex g_mutex;
std::string g_last_error;

void set_error(const char* error) {
  std::lock_guard<std::mutex> lock(g_mutex);
  g_last_error = error ? error : "Unknown native Kodi engine error.";
}

void clear_error() {
  std::lock_guard<std::mutex> lock(g_mutex);
  g_last_error.clear();
}
}  // namespace

extern "C" const char* addko_kodi_engine_version(void) {
  return "0.1.0";
}

extern "C" const char* addko_kodi_engine_kodi_release(void) {
  return "21.0.0-Omega";
}

extern "C" const char* addko_kodi_capability_version(const char* addon_id) {
  if (addon_id == nullptr || addon_id[0] == '\0') {
    return "";
  }
  for (const auto& capability : kCapabilities) {
    if (std::strcmp(capability.id, addon_id) == 0) {
      return capability.version;
    }
  }
  return "";
}

extern "C" int addko_kodi_probe_binary_addon(const char* library_path) {
  if (library_path == nullptr || library_path[0] == '\0') {
    set_error("Binary addon library path is empty.");
    return 0;
  }

  dlerror();
  void* handle = dlopen(library_path, RTLD_NOW | RTLD_LOCAL);
  if (handle == nullptr) {
    set_error(dlerror());
    return 0;
  }

  int result = 0x01;
  if (dlsym(handle, "ADDON_Create") != nullptr) {
    result |= 0x02;
  }
  if (dlsym(handle, "ADDON_GetTypeVersion") != nullptr) {
    result |= 0x04;
  }
  if (dlsym(handle, "ADDON_GetTypeMinVersion") != nullptr) {
    result |= 0x08;
  }

  dlclose(handle);
  if ((result & 0x06) != 0x06) {
    set_error("Shared library is not a complete Kodi binary addon entrypoint.");
  } else {
    clear_error();
  }
  return result;
}

extern "C" const char* addko_kodi_engine_last_error(void) {
  std::lock_guard<std::mutex> lock(g_mutex);
  return g_last_error.c_str();
}
