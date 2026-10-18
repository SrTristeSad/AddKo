-- A reusable tool: no UI, video player or application-specific logic.
local Service = {}

function Service.start()
    return true
end

function Service.service(method, args)
    args = type(args) == "table" and args or {}
    if method == "open" then
        return addko.stream.register({
            url = args.url,
            headers = args.headers,
        })
    elseif method == "close" then
        return addko.stream.revoke(args.id)
    end
    error("Método desconhecido")
end

return Service
