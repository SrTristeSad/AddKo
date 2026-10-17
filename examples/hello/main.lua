local Plugin = {}
local count = 0
local profile = {
    nickname = "Alex",
    remember = false,
    theme = "Escuro",
}

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
                    label = "Editar perfil",
                    action = "profile_form",
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

function Plugin.profile_form()
    return {
        type = "page",
        title = "Formulário Lua",
        body = {
            type = "column",
            children = {
                {
                    type = "input",
                    name = "nickname",
                    label = "Nome",
                    hint = "Como devemos chamar você?",
                    value = profile.nickname,
                    max_length = 80,
                },
                {
                    type = "switch",
                    name = "remember",
                    label = "Lembrar nesta sessão",
                    value = profile.remember,
                },
                {
                    type = "select",
                    name = "theme",
                    label = "Tema preferido",
                    options = { "Escuro", "Claro", "Sistema" },
                    value = profile.theme,
                },
                {
                    type = "textarea",
                    name = "notes",
                    label = "Notas",
                    hint = "Campo de texto longo controlado pelo Flutter",
                    value = "",
                    max_length = 500,
                },
                {
                    type = "button",
                    variant = "primary",
                    label = "Salvar formulário",
                    action = "save_profile",
                    submit_form = true,
                },
                {
                    type = "button",
                    label = "Cancelar",
                    action = "home",
                },
            },
        },
    }
end

function Plugin.save_profile(form)
    profile.nickname = tostring(form.nickname or "")
    profile.remember = form.remember == true
    profile.theme = tostring(form.theme or "Escuro")

    return {
        type = "page",
        title = "Salvo pelo Lua",
        body = {
            type = "column",
            children = {
                {
                    type = "text",
                    style = "title",
                    text = "Olá, " .. profile.nickname .. "!",
                },
                {
                    type = "text",
                    text = "Tema: " .. profile.theme .. " • lembrar: " .. tostring(profile.remember),
                },
                {
                    type = "button",
                    label = "Voltar ao início",
                    action = "home",
                },
            },
        },
    }
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
                    text = "O Flutter valida e renderiza a árvore declarativa; o estado continua dentro da sessão Lua.",
                },
                {
                    type = "search",
                    name = "query",
                    label = "Busca de demonstração",
                    hint = "Digite e pressione buscar",
                    action = "search",
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

function Plugin.search(form)
    local query = tostring(form.query or "")
    return {
        type = "page",
        title = "Busca",
        body = {
            type = "column",
            children = {
                {
                    type = "text",
                    style = "title",
                    text = "Você buscou: " .. query,
                },
                {
                    type = "button",
                    label = "Voltar aos detalhes",
                    action = "details",
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
