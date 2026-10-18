const String luaHostBootstrap = r'''
local json = {}
json.null = {}

local function json_escape(value)
    return value:gsub('[%z\1-\31\\"]', function(char)
        if char == '"' then return '\\"' end
        if char == '\\' then return '\\\\' end
        if char == '\b' then return '\\b' end
        if char == '\f' then return '\\f' end
        if char == '\n' then return '\\n' end
        if char == '\r' then return '\\r' end
        if char == '\t' then return '\\t' end
        return string.format('\\u%04x', string.byte(char))
    end)
end

local function json_is_array(value)
    local count = 0
    local max = 0
    for key, _ in pairs(value) do
        if type(key) ~= 'number' or key < 1 or key % 1 ~= 0 then
            return false, 0
        end
        count = count + 1
        if key > max then max = key end
    end
    if count == 0 then
        return false, 0
    end
    return count == max, max
end

local function json_encode_value(value, seen)
    if value == json.null or value == nil then
        return 'null'
    end

    local kind = type(value)
    if kind == 'boolean' then
        return value and 'true' or 'false'
    elseif kind == 'number' then
        if value ~= value or value == math.huge or value == -math.huge then
            error('cannot encode non-finite number')
        end
        return tostring(value)
    elseif kind == 'string' then
        return '"' .. json_escape(value) .. '"'
    elseif kind ~= 'table' then
        error('cannot encode JSON value of type ' .. kind)
    end

    if seen[value] then
        error('cannot encode recursive table')
    end
    seen[value] = true

    local array, length = json_is_array(value)
    local out = {}
    if array then
        for index = 1, length do
            out[#out + 1] = json_encode_value(value[index], seen)
        end
        seen[value] = nil
        return '[' .. table.concat(out, ',') .. ']'
    end

    for key, item in pairs(value) do
        if type(key) ~= 'string' then
            error('JSON object keys must be strings')
        end
        out[#out + 1] = '"' .. json_escape(key) .. '":' .. json_encode_value(item, seen)
    end
    table.sort(out)
    seen[value] = nil
    return '{' .. table.concat(out, ',') .. '}'
end

function json.encode(value)
    return json_encode_value(value, {})
end

local function json_skip_ws(source, index)
    while true do
        local byte = string.byte(source, index)
        if byte == 32 or byte == 9 or byte == 10 or byte == 13 then
            index = index + 1
        else
            return index
        end
    end
end

local function json_error(index, message)
    error('invalid JSON at byte ' .. tostring(index) .. ': ' .. message)
end

local json_parse_value

local function json_parse_string(source, index)
    index = index + 1
    local out = {}
    while index <= #source do
        local char = source:sub(index, index)
        if char == '"' then
            return table.concat(out), index + 1
        elseif char == '\\' then
            local esc = source:sub(index + 1, index + 1)
            if esc == '"' or esc == '\\' or esc == '/' then
                out[#out + 1] = esc
                index = index + 2
            elseif esc == 'b' then
                out[#out + 1] = '\b'
                index = index + 2
            elseif esc == 'f' then
                out[#out + 1] = '\f'
                index = index + 2
            elseif esc == 'n' then
                out[#out + 1] = '\n'
                index = index + 2
            elseif esc == 'r' then
                out[#out + 1] = '\r'
                index = index + 2
            elseif esc == 't' then
                out[#out + 1] = '\t'
                index = index + 2
            elseif esc == 'u' then
                local hex = source:sub(index + 2, index + 5)
                if #hex ~= 4 or not hex:match('^[0-9a-fA-F]+$') then
                    json_error(index, 'invalid unicode escape')
                end
                local code = tonumber(hex, 16)
                index = index + 6

                if code >= 0xD800 and code <= 0xDBFF and source:sub(index, index + 1) == '\\u' then
                    local low_hex = source:sub(index + 2, index + 5)
                    local low = tonumber(low_hex, 16)
                    if low and low >= 0xDC00 and low <= 0xDFFF then
                        code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
                        index = index + 6
                    end
                end

                out[#out + 1] = utf8.char(code)
            else
                json_error(index, 'invalid string escape')
            end
        else
            if string.byte(char) < 32 then
                json_error(index, 'control character in string')
            end
            out[#out + 1] = char
            index = index + 1
        end
    end
    json_error(index, 'unterminated string')
end

local function json_parse_number(source, index)
    local start = index
    local char = source:sub(index, index)
    if char == '-' then index = index + 1 end

    if source:sub(index, index) == '0' then
        index = index + 1
    else
        if not source:sub(index, index):match('%d') then
            json_error(index, 'invalid number')
        end
        while source:sub(index, index):match('%d') do
            index = index + 1
        end
    end

    if source:sub(index, index) == '.' then
        index = index + 1
        if not source:sub(index, index):match('%d') then
            json_error(index, 'invalid fraction')
        end
        while source:sub(index, index):match('%d') do
            index = index + 1
        end
    end

    local exponent = source:sub(index, index)
    if exponent == 'e' or exponent == 'E' then
        index = index + 1
        local sign = source:sub(index, index)
        if sign == '+' or sign == '-' then index = index + 1 end
        if not source:sub(index, index):match('%d') then
            json_error(index, 'invalid exponent')
        end
        while source:sub(index, index):match('%d') do
            index = index + 1
        end
    end

    local number = tonumber(source:sub(start, index - 1))
    if number == nil then json_error(start, 'invalid number') end
    return number, index
end

local function json_parse_array(source, index)
    local result = {}
    index = json_skip_ws(source, index + 1)
    if source:sub(index, index) == ']' then
        return result, index + 1
    end

    while true do
        local value
        value, index = json_parse_value(source, index)
        result[#result + 1] = value
        index = json_skip_ws(source, index)
        local char = source:sub(index, index)
        if char == ']' then
            return result, index + 1
        elseif char ~= ',' then
            json_error(index, 'expected comma or closing bracket')
        end
        index = json_skip_ws(source, index + 1)
    end
end

local function json_parse_object(source, index)
    local result = {}
    index = json_skip_ws(source, index + 1)
    if source:sub(index, index) == '}' then
        return result, index + 1
    end

    while true do
        if source:sub(index, index) ~= '"' then
            json_error(index, 'expected object key')
        end
        local key
        key, index = json_parse_string(source, index)
        index = json_skip_ws(source, index)
        if source:sub(index, index) ~= ':' then
            json_error(index, 'expected colon')
        end
        index = json_skip_ws(source, index + 1)
        local value
        value, index = json_parse_value(source, index)
        result[key] = value
        index = json_skip_ws(source, index)
        local char = source:sub(index, index)
        if char == '}' then
            return result, index + 1
        elseif char ~= ',' then
            json_error(index, 'expected comma or closing brace')
        end
        index = json_skip_ws(source, index + 1)
    end
end

json_parse_value = function(source, index)
    index = json_skip_ws(source, index)
    local char = source:sub(index, index)
    if char == '"' then
        return json_parse_string(source, index)
    elseif char == '{' then
        return json_parse_object(source, index)
    elseif char == '[' then
        return json_parse_array(source, index)
    elseif char == '-' or char:match('%d') then
        return json_parse_number(source, index)
    elseif source:sub(index, index + 3) == 'true' then
        return true, index + 4
    elseif source:sub(index, index + 4) == 'false' then
        return false, index + 5
    elseif source:sub(index, index + 3) == 'null' then
        return json.null, index + 4
    end
    json_error(index, 'unexpected token')
end

function json.decode(source)
    if type(source) ~= 'string' then
        error('json.decode expects string')
    end
    local value, index = json_parse_value(source, 1)
    index = json_skip_ws(source, index)
    if index <= #source then
        json_error(index, 'trailing data')
    end
    return value
end

local calls = {}
local callbacks = {}
local next_call_id = 0
local next_callback_id = 0
local plugin = nil
local host_config = nil

local function safe_relative(value)
    local relative = tostring(value or ''):gsub('\\', '/')
    if relative == '' then return '' end
    if relative:sub(1, 1) == '/' or relative:find('..', 1, true) then
        error('unsafe relative path')
    end
    return relative
end

local function join_root(root, relative)
    relative = safe_relative(relative)
    if relative == '' then return root end
    root = tostring(root):gsub('/+$', '')
    return root .. '/' .. relative
end

local function host_request(op, args)
    local reply = coroutine.yield({
        kind = 'host',
        op = op,
        args = args or {},
    })

    if type(reply) ~= 'table' then
        error('invalid host reply for ' .. tostring(op))
    end
    if reply.ok ~= true then
        error(tostring(reply.error or ('host operation failed: ' .. tostring(op))))
    end
    if reply.value == json.null then
        return nil
    end
    return reply.value
end

local function register_callback(callback)
    if type(callback) ~= 'function' then
        error('callback must be a function')
    end
    next_callback_id = next_callback_id + 1
    callbacks[next_callback_id] = callback
    return next_callback_id
end

local function build_host(config)
    host_config = config

    addko = {
        json = json,
        platform = config.platform or {},
        locale = config.locale or {},
        paths = {},
        fs = {},
        http = {},
        stream = {},
        process = {},
        net = { tcp = {}, udp = {}, websocket = {}, dns = {} },
        ui = {},
        player = {},
    }

    function addko.log(level, message)
        return host_request('log', { level = level, message = message })
    end

    function addko.sleep(milliseconds)
        return host_request('sleep', { milliseconds = milliseconds })
    end

    function addko.paths.plugin(relative)
        return join_root(config.plugin_root, relative)
    end

    function addko.paths.data(relative)
        return join_root(config.data_root, relative)
    end

    function addko.fs.exists(path)
        return host_request('fs.exists', { path = path })
    end

    function addko.fs.mkdirp(path)
        return host_request('fs.mkdirp', { path = path })
    end
    addko.fs.mkdirs = addko.fs.mkdirp
    addko.fs.create_directories = addko.fs.mkdirp

    function addko.fs.write_text(path, text)
        return host_request('fs.write_text', { path = path, text = text })
    end

    function addko.fs.write_bytes(path, bytes)
        return host_request('fs.write_bytes', { path = path, bytes = bytes })
    end

    function addko.fs.write(path, value, options)
        options = options or {}
        if options.binary == true then
            return addko.fs.write_bytes(path, value)
        end
        return addko.fs.write_text(path, value)
    end

    function addko.fs.set_executable(path, executable)
        return host_request('fs.set_executable', { path = path, executable = executable ~= false })
    end

    function addko.fs.chmod(path, mode)
        return host_request('fs.chmod', { path = path, mode = mode })
    end

    function addko.http.request(request)
        return host_request('http.request', request)
    end

    function addko.http.download(request)
        return host_request('http.download', request)
    end

    function addko.stream.register(options)
        return host_request('stream.register', options or {})
    end

    function addko.stream.revoke(id)
        return host_request('stream.revoke', { id = id })
    end

    function addko.stream.stats(id)
        return host_request('stream.stats', { id = id })
    end

    function addko.process.spawn(options)
        return host_request('process.spawn', options)
    end

    function addko.process.stop(handle)
        return host_request('process.stop', { handle = handle })
    end

    function addko.net.tcp.listen(options)
        options = options or {}
        local callback_id = register_callback(options.on_message)
        return host_request('net.tcp.listen', {
            host = options.host,
            port = options.port,
            framing = options.framing,
            callback_id = callback_id,
        })
    end
    addko.net.tcp.listen_lines = addko.net.tcp.listen

    function addko.net.tcp.connect(options)
        return host_request('net.tcp.connect', options or {})
    end

    function addko.net.tcp.write(handle, data, options)
        options = options or {}
        return host_request('net.tcp.write', {
            handle = handle, data = data, timeout_ms = options.timeout_ms,
        })
    end

    function addko.net.tcp.read(handle, options)
        options = options or {}
        return host_request('net.tcp.read', {
            handle = handle,
            max_bytes = options.max_bytes,
            timeout_ms = options.timeout_ms,
        })
    end

    function addko.net.tcp.disconnect(handle)
        return host_request('net.tcp.disconnect', { handle = handle })
    end

    function addko.net.tcp.close(handle)
        return host_request('net.tcp.close', { handle = handle })
    end

    function addko.net.dns.lookup(host, options)
        options = options or {}
        return host_request('net.dns.lookup', {
            host = host, family = options.family, timeout_ms = options.timeout_ms,
        })
    end

    function addko.net.udp.open(options)
        return host_request('net.udp.open', options or {})
    end

    function addko.net.udp.info(handle)
        return host_request('net.udp.info', {handle = handle})
    end

    function addko.net.udp.send(handle, host, port, data, options)
        options = options or {}
        return host_request('net.udp.send', {
            handle = handle, host = host, port = port,
            data = data, timeout_ms = options.timeout_ms,
        })
    end

    function addko.net.udp.receive(handle, options)
        options = options or {}
        return host_request('net.udp.receive', {
            handle = handle, timeout_ms = options.timeout_ms,
        })
    end

    function addko.net.udp.close(handle)
        return host_request('net.udp.close', { handle = handle })
    end

    function addko.net.websocket.connect(options)
        return host_request('net.websocket.connect', options or {})
    end

    function addko.net.websocket.send(handle, data)
        return host_request('net.websocket.send', { handle = handle, data = data })
    end

    function addko.net.websocket.receive(handle, options)
        options = options or {}
        return host_request('net.websocket.receive', {
            handle = handle, timeout_ms = options.timeout_ms,
        })
    end

    function addko.net.websocket.close(handle)
        return host_request('net.websocket.close', { handle = handle })
    end

    function addko.ui.refresh()
        return host_request('ui.refresh', {})
    end

    function addko.ui.navigate(route)
        return host_request('ui.navigate', { route = route })
    end

    function addko.ui.notify(options)
        return host_request('ui.notify', options)
    end

    function addko.ui.input(options)
        return host_request('ui.input', options)
    end

    function addko.ui.alert(options)
        return host_request('ui.alert', options)
    end

    function addko.ui.confirm(options)
        return host_request('ui.confirm', options)
    end

    function addko.ui.select(options)
        return host_request('ui.select', options)
    end

    function addko.ui.pick_file(options)
        return host_request('ui.pick_file', options)
    end

    function addko.ui.progress_create(options)
        return host_request('ui.progress_create', options)
    end

    function addko.ui.progress_update(handle, options)
        return host_request('ui.progress_update', { handle = handle, options = options })
    end

    function addko.ui.progress_is_cancelled(handle)
        return host_request('ui.progress_is_cancelled', { handle = handle })
    end

    function addko.ui.progress_close(handle)
        return host_request('ui.progress_close', { handle = handle })
    end

    function addko.player.play(item)
        return host_request('player.play', { item = item })
    end

    function addko.player.current_url()
        return host_request('player.current_url', {})
    end

    function addko.player.is_playing()
        return host_request('player.is_playing', {})
    end

    function addko.player.is_paused()
        return host_request('player.is_paused', {})
    end

    function addko.player.times()
        return host_request('player.times', {})
    end

    function addko.player.seek(seconds)
        return host_request('player.seek', { seconds = seconds })
    end

    function addko.player.subtitles()
        return host_request('player.subtitles', {})
    end

    function addko.player.set_subtitles(urls)
        return host_request('player.set_subtitles', { urls = urls })
    end
end

local function step_call(call_id, ...)
    local co = calls[call_id]
    if co == nil then
        return json.encode({ state = 'error', error = 'unknown call id' })
    end

    local ok, value = coroutine.resume(co, ...)
    if not ok then
        calls[call_id] = nil
        return json.encode({ state = 'error', error = tostring(value) })
    end

    if coroutine.status(co) == 'dead' then
        calls[call_id] = nil
        return json.encode({ state = 'done', value = value })
    end

    if type(value) ~= 'table' or value.kind ~= 'host' or type(value.op) ~= 'string' then
        calls[call_id] = nil
        return json.encode({ state = 'error', error = 'plugin yielded an invalid host request' })
    end

    return json.encode({
        state = 'yield',
        call_id = call_id,
        op = value.op,
        args = value.args or {},
    })
end

local function new_call(fn, args)
    next_call_id = next_call_id + 1
    local call_id = next_call_id
    local co = coroutine.create(function()
        return fn(table.unpack(args or {}))
    end)
    calls[call_id] = co
    return step_call(call_id)
end

function __addko_bootstrap(config_json)
    local config = json.decode(config_json)
    build_host(config)
    return true
end

function __addko_load_plugin(module_name)
    local loaded = require(module_name)
    if type(loaded) ~= 'table' then
        error('plugin entrypoint must return a table')
    end
    plugin = loaded
    return true
end

function __addko_start_plugin_call(method, args_json)
    if type(plugin) ~= 'table' then
        return json.encode({ state = 'error', error = 'plugin is not loaded' })
    end
    local fn = plugin[method]
    if type(fn) ~= 'function' then
        return json.encode({ state = 'error', error = 'plugin method not found: ' .. tostring(method) })
    end
    local args = json.decode(args_json)
    return new_call(fn, args)
end

function __addko_start_event(callback_id, args_json)
    local callback = callbacks[tonumber(callback_id)]
    if type(callback) ~= 'function' then
        return json.encode({ state = 'error', error = 'callback not found: ' .. tostring(callback_id) })
    end
    local args = json.decode(args_json)
    return new_call(callback, args)
end

function __addko_resume_call(call_id, reply_json)
    local reply = json.decode(reply_json)
    return step_call(tonumber(call_id), reply)
end

function __addko_shutdown()
    calls = {}
    callbacks = {}
    plugin = nil
    return true
end
''';
