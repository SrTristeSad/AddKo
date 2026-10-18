# AddKo

AddKo is being rebuilt from the ground up as a **Lua mini-app platform**.

The old Kodi/Python architecture is no longer part of `main`. It is preserved in the branch `legacy/kodi-0.2.1` only for historical reference.

## Foundation

- Flutter owns the application UI.
- Lua 5.5.1 is the official plugin runtime.
- Lua is compiled from the official upstream C sources and linked into the Android app.
- Plugins use the AddKo-owned `.addko` package format.
- Each plugin runs in an isolated Lua state with explicit permissions.
- Kodi and Python compatibility are explicitly out of scope.
- Plugins call generic AddKo APIs instead of Android/Flutter directly.

## Current milestone

The runtime is now connected to a real persistent mini-app lifecycle and the first generic host APIs.

Implemented in `main` (with outbound TCP/TLS available in the network-core integration branch):

1. fetch and SHA-256 verify the official Lua 5.5.1 source;
2. compile Lua into `libaddko_lua.so` for Android ARM64;
3. create a constrained Lua state with memory/instruction limits;
4. expose a safe plugin-local `require` without enabling the standard `package` library;
5. install and validate `.addko` ZIP packages;
6. persist one Lua state for the lifetime of an opened mini-app;
7. coroutine-based asynchronous Lua → Dart host calls;
8. declarative Flutter UI returned by Lua;
9. forms, buttons, cards, lists/grids, images and common controls;
10. permission-gated HTTP/HTTPS;
11. sandboxed per-plugin filesystem;
12. loopback-only TCP server for background plugins;
13. reusable outbound TCP/TLS client sockets for Lua plugins (bounded read/write);
14. generic Flutter dialogs (`alert`, `confirm`, `input`, `select`);
15. generic video player API and player surface;
16. safe Android external-URI launcher through `system.open_uri`;
17. plugin background sessions;
18. platform, locale, JSON, paths and timing APIs;
19. generic desktop native-process host for Windows/Linux/macOS, restricted to the plugin/data sandbox.

The sandbox still does **not** expose `io`, `os`, `package` or `debug`. `dofile`, `loadfile` and `collectgarbage` remain unavailable.

## Generic host model

A plugin can use capabilities such as:

```text
addko.http
addko.fs
addko.net.tcp       # outbound TCP/TLS + loopback server
addko.ui
addko.player
addko.system
addko.process        # desktop only
addko.paths
addko.platform
addko.locale
addko.json
addko.sleep
```

The core does not contain application-specific APIs such as torrent, manga, radio or social-network APIs. Those belong to plugins.

The current permission vocabulary remains intentionally small:

```text
network
storage
media
background
```

`system.open_uri` does not create a product-specific permission. The Android host validates the URI and rejects local/dangerous schemes such as `file:`, `content:`, `data:`, `javascript:` and `intent:`.

Desktop `process.spawn` also does not introduce a product-specific permission. It is only enabled when the plugin already declares `storage` + `background`, and the executable/working directory must stay inside the installed plugin directory or that plugin's private data directory.

## First stress-test plugin

[Luelement](https://github.com/SrTristeSad/Luelement) is being used as the first demanding Plugin v2 integration.

It exercises:

- persistent Lua state;
- HTTP redirects;
- loopback TCP callbacks;
- dialogs;
- forms/UI updates;
- background lifetime;
- local media playback;
- standalone native helper launch on desktop;
- external companion deep links on Android.

Torrent/libtorrent is **not** part of the AddKo core. Luelement talks to the Elementum engine through generic AddKo APIs.

## Native process policy

### Desktop

On Windows, Linux and macOS, plugins with `storage` + `background` may use the generic `addko.process` API. The host accepts only executables located inside the plugin's own installation/data sandbox. Processes started by a session are terminated when that host session closes.

### Android/iOS

Plugin code cannot download and execute arbitrary native binaries from writable storage. `process.spawn` therefore remains unavailable on mobile hosts.

Native workloads that genuinely require Android-native packaging can use a separately installed companion app/service and communicate through generic network/URI contracts. Luelement Engine is the first test of this architecture.

## Build on Windows

Run:

```bat
BUILD_ANDROID.bat
```

The script intentionally pauses before closing so build errors remain visible.

For analysis/tests only:

```bat
TESTAR_CODIGO.bat
```

## Lua upstream

Pinned release: **Lua 5.5.1**

Official archive: `https://www.lua.org/ftp/lua-5.5.1.tar.gz`

SHA-256:

```text
1c4b4068d67061f2a2231ad2b5422e77acea1487ea9890f6320af614f4373dce
```

The source is downloaded during setup instead of being copied into this repository.

See `docs/ARCHITECTURE.md`, `docs/PLUGIN_SPEC.md`, `docs/NETWORK.md` and `docs/ROADMAP.md`.
