# AddKo architecture

## Decision

AddKo is a first-party mini-app host. It no longer attempts to emulate or embed Kodi and it does not use Python as a plugin runtime.

## Layers

```text
Flutter shell / renderer
        |
AddKo host APIs
(UI, navigation, storage, network, media, permissions)
        |
Lua runtime manager
(one isolated lua_State per plugin instance)
        |
Official Lua 5.5.1 C runtime
        |
Android / platform services
```

## Runtime rules

Each plugin instance gets its own Lua state. Host capabilities are injected explicitly. A plugin never receives Dart FFI, Android JNI, arbitrary filesystem access or native library loading.

The initial native runtime enforces:

- 8 MiB allocator budget per Lua state;
- an instruction hook budget per evaluation;
- no `io` library;
- no `os` library;
- no `package`/`loadlib` library;
- no `debug` library;
- no `dofile` or `loadfile`;
- no direct host filesystem access.

These limits are a foundation, not the final sandbox. The plugin process/isolate model and asynchronous host-call scheduler are separate milestones.

## UI model

Plugins will describe UI through AddKo APIs. Flutter remains the renderer. Lua code must not know Flutter widget classes and must not draw directly into the Flutter tree.

The same plugin description should later adapt to phone, tablet, TV, keyboard, mouse and remote-control navigation.

## Compatibility policy

There is intentionally no Kodi addon compatibility and no Python plugin compatibility in the new architecture. The previous implementation is archived under `legacy/kodi-0.2.1`.
