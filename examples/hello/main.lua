local Plugin = {}

function Plugin.start()
    addko.log("info", "Hello AddKo iniciou")
    addko.sleep(25)
    return {
        message = "Hello from Lua",
        platform = addko.platform.os,
        arch = addko.platform.arch,
    }
end

function Plugin.route(name, params)
    return {
        route = name,
        params = params or {},
    }
end

function Plugin.stop()
    addko.log("info", "Hello AddKo encerrou")
    return true
end

return Plugin
