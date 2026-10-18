# AddKo — generic media streaming bridge

The core now includes a per-plugin HTTP media bridge. This is a **transport**,
not a Torrent client, an IPTV addon, an adaptive-media engine, or a media
catalog. Plugins resolve their own media URLs and addons design their own UI.

## One plugin, another addon, native player

1. An installed service plugin with `network` permission receives a playable
   HTTP(S) media source URL and optional upstream request headers.
2. The service invokes `addko.stream.register({url=..., headers=...})`, which
   returns `{id, url}`. The URL points to a random, loopback-only HTTP endpoint.
3. An addon declares that service in `dependencies`, calls it using
   `addko.plugins.call` and invokes `addko.player.play(result.url)`.
   The addon needs `media` permission for the native player.
4. The native player requests media directly from the local HTTP endpoint.
   Dart forwards byte streams from the upstream source without passing them
   through Lua, including single HTTP byte-range requests used for seeking.
5. The owning service calls `addko.stream.revoke(id)` to deny future requests,
   or AddKo removes all endpoints when that Lua session closes.

A Lua service does **not** need `media` permission merely to register a source;
and a consumer addon does **not** need `network` just to play the returned local
URL. The declared dependency controls which addon can request the service.

## Source capabilities

- HTTP/HTTPS input (including a local HTTP endpoint provided by a native helper).
- Per-source request headers, e.g. `Authorization` or `Cookie`.
- GET and HEAD from the player, passthrough of `Range` / `If-Range` /
  HTTP cache validators.
- HTTP 206 partial responses, `Content-Range` and media metadata headers.
- At most four upstream redirects. Source credentials are **never forwarded**
  when the redirect changes origin.
- Direct streaming with backpressure; no whole-video buffering.
- Bounded activity: at most eight registered sources and eight concurrent
  local HTTP media requests per plugin instance.
- Cryptographically random bearer URL (192-bit token), bound to 127.0.0.1.
  Treat the resulting URL as temporary and do not publish it.
- Upstream connection timeout: 15 seconds. Upstream idle-chunk timeout: 60
  seconds, allowing long downloads while receiving data continuously.

Source registration rejects non-HTTP protocols, userinfo in the URL,
fragment identifiers, unsafe upstream headers and oversized header fields.
The bridge itself **only** performs HTTP transport. No plugin can inject
arbitrary request/response files into the native player.

## Installed examples

Package each directory below into a separate `.addko` ZIP with
`manifest.json` and `main.lua` at the ZIP root:

- `examples/media_source_service` — a reusable tool, type `service`,
  requires `network` and exposes `service("open", {url=...})`.
- `examples/media_player_app` — a Lua visual addon, type `app`,
  requires `media`, declares the service as a dependency, and calls the
  built-in player.

Install the service first, then the addon. Enter a legal HTTP(S) progressive
video URL that supports byte ranges and select Reproduzir.

## Limits

The bridge does not decode video, create torrent peers, add SMB/NFS support,
rewrite HLS or DASH playlists, parse manifests or relay arbitrary non-HTTP
streams. Sources such as m3u8 playlists that contain relative segment URLs or
require per-segment authentication need a future adaptive-stream capability.
The existing player currently uses Flutter's `video_player` backend.

The bridge is intentionally tied to the source plugin's Lua session. Stopping
that service interrupts playback. Revoking the ID prevents subsequent
requests, but a request already streaming may finish.

The new code and tests require a Flutter/Dart runtime to compile and run.
Tests were added but were not run in the connector environment.
