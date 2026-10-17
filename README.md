# AddKo

AddKo is being rebuilt from the ground up as a **Lua mini-app platform**.

The old Kodi/Python architecture is no longer part of `main`. It is preserved in the branch `legacy/kodi-0.2.1` only for historical reference.

## New foundation

- Flutter owns the application UI.
- Lua 5.5.1 is the official plugin runtime.
- Lua is compiled from the official upstream C sources and linked into the Android app.
- Each future plugin will run in an isolated Lua state with explicit permissions.
- The AddKo API will provide UI, navigation, storage, networking, media and other capabilities instead of exposing Android or Flutter directly.
- Kodi and Python compatibility are explicitly out of scope.

## Current milestone

The first milestone proves the new stack end to end:

1. fetch and SHA-256 verify the official Lua 5.5.1 source;
2. compile Lua into `libaddko_lua.so` for Android ARM64;
3. create a constrained Lua state;
4. execute Lua through Dart FFI;
5. enforce an initial memory limit and instruction budget;
6. expose only a reduced standard library set.

The current sandbox does **not** open `io`, `os`, `package`, or `debug`. `dofile`, `loadfile`, and `collectgarbage` are removed from the base environment.

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

See `docs/ARCHITECTURE.md`, `docs/PLUGIN_SPEC.md`, and `docs/ROADMAP.md`.
