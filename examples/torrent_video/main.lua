-- AddKo example: video playback delegated entirely to Luelement.
-- This plugin deliberately has no network/media permissions of its own.
local LUELEMENT = "io.addko.luelement"
local Plugin = {}

local last_uri = ""
local status_message = nil
local listed_torrents = nil

local function text(value, style)
    return {
        type = "text",
        text = tostring(value or ""),
        style = style or "body",
    }
end

local function button(label, action, options)
    options = options or {}
    return {
        type = "button",
        label = label,
        action = action,
        args = options.args or {},
        submit_form = options.submit_form == true,
        variant = options.variant or "tonal",
        enabled = options.enabled ~= false,
    }
end

local function card(children)
    return {
        type = "card",
        child = {
            type = "column",
            children = children,
        },
    }
end

local function truncate(value, limit)
    local value_text = tostring(value or "")
    if #value_text > limit then
        return value_text:sub(1, limit - 3) .. "..."
    end
    return value_text
end

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function validate_uri(raw)
    local uri = trim(raw)
    if uri == "" then
        return nil, "Cole um magnet ou URL de arquivo .torrent."
    end
    if #uri > 16384 or uri:find("[%c]") then
        return nil, "O endereço é muito longo ou contém caracteres inválidos."
    end
    if uri:match("^magnet:%?") then
        if not uri:find("xt=urn:btih:", 1, true) then
            return nil, "O magnet precisa conter o identificador xt=urn:btih:."
        end
        return uri
    end
    if uri:match("^https?://") and (uri:match("%.torrent$") or uri:match("%.torrent[?#]")) then
        return uri
    end
    return nil, "Use um magnet válido ou um endereço HTTP(S) terminado em .torrent."
end

local function service(method, payload)
    return addko.plugins.call(LUELEMENT, method, payload or {})
end

local function status()
    local ok, result = pcall(service, "health", {})
    if not ok then
        return false, "Não foi possível consultar o Luelement: " .. truncate(result, 260)
    end
    if type(result) == "table" and result.ready == true then
        return true, "Luelement e motor Elementum prontos."
    end
    return false, "Motor indisponível. Instale e abra o Luelement; no Android, instale também o Luelement Engine."
end

local function render()
    local ready, engine_message = status()
    local children = {
        text("Vídeo por Torrent", "headline"),
        text("Exemplo de addon Lua que usa o Luelement como serviço, sem implementar BitTorrent no AddKo.", "caption"),
        card({
            text(ready and "Motor conectado" or "Motor não conectado", "title"),
            text(engine_message, "caption"),
            button("Verificar novamente", "refresh"),
        }),
        { type = "divider" },
        text("Abrir vídeo", "title"),
        {
            type = "textarea",
            name = "uri",
            label = "Magnet ou URL .torrent",
            hint = "magnet:?xt=urn:btih:...",
            value = last_uri,
            max_length = 16384,
        },
        button("Reproduzir", "play", { submit_form = true, variant = "primary" }),
        button("Torrents no Luelement", "list_torrents"),
        text("Utilize somente torrents de vídeos que você tem direito de acessar.", "caption"),
    }

    if status_message and status_message ~= "" then
        children[#children + 1] = card({ text(status_message, "body") })
    end

    if listed_torrents ~= nil then
        children[#children + 1] = { type = "divider" }
        children[#children + 1] = text("Torrents disponíveis", "title")
        if #listed_torrents == 0 then
            children[#children + 1] = text("Nenhum torrent na sessão do Luelement.", "caption")
        else
            local count = math.min(#listed_torrents, 12)
            for i = 1, count do
                local torrent = listed_torrents[i]
                if type(torrent) == "table" then
                    local id = tostring(torrent.id or torrent.info_hash or "")
                    local name = truncate(torrent.name or torrent.title or id, 180)
                    local progress = tonumber(torrent.progress or 0) or 0
                    progress = math.max(0, math.min(100, progress))
                    children[#children + 1] = card({
                        text(name, "title"),
                        text(string.format("%.1f%% — %s", progress, truncate(torrent.status, 60)), "caption"),
                        button("Reproduzir este torrent", "play_existing", {
                            args = { id },
                            variant = "primary",
                            enabled = id ~= "" and #id <= 256,
                        }),
                    })
                end
            end
            if #listed_torrents > count then
                children[#children + 1] = text("Mostrando os primeiros " .. count .. " torrents.", "caption")
            end
        end
    end

    return {
        type = "page",
        title = "Vídeo por Torrent",
        body = { type = "column", children = children },
    }
end

function Plugin.start()
    return render()
end

function Plugin.refresh()
    status_message = nil
    return render()
end

function Plugin.play(form)
    form = type(form) == "table" and form or {}
    local uri, error_message = validate_uri(form.uri)
    if not uri then
        status_message = error_message
        return render()
    end
    last_uri = uri
    local ok, result = pcall(service, "play", { uri = uri })
    if not ok then
        status_message = "Falha ao reproduzir: " .. truncate(result, 320)
    elseif type(result) == "table" and result.started == true then
        status_message = "Reprodução iniciada no player do AddKo."
    else
        status_message = "O Luelement não confirmou o início da reprodução."
    end
    return render()
end

function Plugin.list_torrents()
    local ok, result = pcall(service, "torrents", {})
    if ok and type(result) == "table" then
        listed_torrents = result
        status_message = "Lista atualizada."
    else
        listed_torrents = nil
        status_message = "Não foi possível listar os torrents: " .. truncate(result, 250)
    end
    return render()
end

function Plugin.play_existing(id)
    id = tostring(id or "")
    if id == "" or #id > 256 then
        status_message = "Identificador de torrent inválido."
        return render()
    end
    local ok, result = pcall(service, "play", { id = id })
    if not ok then
        status_message = "Falha ao reproduzir: " .. truncate(result, 320)
    elseif type(result) == "table" and result.started == true then
        status_message = "Reprodução iniciada no player do AddKo."
    else
        status_message = "O Luelement não confirmou o início da reprodução."
    end
    return render()
end

return Plugin
