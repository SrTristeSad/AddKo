-- Run at repository root: lua examples/torrent_video/tests/run.lua
local calls = {}
local ready = true
local fail_play = false
local results = {
    { id = "demo-hash", name = "Video de dominio publico", progress = 58, status = "buffering" },
}

addko = {
    plugins = {
        call = function(id, method, params)
            assert(id == "io.addko.luelement")
            calls[#calls + 1] = { method = method, params = params }
            if method == "health" then
                return { ready = ready }
            elseif method == "torrents" then
                return results
            elseif method == "play" then
                if fail_play then error("motor indisponível") end
                return { started = true, url = "http://127.0.0.1:65220/files/demo.mp4" }
            end
            error("método inesperado: " .. tostring(method))
        end,
    },
}

local plugin = dofile("examples/torrent_video/main.lua")
local function has_text(node, needle)
    if type(node) ~= "table" then return false end
    if node.type == "text" and tostring(node.text):find(needle, 1, true) then
        return true
    end
    if node.children then
        for _, child in ipairs(node.children) do
            if has_text(child, needle) then return true end
        end
    end
    if node.child and has_text(node.child, needle) then return true end
    return false
end
local function latest_play()
    for i = #calls, 1, -1 do
        if calls[i].method == "play" then return calls[i].params end
    end
end

local started = plugin.start()
assert(started.type == "page")
assert(started.title == "Vídeo por Torrent")
assert(has_text(started.body, "Motor não verificado"))
assert(#calls == 0) -- ENTRAR never initializes the native engine
-- Lua 5.5 serializa {} como objeto JSON. Buttons without positional args
-- must omit the args field so Flutter accepts the declarative page.
local function assert_button_arguments(node)
    if type(node) ~= "table" then return end
    if node.type == "button" then
        assert(node.args == nil or (type(node.args) == "table"
            and #node.args > 0), "button.args vazio deve ser omitido")
    end
    if node.children then
        for _, child in ipairs(node.children) do assert_button_arguments(child) end
    end
    if node.child then assert_button_arguments(node.child) end
end
assert_button_arguments(started.body)
assert(has_text(started.body, "AJKRETO5SBORCFLSLNVJMZF2XNSTJC3N"))
local function find_type(node, kind)
    if type(node) ~= "table" then return nil end
    if node.type == kind then return node end
    if node.children then
        for _, child in ipairs(node.children) do
            local found = find_type(child, kind)
            if found then return found end
        end
    end
    if node.child then return find_type(node.child, kind) end
end
local filled = find_type(started.body, "textarea")
assert(filled and filled.name == "uri")
assert(filled.value:find("AJKRETO5SBORCFLSLNVJMZF2XNSTJC3N", 1, true))
assert(filled.value:find("tracker.opentrackr.org", 1, true))
assert(latest_play() == nil) -- never launch torrent on page load

local checked = plugin.refresh()\nassert_button_arguments(checked.body)
assert(has_text(checked.body, "Motor conectado"))
assert(calls[#calls].method == "health")

local bundled = plugin.test_magnet()
assert(has_text(bundled.body, "Reprodução iniciada"))
assert(latest_play().uri == filled.value)
assert(latest_play().uri:find("urn:btih:AJKRETO5SBORCFLSLNVJMZF2XNSTJC3N", 1, true))

local before = #calls
local invalid = plugin.play({ uri = "file:///private/example.torrent" })
assert(has_text(invalid.body, "Use um magnet válido"))
assert(#calls == before) -- invalid input and rendering never wake up the motor

local magnet = "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567"
local played = plugin.play({ uri = magnet })
assert(has_text(played.body, "Reprodução iniciada"))
assert(latest_play().uri == magnet)

local http = plugin.play({ uri = "https://example.org/legal-video.torrent" })
assert(has_text(http.body, "Reprodução iniciada"))
assert(latest_play().uri == "https://example.org/legal-video.torrent")

local shown = plugin.list_torrents()\nassert_button_arguments(shown.body)
assert(has_text(shown.body, "Video de dominio publico"))
local existing = plugin.play_existing("demo-hash")
assert(has_text(existing.body, "Reprodução iniciada"))
assert(latest_play().id == "demo-hash")

fail_play = true
local failed = plugin.play({ uri = magnet })
assert(has_text(failed.body, "Falha ao reproduzir"))

ready = false
local offline = plugin.refresh()
assert(has_text(offline.body, "Motor não conectado"))

print("OK: 9 cenários do addon Video por Torrent")
