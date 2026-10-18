# AddKo mini-app model

AddKo is not a Kodi-style addon browser. A `.addko` package is a sandboxed Lua application package. The host supplies capabilities; the package decides what kind of experience it builds.

## Experience roots

A plugin `start()` may currently return one of two first-class roots:

- `type = "page"` — application UI rendered from the declarative Flutter component tree;
- `type = "game"` — real-time Lua game/emulator surface.

This is deliberately open-ended. A package may be a reader, catalog, client, utility, dashboard, music app, game, emulator, tool or another experience that fits the host APIs.

## Game / emulator root

Example:

```lua
return {
    type = "game",
    title = "My Lua Game",
    width = 320,
    height = 180,
    fps = 60,
    frame_action = "frame",
    pixel_art = true,
}
```

The frame method receives `dt` in seconds and an input snapshot:

```lua
function Plugin.frame(dt, input)
    return {
        type = "game_frame",
        clear = "#101820",
        commands = {
            { type = "rect", x = 10, y = 10, width = 20, height = 20, color = "#38BDF8" },
            { type = "text", x = 8, y = 40, text = "Hello", size = 12, color = "#FFFFFF" },
        },
    }
end
```

`input.keys` contains normalized keys such as `arrowLeft`, `arrowRight`, `keyA`, `keyW`, `space` and `enter`. `input.pointers` contains active touch/mouse pointers in the virtual game coordinate system.

### Emulator framebuffer

A Lua emulator may provide a complete RGBA framebuffer instead of thousands of draw commands:

```lua
return {
    type = "game_frame",
    pixels = {
        format = "rgba8888",
        width = 160,
        height = 144,
        data = base64_rgba_bytes,
    },
    commands = {},
}
```

The framebuffer may be combined with draw commands for overlays.

## Drawing commands

The first game protocol supports:

- `rect`
- `circle`
- `line`
- `text`
- `image` using only `asset:assets/...`
- optional RGBA8888 framebuffer

The renderer is owned by AddKo. Lua never receives a raw Flutter canvas, OpenGL/Vulkan handle or native pointer.

## Security boundaries

Freedom inside a mini-app does not mean unrestricted host access. AddKo keeps these boundaries:

- no arbitrary native `.so`, DLL, JNI or FFI supplied by plugins;
- no direct `os`, `io`, `package` or `debug` Lua libraries;
- no filesystem access outside package assets and the plugin's scoped data directory;
- network access only when the manifest requests and the user approves `network`;
- privileged host operations validate permissions again at execution time;
- no arbitrary shader/native GPU program supplied by a plugin;
- package paths reject traversal and symbolic-link escapes;
- Lua states keep memory and instruction budgets;
- game frames are limited to 60 FPS and never overlap Lua frame calls;
- at most 1024 draw commands per frame;
- frame payload is limited to 2 MiB;
- framebuffer is limited to 512×512 RGBA8888;
- repeated invalid frames pause the game surface instead of hammering the runtime.

These limits are host policy and may evolve, but plugins cannot disable them.

## Philosophy

The AddKo core should expose generic capabilities instead of hard-coding media-addon concepts. UI, game rendering, storage, networking, media, dialogs, files and future databases are host services. Lua combines those services into an application.

A media plugin is therefore only one possible AddKo app type — not the architecture that every other plugin must imitate.
