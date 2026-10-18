# AddKo — Android MP4 streaming smoke test (offline / no torrents)

This test verifies that **an actual Android device** can play and seek a
progressive MP4 using AddKo's Lua service, HTTP streaming bridge, and native
player. It does not depend on Elementum, torrent peers, or public sample sites.

## Prerequisites

- Windows with Python 3 and Android platform-tools (`adb` on PATH).
- USB debugging enabled on a real Android phone, authorized in `adb devices`.
- Recent AddKo ARM64 APK built from `main`, installed on the device.
- Either `ffmpeg` on PATH (to generate a small H.264 test MP4), **or**
  a local, lawfully obtained H.264 MP4 with progressive playback.
- No Docker and no GitHub Actions.

## Start everything

1. Connect the device via USB and authorize USB debugging.
2. In the AddKo repository folder run `TESTAR_STREAM_ANDROID.bat`.
   Or drag a local MP4 onto this batch file to serve your own video.
3. The batch file creates two packages in `dist/` and runs
   `adb reverse tcp:8765 tcp:8765`.
4. Leave the batch window running. It serves an HTTP MP4 with proper
   `Range` and `HEAD` responses on your Windows computer, but only binds
   to `127.0.0.1`.
5. On the phone install `dist/MediaSource-1.0.0.addko` first. This is
   a **service plugin**, with `network` permission; it does not appear as
   a standalone tile in the launcher.
6. Install `dist/MediaBridge-1.0.0.addko`. This is the **visual addon**,
   requiring `media` and depending on the MediaSource service.
7. Open Media Bridge, then use the prefilled
   `http://127.0.0.1:8765/test.mp4` and tap **Reproduzir**.

## Acceptance criteria

1. The player surface opens, initializes and displays the moving H.264
   test pattern, with a nonzero duration.
2. Pause and resume work on the native player UI.
3. Seek forward/backward using the player timeline. Return to the addon
   and tap "Avançar 5 segundos" or "Voltar 5 segundos" for Lua-driven
   seek. "Consultar player" displays playback state and times.
4. The Windows server console logs `GET` and `Range=bytes=...` requests.
   The native player may use different seek patterns depending on codec
   and platform.
5. The addon can be closed without a crash; the service can be removed
   safely after stopping playback.

**Do not mark Android playback as verified** until all checks are performed
on the device. The pure-Python HTTP tests and Dart host tests cannot prove
that Android's player decoder renders video.

## Read the diagnostic buttons

Both sample addons now expose transport diagnostics without sending media
bytes through Lua. After a playback attempt:

- Media Bridge: tap **Diagnosticar conexão** to see HTTP status, request
  count, byte-range requests, forwarded bytes, active requests and failures.
- VideoTorrent (version 0.1.4): tap **Diagnosticar streaming** to ask the
  Luelement service for the same network measurements. Install a Luelement
  revision that exposes the `stream_stats` service method.
- If the source shows no requests, verify the local URL and permissions.
  If requests arrive with HTTP 206 and nonzero bytes but the player is
  black or fails, investigate codecs and the Android player backend.
- This does **not** prove BitTorrent peers, trackers, buffering and native
  engine startup; those require the separate Luelement smoke test.

## Troubleshooting

- If `adb reverse` fails: use a real device with USB debugging enabled,
  make sure `adb devices` lists it as "device", not "unauthorized".
- If the bat reports missing `ffmpeg`, run it with an MP4 argument, e.g.
  `TESTAR_STREAM_ANDROID.bat "C:\Videos\teste.mp4"`.
- If the addon refuses to open: confirm both `.addko` files are installed,
  and that the service is installed *before* the visual addon.
- If video shows 404/connection refused: keep the batch console open,
  check `adb reverse --list` and try `curl -I http://127.0.0.1:8765/test.mp4`
  on your Windows computer.
- If `HTTP 206` never appears in server logs: seeking may not trigger a
  separate range request for tiny already-buffered files. Use a longer MP4.
- If video fails with an initialization error but HTTP works, inspect the
  on-device player codec support and Android logs, not the torrent engine.
- If a preview APK from before the streaming-bridge commit is installed,
  rebuild AddKo with `BUILD_ANDROID.bat` and install the new APK.

## Desktop validation commands

From the project root:

`python tools/test_stream_smoke_server.py`

`python tools/build_stream_smoke_examples.py`

With the server running:

`curl -I http://127.0.0.1:8765/test.mp4`

`curl -H "Range: bytes=4096-8191" -I http://127.0.0.1:8765/test.mp4`

Expected: HTTP 200 for HEAD and 206 for byte ranges, with a
`Content-Range` response header.

For Dart host tests, when Flutter is installed:

`flutter test test/media_stream_proxy_test.dart`

No assertion about real Android playback is possible without an Android
device or emulator.

## Luelement bridge (separate service)

Once this works, the Luelement service can register the Elementum
`http://127.0.0.1:65220/files/...` URL using the very same
`addko.stream.register` transport. Only Elementum/libtorrent handles
BitTorrent; AddKo handles general HTTP media transport and the player.
