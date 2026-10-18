# AddKo network host API — TCP, UDP, WebSocket and DNS

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

## Datagram transport (UDP)

- Open: `local h = addko.net.udp.open({family="ipv4", bind="any", port=0})`.
- Query the local port: `addko.net.udp.info(h)` returns `{host, port}`.
- Send: `addko.net.udp.send(h, "127.0.0.1", 9000, {1, 2, 3})`.
- Receive: `addko.net.udp.receive(h, {timeout_ms=5000})` returns
  `{bytes, host, port, timed_out, closed}`.
- Close: `addko.net.udp.close(h)`.

The `network` permission permits ephemeral UDP sockets (`port=0`)
for outgoing datagrams and replies. A fixed-port UDP listener bound to
`any` additionally requires the `background` permission; binding to
`loopback` does not.

UDP packets are limited to 65507 bytes (IPv4 theoretical maximum);
actual network paths may support far smaller datagrams. The transport
does not fragment data automatically. Each plugin has at most 8 UDP sockets.

## WebSocket transport

- Connect: `addko.net.websocket.connect({url="wss://example.com/ws", headers={Authorization="Bearer token"}})`.
- Send UTF-8 text or byte arrays: `addko.net.websocket.send(handle, "hello")`.
- Receive: `addko.net.websocket.receive(handle, {timeout_ms=5000})`.
  This returns a text/binary message, a timeout, or a closed indicator.
- Close: `addko.net.websocket.close(handle)`.

WebSocket supports `ws:` and `wss:`. TLS uses normal certificate verification;
the host owns handshake headers. Each plugin gets at most 8 WebSockets.
Individual messages are capped at 64 KiB, incoming queues at 256 KiB.
Oversized messages or overflowing queues terminate the connection.

## DNS

`addko.net.dns.lookup("example.com", {family="ipv4"})` resolves IP
address strings (up to 16 results). `family` may be `ipv4`, `ipv6` or
`any`. Resolution requires the `network` permission.

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

## Still to implement

Multicast, proxy configuration, SMB/NFS, streaming HTTP handles, direct
stream-to-player pipelines, native gamepad support and high-throughput
binary transfer remain separate milestones. These transports do not
implement Torrent or any other specialized protocol in the core.
