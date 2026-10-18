-- A reusable tool: no UI, video player or application-specific logic.
local Service = {}
local active_id = nil

function Service.start()
    return true
end

function Service.service(method, args)
    args = type(args) == "table" and args or {}
    if method == "open" then
        -- This demo keeps only one active source; a real service can manage
        -- multiple registered sources and revoke each when no longer needed.
        if active_id then
            addko.stream.revoke(active_id)
            active_id = nil
        end
        local source = addko.stream.register({
            url = args.url,
            headers = args.headers,
        })
        active_id = source.id
        return source
    elseif method == "close" then
        local id = args.id or active_id
        if id == nil then return false end
        local revoked = addko.stream.revoke(id)
        if id == active_id then active_id = nil end
        return revoked
    end
    error("Método desconhecido")
end

function Service.stop()
    if active_id then
        addko.stream.revoke(active_id)
        active_id = nil
    end
    return true
end

return Service
