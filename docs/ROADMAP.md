# AddKo roadmap — Lua rewrite

## Phase 0 — clean reset

- [x] preserve the Kodi/Python implementation under `legacy/kodi-0.2.1`;
- [x] remove Kodi and Python from the new `main` tree;
- [x] define Lua as the only plugin runtime;
- [x] pin official Lua 5.5.1 with SHA-256 verification.

## Phase 1 — native Lua foundation

- [x] Android CMake target for Lua;
- [x] Dart FFI wrapper;
- [x] one Lua state per runtime instance;
- [x] initial memory budget;
- [x] initial instruction budget;
- [x] restricted standard libraries;
- [x] Android smoke UI evaluating `return 6 * 7`;
- [ ] CI validation on a real Android emulator/device.

## Phase 2 — package loader

- [x] initial manifest domain validation;
- [x] `.addko` ZIP parser;
- [x] zip-slip and decompression-bomb protection;
- [x] package size/resource limits;
- [x] install staging + atomic commit/rollback;
- [x] installed plugin registry;
- [x] uninstall flow with optional data cleanup and dependency protection;
- [x] update/replace flow.

## Phase 3 — AddKo host API

- [ ] versioned host API;
- [x] initial manifest-scoped native engines API (APK-bundled only);
- [x] UI tree protocol;
- [x] event callbacks;
- [x] in-app push/replace/pop navigation;
- [x] scoped storage;
- [x] permission-gated HTTP;
- [x] asynchronous Lua coroutine scheduler;
- [ ] structured errors/logging.

## Phase 4 — mini-app platform

- [x] lists and grids;
- [x] forms;
- [x] tabs;
- [x] network and package-local images;
- [x] initial audio/video media API;
- [x] first-class `type="game"` Lua experience root;
- [x] sandboxed 2D game surface with keyboard/touch input;
- [x] bounded draw-command protocol for Lua games;
- [x] RGBA8888 framebuffer path for Lua emulators;
- [x] package-local sprites inside game frames;
- [ ] dedicated gamepad axes/buttons API;
- [ ] low-overhead native frame transport for demanding emulators;
- [ ] audio sample/buffer API for games and emulators;
- [ ] local database API;
- [ ] authentication helpers;
- [ ] background services with quotas;
- [ ] phone/tablet/TV input model;
- [ ] plugin developer tools.

## Design rule

AddKo mini-apps must not be forced into Kodi-style media-addon screens. The host exposes generic capabilities and sandbox limits; Lua is free to combine them into apps, tools, readers, games, emulators and other experiences.
