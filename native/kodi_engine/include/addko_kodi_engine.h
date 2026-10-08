#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// AddKo's native Kodi compatibility engine. The ABI/version values mirror the
// Kodi 21 (Omega) development kit so repository dependencies such as
// kodi.binary.global.* are host capabilities rather than downloadable addons.

const char* addko_kodi_engine_version(void);
const char* addko_kodi_engine_kodi_release(void);
const char* addko_kodi_capability_version(const char* addon_id);

// Probe a Kodi binary addon shared library without creating an instance.
// Return value is a bit mask:
//   0x01 = library opened
//   0x02 = ADDON_Create exported
//   0x04 = ADDON_GetTypeVersion exported
//   0x08 = ADDON_GetTypeMinVersion exported
int addko_kodi_probe_binary_addon(const char* library_path);

const char* addko_kodi_engine_last_error(void);

#ifdef __cplusplus
}
#endif
