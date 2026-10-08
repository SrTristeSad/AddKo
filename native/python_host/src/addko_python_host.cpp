#include "addko_python_host.h"

#include <dlfcn.h>

#include <array>
#include <mutex>
#include <string>

namespace {
using PyInitializeFn = void (*)();
using PyIsInitializedFn = int (*)();
using PyRunSimpleStringFn = int (*)(const char*);
using PyFinalizeExFn = int (*)();
using PyGetVersionFn = const char* (*)();

std::mutex g_mutex;
void* g_python_handle = nullptr;
PyInitializeFn g_py_initialize = nullptr;
PyIsInitializedFn g_py_is_initialized = nullptr;
PyRunSimpleStringFn g_py_run_simple_string = nullptr;
PyFinalizeExFn g_py_finalize_ex = nullptr;
PyGetVersionFn g_py_get_version = nullptr;
bool g_initialized_by_addko = false;
std::string g_last_error;
std::string g_version;

void set_error(const std::string& message) {
  g_last_error = message;
}

bool resolve_symbols_locked() {
  g_py_initialize = reinterpret_cast<PyInitializeFn>(
      dlsym(g_python_handle, "Py_Initialize"));
  g_py_is_initialized = reinterpret_cast<PyIsInitializedFn>(
      dlsym(g_python_handle, "Py_IsInitialized"));
  g_py_run_simple_string = reinterpret_cast<PyRunSimpleStringFn>(
      dlsym(g_python_handle, "PyRun_SimpleString"));
  g_py_finalize_ex = reinterpret_cast<PyFinalizeExFn>(
      dlsym(g_python_handle, "Py_FinalizeEx"));
  g_py_get_version = reinterpret_cast<PyGetVersionFn>(
      dlsym(g_python_handle, "Py_GetVersion"));

  if (!g_py_initialize || !g_py_is_initialized || !g_py_run_simple_string ||
      !g_py_finalize_ex || !g_py_get_version) {
    const char* error = dlerror();
    set_error(error ? error : "CPython symbols are incomplete.");
    return false;
  }

  const char* version = g_py_get_version();
  g_version = version ? version : "unknown";
  g_last_error.clear();
  return true;
}

bool load_python_locked() {
  if (g_python_handle != nullptr) {
    return true;
  }

  constexpr std::array<const char*, 4> candidates = {
      "libpython3.13.so",
      "libpython3.12.so",
      "libpython3.11.so",
      "libpython3.so",
  };

  for (const char* candidate : candidates) {
    dlerror();
    g_python_handle = dlopen(candidate, RTLD_NOW | RTLD_GLOBAL);
    if (g_python_handle == nullptr) {
      continue;
    }
    if (resolve_symbols_locked()) {
      return true;
    }
    dlclose(g_python_handle);
    g_python_handle = nullptr;
  }

  const char* error = dlerror();
  set_error(
      error ? error
            : "No bundled libpython3.x.so was found for this architecture.");
  return false;
}
}  // namespace

extern "C" int addko_python_probe(void) {
  std::lock_guard<std::mutex> lock(g_mutex);
  return load_python_locked() ? 1 : 0;
}

extern "C" int addko_python_initialize(void) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (!load_python_locked()) {
    return -1;
  }
  if (g_py_is_initialized()) {
    return 0;
  }
  g_py_initialize();
  if (!g_py_is_initialized()) {
    set_error("Py_Initialize did not initialize CPython.");
    return -2;
  }
  g_initialized_by_addko = true;
  g_last_error.clear();
  return 0;
}

extern "C" int addko_python_is_initialized(void) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (!load_python_locked()) {
    return 0;
  }
  return g_py_is_initialized() ? 1 : 0;
}

extern "C" int addko_python_exec(const char* code) {
  if (code == nullptr) {
    std::lock_guard<std::mutex> lock(g_mutex);
    set_error("Python source is null.");
    return -1;
  }

  std::lock_guard<std::mutex> lock(g_mutex);
  if (!load_python_locked()) {
    return -2;
  }
  if (!g_py_is_initialized()) {
    g_py_initialize();
    if (!g_py_is_initialized()) {
      set_error("Unable to initialize CPython before execution.");
      return -3;
    }
    g_initialized_by_addko = true;
  }

  const int result = g_py_run_simple_string(code);
  if (result != 0) {
    set_error("PyRun_SimpleString returned a non-zero status.");
    return result;
  }
  g_last_error.clear();
  return 0;
}

extern "C" int addko_python_shutdown(void) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_python_handle == nullptr || !g_py_is_initialized) {
    return 0;
  }
  if (!g_py_is_initialized()) {
    return 0;
  }
  if (!g_initialized_by_addko) {
    return 0;
  }

  const int result = g_py_finalize_ex();
  g_initialized_by_addko = false;
  if (result != 0) {
    set_error("Py_FinalizeEx returned a non-zero status.");
    return result;
  }
  g_last_error.clear();
  return 0;
}

extern "C" const char* addko_python_version(void) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (!load_python_locked()) {
    return "";
  }
  return g_version.c_str();
}

extern "C" const char* addko_python_last_error(void) {
  std::lock_guard<std::mutex> lock(g_mutex);
  return g_last_error.c_str();
}
