# AddKo network host API — initial TCP client layer

The AddKo core provides generic transport primitives. Protocol-specific
implementations (torrent, WebDAV, FTP, game protocols, cloud APIs) belong
in Lua plugins, not in the Flutter/Dart core.

## Available

- `addko.http.request` and `addko.http.download` (HTTP/HTTPS).
- `addko.net.tcp.connect({host, port, tls = false, timeout_ms = 10000})`.
- `addko.net.tcp.write(handle, data, {timeout_ms = 10000})` accepts UTF-8 text or byte arrays.
- `addko.net.tcp.read(handle, {max_bytes = 8192, timeout_ms = 5000})` returns `{bytes, eof, timed_out}`.
- `addko.net.tcp.disconnect(handle)` closes an outbound socket.
- `addko.net.tcp.listen({host, port, on_message})` provides a line-framed loopback server for background plugins.
- `addko.net.tcp.close(handle)` closes a TCP client or an existing server.

All TCP clients require the `network` permission; server listening also needs
`background`. The host owns every socket and closes it when the Lua session ends.

## Sample Lua service

~~~lua
local M = {}
function M.service(method, args)
  if method ~= 'ping' then error('unknown method') end
  local handle = addko.net.tcp.connect({host = args.host, port = args.port})
  local ok, result = pcall(function()
    addko.net.tcp.write(handle, 'ping\n')
    return addko.net.tcp.read(handle, {max_bytes = 256})
  end)
  addko.net.tcp.disconnect(handle)
  if not ok then error(result) end
  return result
end
return M
~~~

## Transport limits

- 8 concurrent outbound TCP connections per plugin session.
- 64 KiB maximum bytes per `read` or `write`; 256 KiB incoming buffer per connection.
- Connection, send and receive timeouts are bounded from 1 to 60000 ms.
- TLS uses platform certificate verification (no insecure bypass switch).
- Binary payloads travel as Lua/JSON byte arrays, not direct native pointers.
- Reads may return fewer bytes than requested; `timed_out` is not EOF.
- This is a bounded general-purpose transport API, not a high-throughput byte-stream media pipeline.

## Not implemented by this milestone

WebSocket, UDP, multicast, DNS API, proxy settings, SMB/NFS, HTTP streaming
handles, native gamepad integration and direct streaming-to-player are distinct
follow-up capabilities. Do not mark these as implemented based on TCP alone.
