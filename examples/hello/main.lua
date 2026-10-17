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
                    type = "image",
                    src = "asset:assets/logo.png",
                    alt = "Logo local do exemplo AddKo",
                    fit = "contain",
                    height = 120,
                },
                {
                    type = "text",
                    style = "headline",
                    align = "center",
                    text = "Hello from Lua",
                },
                {
                    type = "tabs",
                    tabs = {
                        {
                            label = "Início",
                            child = {
                                type = "column",
                                children = {
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
                                },
                            },
                        },
                        {
                            label = "Perfil",
                            child = {
                                type = "column",
                                children = {
                                    {
                                        type = "text",
                                        style = "title",
                                        text = profile.nickname,
                                    },
                                    {
                                        type = "text",
                                        text = "Tema: " .. profile.theme,
                                    },
                                    {
                                        type = "button",
                                        label = "Editar perfil",
                                        action = "profile_form",
                                        navigation = "push",
                                    },
                                },
                            },
                        },
                    },
                },
                {
                    type = "button",
                    label = "Abrir detalhes",
                    action = "details",
                    navigation = "push",
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
                    navigation = "pop",
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
                    navigation = "push",
                },
                {
                    type = "button",
                    label = "Voltar",
                    navigation = "pop",
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
                    navigation = "pop",
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
