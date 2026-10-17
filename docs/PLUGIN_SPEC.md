# AddKo plugin format — draft 0

The target installable extension is `.addko`, a validated ZIP package owned by AddKo.

## Minimal package

```text
my-plugin.addko
├── manifest.json
├── main.lua
└── assets/
```

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

## Initial permission vocabulary

- `network`
- `storage`
- `media`
- `background`

Unknown permissions are rejected instead of silently granted.

## Planned lifecycle

The host will expose a small lifecycle rather than Android/Flutter internals. The exact Lua API is intentionally not frozen yet; it will be versioned before external plugins are supported.

## Security requirements

Before a package becomes installable, AddKo must validate archive paths, manifest schema, package size, entrypoint location, duplicate paths, decompression limits and requested permissions. Plugins must never be able to load arbitrary native libraries.
