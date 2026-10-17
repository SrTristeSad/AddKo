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
- unknown permissions.

A valid package is extracted into a staging directory first. When updating an installed plugin, the old directory is moved aside and the staged package replaces it only after validation and extraction complete.

## Runtime

Each installed plugin opens an isolated persistent Lua state. The AddKo host injects APIs for capabilities such as UI, networking, scoped storage and media instead of exposing Android, Flutter, arbitrary native libraries, `io`, `os`, `package` or `debug` directly.

Lua host calls can yield through the AddKo coroutine scheduler while Dart performs asynchronous work, then resume in the same plugin session.

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
