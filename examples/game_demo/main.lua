local Plugin = {}

local player = {
    x = 160,
    y = 90,
    speed = 110,
}

local function pressed(input, name)
    for _, key in ipairs(input.keys or {}) do
        if key == name then
            return true
        end
    end
    return false
end

function Plugin.start()
    return {
        type = "game",
        title = "AddKo Game Demo",
        width = 320,
        height = 180,
        fps = 30,
        frame_action = "frame",
        pixel_art = true,
    }
end

function Plugin.frame(dt, input)
    local dx = 0
    local dy = 0

    if pressed(input, "arrowLeft") or pressed(input, "keyA") then
        dx = dx - 1
    end
    if pressed(input, "arrowRight") or pressed(input, "keyD") then
        dx = dx + 1
    end
    if pressed(input, "arrowUp") or pressed(input, "keyW") then
        dy = dy - 1
    end
    if pressed(input, "arrowDown") or pressed(input, "keyS") then
        dy = dy + 1
    end

    player.x = math.max(10, math.min(310, player.x + dx * player.speed * dt))
    player.y = math.max(10, math.min(170, player.y + dy * player.speed * dt))

    local pointer = (input.pointers or {})[1]
    if pointer then
        player.x = pointer.x
        player.y = pointer.y
    end

    return {
        type = "game_frame",
        clear = "#10151F",
        commands = {
            {
                type = "text",
                x = 12,
                y = 10,
                text = "Lua controla este frame",
                size = 16,
                color = "#FFFFFF",
            },
            {
                type = "text",
                x = 12,
                y = 32,
                text = "Setas/WASD ou toque",
                size = 12,
                color = "#9FB3C8",
            },
            {
                type = "line",
                x1 = 0,
                y1 = 55,
                x2 = 320,
                y2 = 55,
                width = 1,
                color = "#334155",
            },
            {
                type = "rect",
                x = player.x - 10,
                y = player.y - 10,
                width = 20,
                height = 20,
                color = "#38BDF8",
            },
            {
                type = "circle",
                x = player.x,
                y = player.y,
                radius = 4,
                color = "#FFFFFF",
            },
        },
    }
end

function Plugin.stop()
    return true
end

return Plugin
