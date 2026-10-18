# AddKo plugin format — draft 0

The installable extension is `.addko`. A package is a ZIP archive owned and validated by AddKo; it is not a Kodi addon and it does not contain Python.

## Minimal package

```text
my-plugin.addko
├── manifest.json
├── main.lua
└── assets/
```

`manifest.json` must exist at the archive root. Paths use `/` as the separator.

## Minimal manifest

```json
{
  "id": "com.example.myapp",
  "name": "My App",
  "version": "1.0.0",
  "entry": "main.lua",
  "permissions": ["network", "storage"]
}
```

The declared `entry` must point to a `.lua` file inside the same package.

## Initial permission vocabulary

- `network`
- `storage`
- `media`
- `background`

Unknown permissions are rejected instead of silently granted. Declaring a permission does not bypass the sandbox: every privileged host operation still verifies the installed plugin permission before executing.

## Plugin dependencies

A mini-app may depend on another installed AddKo plugin without adding an application-specific core API.

Example:

```json
{
  "id": "com.example.catalog",
  "name": "Catalog",
  "version": "1.0.0",
  "entry": "main.lua",
  "permissions": ["network"],
  "dependencies": [
    "io.addko.luelement"
  ]
}
```

`dependencies` is optional. Current rules:

- dependency entries are plugin IDs, not URLs or package paths;
- a plugin cannot depend on itself;
- duplicate dependency IDs are rejected;
- up to 32 dependencies may be declared;
- version constraints are intentionally not part of draft 0 yet;
- installing a package with a missing dependency is allowed, but AddKo clearly marks the dependency as absent and will not open the mini-app until required plugins are installed.

A plugin can call only IDs it declared:

```lua
local health = addko.plugins.call(
    "io.addko.luelement",
    "health",
    {}
)
```

The target plugin exposes a normal Lua method named `service(method, args)`. AddKo opens or reuses one persistent session for the target and dispatches the call as:

```lua
Plugin.service("health", {})
```

The broker:

- rejects calls to undeclared plugin IDs;
- reuses an already running dependency session instead of opening duplicates;
- serializes duplicate session startup through a shared opening future;
- detects dependency cycles such as `A → B → A`;
- preserves the target plugin's own sandbox and permissions.

This is deliberately generic. The AddKo core does not know whether the target service is torrent, metadata, radio, manga, an emulator helper or something else.

## Media sources and native player

A service plugin with the `network` permission can publish an HTTP media
source to the AddKo player without buffering the full file in Lua:

```lua
local source = addko.stream.register({
    url = "https://example.org/video.mp4",
    headers = { Authorization = "Bearer token" },
})
-- Return source.url to a declared dependent addon.
-- That addon may call addko.player.play(source.url), with media permission.
addko.stream.revoke(source.id)
```

The stream URL is an ephemeral loopback bearer token scoped to the service
session. The Dart core forwards GET/HEAD, byte ranges and selected media
headers, without sending video bytes over the Lua RPC bridge. A dependency
must keep its service alive while the player uses the stream. More details
and a runnable service + addon pair are in `docs/STREAMING.md`.

## Installation rules implemented now

Before extraction AddKo rejects:

- packages larger than 16 MiB;
- more than 512 archive entries;
- more than 32 MiB total declared extracted data;
- individual files larger than 8 MiB;
- `manifest.json` larger than 64 KiB;
- absolute paths, drive-letter paths, `.` / `..` traversal and backslash paths;
- duplicate paths, including case-only duplicates;
- symbolic links;
- missing or invalid root `manifest.json`;
- missing/non-file Lua entrypoints;
- unknown permissions;
- malformed, duplicate or self-referencing dependency IDs.

A valid package is extracted into a staging directory first. When updating an installed plugin, the old directory is moved aside and the staged package replaces it only after validation and extraction complete.

## Runtime

Each installed plugin opens an isolated persistent Lua state. The AddKo host injects APIs for capabilities such as UI, networking, scoped storage and media instead of exposing Android, Flutter, arbitrary native libraries, `io`, `os`, `package` or `debug` directly.

Lua host calls can yield through the AddKo coroutine scheduler while Dart performs asynchronous work, then resume in the same plugin session.

## Experience roots

`start()` is not restricted to a Kodi-like media screen. It currently supports two first-class experience roots:

- `type = "page"` for application UI;
- `type = "game"` for real-time games and Lua emulators.

More experience types may be introduced as generic host capabilities without changing the `.addko` package model.

## Declarative UI

A plugin method such as `start()` can return a page:

```lua
return {
    type = "page",
    title = "Example",
    body = {
        type = "text",
        text = "Hello",
    },
}
```

Current components include text, buttons, cards, rows, columns, lists, grids, images, spacers, dividers, form controls and tabs. Flutter validates the tree before rendering it.

### Navigation

Interactive components can choose how a returned page is applied:

- `navigation = "replace"` — default; replace the current document;
- `navigation = "push"` — push the current document onto the mini-app navigation stack and show the returned page;
- `navigation = "pop"` — return to the previous mini-app document. A button using `pop` does not need an `action`.

The in-app navigation stack is bounded to 32 documents.

### Tabs

A local tab container does not require a Lua round-trip to switch tabs:

```lua
{
    type = "tabs",
    tabs = {
        {
            label = "Home",
            child = { type = "text", text = "Home" },
        },
        {
            label = "Profile",
            child = { type = "text", text = "Profile" },
        },
    },
}
```

A single `tabs` component is limited to 8 tabs.

### Package-local images

Images stored inside the plugin package use the `asset:` scheme and must remain under the package `assets/` directory:

```lua
{
    type = "image",
    src = "asset:assets/logo.png",
}
```

Local assets do not require the `network` permission. Absolute paths, backslashes, `.` / `..`, empty path segments and any path outside `assets/` are rejected. Network images continue to require the `network` permission.

## Game and emulator root

A Lua game may return:

```lua
return {
    type = "game",
    title = "My Game",
    width = 320,
    height = 180,
    fps = 60,
    frame_action = "frame",
    pixel_art = true,
}
```

`frame_action` is called with `(dt, input)`. `dt` is bounded elapsed time in seconds. `input.keys` contains normalized keyboard keys and `input.pointers` contains active touch/mouse pointers in the virtual game coordinate system.

The frame method returns `type = "game_frame"`. A frame can contain up to 1024 bounded drawing commands (`rect`, `circle`, `line`, `text`, `image`) and may include a complete `rgba8888` pixel framebuffer for Lua emulators.

Game sprites can only reference `asset:assets/...`. Plugins do not receive native canvas, GPU, OpenGL/Vulkan, JNI or FFI handles.

Current game limits include:

- maximum 60 requested FPS;
- no overlapping Lua frame calls;
- maximum 2 MiB serialized frame payload;
- maximum 1024 draw commands per frame;
- maximum 512×512 RGBA8888 framebuffer;
- three consecutive invalid/erroring frames pause the surface;
- game assets remain scoped to the installed package.

These limits are host policy, not plugin preferences, and a package cannot disable them.
