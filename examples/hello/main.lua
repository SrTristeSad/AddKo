local Plugin = {}
local count = 0

local function page()
    return {
        type = "page",
        title = "Hello AddKo",
        body = {
            type = "column",
            children = {
                {
                    type = "text",
                    style = "headline",
                    text = "Hello from Lua",
                },
                {
                    type = "text",
                    text = "Runtime: " .. tostring(addko.platform.os) .. " / " .. tostring(addko.platform.arch),
                },
                {
                    type = "card",
                    child = {
                        type = "text",
                        align = "center",
                        text = "Cliques nesta sessão: " .. tostring(count),
                    },
                },
                {
                    type = "button",
                    variant = "primary",
                    label = "Somar +1",
                    action = "increment",
                },
                {
                    type = "button",
                    label = "Abrir detalhes",
                    action = "details",
                },
            },
        },
    }
end

function Plugin.start()
    addko.log("info", "Hello AddKo iniciou")
    addko.sleep(25)
    return page()
end

function Plugin.increment()
    count = count + 1
    return page()
end

function Plugin.details()
    return {
        type = "page",
        title = "Detalhes",
        body = {
            type = "column",
            children = {
                {
                    type = "text",
                    style = "title",
                    text = "A interface desta tela veio do main.lua.",
                },
                {
                    type = "text",
                    text = "O Flutter apenas valida e renderiza a árvore declarativa; o estado continua dentro da sessão Lua.",
                },
                {
                    type = "button",
                    label = "Voltar",
                    action = "home",
                },
            },
        },
    }
end

function Plugin.home()
    return page()
end

function Plugin.route(name, params)
    if name == "details" then
        return Plugin.details()
    end
    return page()
end

function Plugin.stop()
    addko.log("info", "Hello AddKo encerrou")
    return true
end

return Plugin
