# Kodi Omega API snapshot used by AddKo

AddKo does **not** treat Dart/Flutter as the source of truth for Kodi legacy
addon APIs anymore. The compatibility surface is pinned to the official Kodi
Omega source tree.

Pinned upstream commit:

`f8815ee40f49a700c047982d752be4b2a61420e2`

Upstream repository:

`https://github.com/xbmc/xbmc`

The vendored SWIG module descriptions in this directory are copied from Kodi
and remain GPL-2.0-or-later. They describe which native legacy interfaces form
the Python modules `xbmc`, `xbmcgui`, `xbmcplugin`, `xbmcaddon` and `xbmcvfs`.

The AddKo runtime keeps behaviour-critical functions explicitly bridged. When
an addon reaches an API that has not been bridged yet, `kodi_proxy.py` routes it
through the generic host bridge instead of failing immediately with
`AttributeError`. This is a migration mechanism while the native legacy engine
is expanded; it is not a replacement for Kodi's real behaviour.

The long-term boundary is:

```text
Flutter UI
   |
AddKo native bridge
   |
Kodi-compatible legacy engine
   |-- CPython
   |-- xbmc / xbmcgui / xbmcplugin / xbmcaddon / xbmcvfs
   |-- VFS / Player / JSON-RPC
   `-- Kodi binary addon ABI
```

Do not hand-invent new Kodi API names or numeric constants. Check the pinned
Kodi Omega interfaces first.
