-- Example composition: service plugin + native player + visual Lua addon.
local SOURCE_PLUGIN = "io.addko.example.media-source"
local App = {}
local url = "http://127.0.0.1:8765/test.mp4"
local message = "Teste Android: conecte o USB e execute TESTAR_STREAM_ANDROID.bat no Windows."

local function page()
    return {
        type = "page",
        title = "Media Bridge",
        body = {
            type = "column",
            children = {
                {type = "text", style = "headline", text = "Plugin + Player + Addon"},
                {type = "text", text = "O serviço fornece uma URL local temporária. O player lê o vídeo pelo núcleo, sem enviar bytes para Lua."},
                {
                    type = "input",
                    name = "url",
                    label = "URL de vídeo HTTP(S)",
                    hint = "https://example.org/video.mp4",
                    value = url,
                    max_length = 2048,
                },
                {
                    type = "button",
                    label = "Reproduzir",
                    action = "play",
                    submit_form = true,
                    variant = "primary",
                },
                {
                    type = "button", label = "Consultar player",
                    action = "player_status",
                },
                {
                    type = "button", label = "Avançar 5 segundos",
                    action = "seek_forward",
                },
                {
                    type = "button", label = "Voltar 5 segundos",
                    action = "seek_backward",
                },
                {type = "text", text = message},
            },
        },
    }
end

function App.start()
    return page()
end

function App.play(form)
    form = type(form) == "table" and form or {}
    url = tostring(form.url or url)
    if not url:match("^https?://") then
        message = "Informe um endereço HTTP(S) válido."
        return page()
    end

    local ok, result = pcall(function()
        local source = addko.plugins.call(SOURCE_PLUGIN, "open", {url = url})
        if type(source) ~= "table" or type(source.url) ~= "string" then
            error("Serviço não retornou um endereço reproduzível")
        end
        local started = addko.player.play(source.url)
        if started ~= true then error("O player recusou a reprodução.") end
        return true
    end)
    message = ok and "Reprodução solicitada ao player."
        or ("Falha: " .. tostring(result):sub(1, 240))
    return page()
end

function App.player_status()
    local info = addko.player.times() or {}
    local position = tonumber(info.position or 0) or 0
    local duration = tonumber(info.duration or 0) or 0
    local playing = addko.player.is_playing()
    message = string.format(
        "Player: %s | posição %.1fs / %.1fs",
        playing and "reproduzindo" or "parado/pausado", position, duration
    )
    return page()
end

local function seek(offset)
    local times = addko.player.times() or {}
    local position = tonumber(times.position or 0) or 0
    local duration = tonumber(times.duration or 0) or 0
    local next_position = math.max(0, position + offset)
    if duration > 0 then next_position = math.min(duration, next_position) end
    local ok, err = pcall(addko.player.seek, next_position)
    message = ok and string.format("Seek solicitado para %.1fs", next_position)
        or ("Falha no seek: " .. tostring(err))
    return page()
end

function App.seek_forward()
    return seek(5)
end

function App.seek_backward()
    return seek(-5)
end

return App
