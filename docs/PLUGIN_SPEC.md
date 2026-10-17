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

Unknown permissions are rejected instead of silently granted. Declaring a permission does not grant a Lua API yet; host APIs will be introduced separately and must check the plugin permission before performing privileged work.

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

Each plugin execution creates an isolated Lua state through the native AddKo runtime. The current milestone executes the declared entrypoint and returns its Lua result to the host.

The host API for UI, navigation, networking, storage and media is intentionally not frozen yet. Those capabilities will be injected by AddKo rather than exposing Android, Flutter, native libraries, `io`, `os`, `package` or `debug` directly.
