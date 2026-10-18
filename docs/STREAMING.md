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

## Read-only stream diagnostics

After registering a source, its owning Lua plugin may call
`addko.stream.stats(source.id)`. This requires the same `network`
permission as registration. It returns only transport counters:

- `requests`, `head_requests`, `range_requests`, `upstream_requests`
- `bytes_forwarded`, `active_requests`, `failed_requests`
- `last_http_status` (number or nil), `last_error` (error class or nil)

No authorization header, source URL or bearer token appears in the result.
Metrics are scoped to one source and disappear when it is revoked.
Service plugins may offer them to declared dependent addons through their
`service()` interface.

**Interpreting the results:** no requests suggests the player could not
connect to the local URL; upstream status 404/500 suggests source issues;
HTTP 200/206 plus bytes but no rendered picture suggests investigating
the Android media decoder and video codec. A 206 with `range_requests`
greater than zero confirms the byte-range path was exercised.

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

## Service-to-player integration test

`flutter test test/media_stream_integration_test.dart` exercises the
full **host-level** chain: service plugin → declared dependency call →
registered loopback source → player host → HTTP HEAD + byte-range GET →
diagnostic counters → revocation. It uses a fake video decoder that
performs actual HTTP requests so the test does not depend on a phone.
The remaining on-device acceptance test must still prove decoding.

## Android playback smoke test

Run `TESTAR_STREAM_ANDROID.bat` from the repository root on Windows.
It packages both service + addon, sets up `adb reverse`, and serves a
generated (ffmpeg) or user-supplied MP4 with HTTP Range. The visual
Media Bridge addon has a prefilled local URL, native playback, status,
and seek buttons. See `ANDROID_STREAM_SMOKE.md` for prerequisites,
expected HTTP 200/206 results, and physical-device acceptance criteria.

The Python byte-range server can be regression-tested locally with
`python tools/test_stream_smoke_server.py`. These tests do not replace
checking an actual Android codec/player.

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
