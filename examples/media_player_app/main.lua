-- Example composition: service plugin + native player + visual Lua addon.
local SOURCE_PLUGIN = "io.addko.example.media-source"
local App = {}
local url = ""
local message = "Informe um arquivo de vídeo HTTP(S) com suporte a Range."

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
        return addko.player.play(source.url)
    end)
    message = ok and "Reprodução solicitada ao player."
        or ("Falha: " .. tostring(result):sub(1, 240))
    return page()
end

return App
