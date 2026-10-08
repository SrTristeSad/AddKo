#include "addko_python_host.h"

#include <dlfcn.h>

#include <array>
#include <cstdlib>
#include <mutex>
#include <string>

namespace {
using PyInitializeFn = void (*)();
using PyIsInitializedFn = int (*)();
using PyRunSimpleStringFn = int (*)(const char*);
using PyFinalizeExFn = int (*)();
using PyGetVersionFn = const char* (*)();
using PyGILStateEnsureFn = int (*)();
using PyGILStateReleaseFn = void (*)(int);
using PyEvalSaveThreadFn = void* (*)();
using PyEvalRestoreThreadFn = void (*)(void*);
using PyThreadStateGetFn = void* (*)();
using PyThreadStateSwapFn = void* (*)(void*);
using PyNewInterpreterFn = void* (*)();
using PyEndInterpreterFn = void (*)(void*);

std::mutex g_mutex;
void* g_python_handle = nullptr;
PyInitializeFn g_py_initialize = nullptr;
PyIsInitializedFn g_py_is_initialized = nullptr;
PyRunSimpleStringFn g_py_run_simple_string = nullptr;
PyFinalizeExFn g_py_finalize_ex = nullptr;
PyGetVersionFn g_py_get_version = nullptr;
PyGILStateEnsureFn g_py_gil_state_ensure = nullptr;
PyGILStateReleaseFn g_py_gil_state_release = nullptr;
PyEvalSaveThreadFn g_py_eval_save_thread = nullptr;
PyEvalRestoreThreadFn g_py_eval_restore_thread = nullptr;
PyThreadStateGetFn g_py_thread_state_get = nullptr;
PyThreadStateSwapFn g_py_thread_state_swap = nullptr;
PyNewInterpreterFn g_py_new_interpreter = nullptr;
PyEndInterpreterFn g_py_end_interpreter = nullptr;
void* g_main_thread_state = nullptr;
bool g_initialized_by_addko = false;
std::string g_last_error;
std::string g_version;
std::string g_python_home;

void set_error_locked(const std::string& message) {
  g_last_error = message;
}

void set_error(const std::string& message) {
  std::lock_guard<std::mutex> lock(g_mutex);
  set_error_locked(message);
}

void clear_error() {
  std::lock_guard<std::mutex> lock(g_mutex);
  g_last_error.clear();
}

std::string major_minor_locked() {
  const std::size_t first = g_version.find('.');
  if (first == std::string::npos) {
    return "";
  }
  const std::size_t second = g_version.find('.', first + 1);
  if (second == std::string::npos) {
    return g_version;
  }
  return g_version.substr(0, second);
}

bool resolve_symbols_locked() {
  dlerror();
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
  g_py_gil_state_ensure = reinterpret_cast<PyGILStateEnsureFn>(
      dlsym(g_python_handle, "PyGILState_Ensure"));
  g_py_gil_state_release = reinterpret_cast<PyGILStateReleaseFn>(
      dlsym(g_python_handle, "PyGILState_Release"));
  g_py_eval_save_thread = reinterpret_cast<PyEvalSaveThreadFn>(
      dlsym(g_python_handle, "PyEval_SaveThread"));
  g_py_eval_restore_thread = reinterpret_cast<PyEvalRestoreThreadFn>(
      dlsym(g_python_handle, "PyEval_RestoreThread"));
  g_py_thread_state_get = reinterpret_cast<PyThreadStateGetFn>(
      dlsym(g_python_handle, "PyThreadState_Get"));
  g_py_thread_state_swap = reinterpret_cast<PyThreadStateSwapFn>(
      dlsym(g_python_handle, "PyThreadState_Swap"));
  g_py_new_interpreter = reinterpret_cast<PyNewInterpreterFn>(
      dlsym(g_python_handle, "Py_NewInterpreter"));
  g_py_end_interpreter = reinterpret_cast<PyEndInterpreterFn>(
      dlsym(g_python_handle, "Py_EndInterpreter"));

  if (!g_py_initialize || !g_py_is_initialized || !g_py_run_simple_string ||
      !g_py_finalize_ex || !g_py_get_version || !g_py_gil_state_ensure ||
      !g_py_gil_state_release || !g_py_eval_save_thread ||
      !g_py_eval_restore_thread || !g_py_thread_state_get ||
      !g_py_thread_state_swap || !g_py_new_interpreter ||
      !g_py_end_interpreter) {
    const char* error = dlerror();
    set_error_locked(error ? error : "CPython symbols are incomplete.");
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

  constexpr std::array<const char*, 5> candidates = {
      "libpython3.14.so",
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
  set_error_locked(
      error ? error
            : "No bundled libpython3.x.so was found for this architecture.");
  return false;
}

bool configure_home_locked(const char* home) {
  if (home == nullptr || home[0] == '\0') {
    set_error_locked("Python home is empty.");
    return false;
  }
  if (!load_python_locked()) {
    return false;
  }

  const std::string requested(home);
  if (g_py_is_initialized && g_py_is_initialized()) {
    if (g_python_home == requested) {
      return true;
    }
    set_error_locked("CPython is already initialized with a different Python home.");
    return false;
  }

  const std::string version = major_minor_locked();
  if (version.empty()) {
    set_error_locked("Unable to determine CPython major/minor version.");
    return false;
  }

  const std::string stdlib = requested + "/lib/python" + version;
  const std::string python_path =
      stdlib + ":" + stdlib + "/lib-dynload:" + stdlib + "/site-packages";

  if (setenv("PYTHONHOME", requested.c_str(), 1) != 0 ||
      setenv("PYTHONPATH", python_path.c_str(), 1) != 0 ||
      setenv("PYTHONUTF8", "1", 1) != 0 ||
      setenv("PYTHONDONTWRITEBYTECODE", "1", 1) != 0) {
    set_error_locked("Failed to configure CPython environment variables.");
    return false;
  }

  g_python_home = requested;
  g_last_error.clear();
  return true;
}

bool initialize_locked() {
  if (!load_python_locked()) {
    return false;
  }
  if (g_py_is_initialized()) {
    return true;
  }
  if (g_python_home.empty()) {
    set_error_locked("Python home must be configured before initialization.");
    return false;
  }

  g_py_initialize();
  if (!g_py_is_initialized()) {
    set_error_locked("Py_Initialize did not initialize CPython.");
    return false;
  }

  g_initialized_by_addko = true;
  // Py_Initialize leaves the GIL owned by the initializing native thread.
  // Release it immediately so later Flutter/Dart worker isolates can safely
  // acquire the interpreter through PyGILState_Ensure.
  g_main_thread_state = g_py_eval_save_thread();
  g_last_error.clear();
  return true;
}

bool ensure_initialized() {
  std::lock_guard<std::mutex> lock(g_mutex);
  return initialize_locked();
}
}  // namespace

extern "C" int addko_python_probe(void) {
  std::lock_guard<std::mutex> lock(g_mutex);
  return load_python_locked() ? 1 : 0;
}

extern "C" int addko_python_configure(const char* home) {
  std::lock_guard<std::mutex> lock(g_mutex);
  return configure_home_locked(home) ? 0 : -1;
}

extern "C" int addko_python_initialize(void) {
  std::lock_guard<std::mutex> lock(g_mutex);
  return initialize_locked() ? 0 : -1;
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
    set_error("Python source is null.");
    return -1;
  }
  if (!ensure_initialized()) {
    return -2;
  }

  const int gil_state = g_py_gil_state_ensure();
  const int result = g_py_run_simple_string(code);
  g_py_gil_state_release(gil_state);

  if (result != 0) {
    set_error("PyRun_SimpleString returned a non-zero status.");
    return result;
  }
  clear_error();
  return 0;
}

extern "C" int addko_python_exec_isolated(const char* code) {
  if (code == nullptr) {
    set_error("Python source is null.");
    return -1;
  }
  if (!ensure_initialized()) {
    return -2;
  }

  const int gil_state = g_py_gil_state_ensure();
  void* main_state = g_py_thread_state_get();
  void* sub_state = g_py_new_interpreter();
  if (sub_state == nullptr) {
    g_py_thread_state_swap(main_state);
    g_py_gil_state_release(gil_state);
    set_error("Py_NewInterpreter returned null.");
    return -3;
  }

  const int result = g_py_run_simple_string(code);
  // Py_EndInterpreter requires the subinterpreter thread state to be current.
  g_py_thread_state_swap(sub_state);
  g_py_end_interpreter(sub_state);
  g_py_thread_state_swap(main_state);
  g_py_gil_state_release(gil_state);

  if (result != 0) {
    set_error("PyRun_SimpleString returned a non-zero status in subinterpreter.");
    return result;
  }
  clear_error();
  return 0;
}

extern "C" int addko_python_shutdown(void) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_python_handle == nullptr || !g_py_is_initialized) {
    return 0;
  }
  if (!g_py_is_initialized() || !g_initialized_by_addko) {
    return 0;
  }

  if (g_main_thread_state != nullptr) {
    g_py_eval_restore_thread(g_main_thread_state);
    g_main_thread_state = nullptr;
  } else {
    g_py_gil_state_ensure();
  }

  const int result = g_py_finalize_ex();
  g_initialized_by_addko = false;
  if (result != 0) {
    set_error_locked("Py_FinalizeEx returned a non-zero status.");
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

extern "C" const char* addko_python_home(void) {
  std::lock_guard<std::mutex> lock(g_mutex);
  return g_python_home.c_str();
}

extern "C" const char* addko_python_last_error(void) {
  std::lock_guard<std::mutex> lock(g_mutex);
  return g_last_error.c_str();
}
