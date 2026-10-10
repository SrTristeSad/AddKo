# Kodi Omega core status

AddKo targets Kodi 21 (Omega).

## What is native today

- CPython is embedded on Android through `libaddko_python_host.so`.
- `libaddko_kodi_engine.so` exposes Kodi Omega binary ABI capability versions and can probe Kodi binary addon entrypoints.
- The official Kodi Omega Python/SWIG and binary addon API/ABI source snapshot is kept under `third_party/kodi_omega`.
- Repository dependencies named `kodi.binary.global.*` and `kodi.binary.instance.*` are treated as host capabilities, as Kodi does, rather than downloadable repository addons.

## What is still compatibility code

Python modules such as `xbmc`, `xbmcgui`, `xbmcplugin`, `xbmcaddon` and `xbmcvfs` are currently hosted by AddKo's Python bridge. Behaviour-critical functions are implemented explicitly and the official Kodi Omega interfaces are the source of truth.

## What is not complete yet

AddKo does **not** yet embed Kodi's complete Android `libkodi.so` application core (`CServiceBroker`, `CPluginDirectory`, full GUI core, full player core and binary addon instance manager). Therefore the project must not describe the current bridge as the complete Kodi core.

The next native milestone is binary addon instance creation, starting with `kodi.binary.instance.inputstream`, followed by `inputstream.adaptive`. Longer term, plugin execution can be moved behind the real Kodi Android core while Flutter remains the AddKo frontend.

## Upstream

Kodi Omega source: https://github.com/xbmc/xbmc

Pinned source commit used by the vendoring tool:

`f8815ee40f49a700c047982d752be4b2a61420e2`

Kodi code is GPL-2.0-or-later. Vendored upstream files preserve their license headers.
