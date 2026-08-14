local dandelion = require("dandelion")

function _config()
    ---@type Usagi.Config
    return { name = "Dandelion Playground", pause_menu = false }
end

local PARTICLE_NAMES = dandelion.Particles()
for _, v in pairs(dandelion.Emitters()) do
    table.insert(PARTICLE_NAMES, v)
end
table.sort(PARTICLE_NAMES)
local MAX_RESULTS = 8


function _init()
    Selected_Particle = PARTICLE_NAMES[1]
    Search_Open = false
    Search_Text = ""
    Search_Results = nil
    Selected_Result_Index = 1
    Hide_UI = false
end

local counter = 1

local function get_pressed_char()
    for i = input.KEY_A, input.KEY_Z do
        if input.key_pressed(i) then
            return string.char(i + 32) -- converts uppercase to lowercase
        end
    end
    for i = input.KEY_0, input.KEY_9 do
        if input.key_pressed(i) then
            return string.char(i)
        end
    end
    if input.key_pressed(input.KEY_PERIOD) then
        return "."
    end
    if input.key_pressed(input.KEY_MINUS) then
        if input.key_held(input.KEY_LSHIFT) or input.key_held(input.KEY_RSHIFT) then 
            return "_"
        else
            return "-"
        end
    end
    return nil
end

local next_backspace = 1

local last_spawned = nil

function _update(dt)
    if input.key_pressed(input.KEY_F3) then
        Hide_UI = not Hide_UI
    end

    if input.key_pressed(input.KEY_SPACE) or input.key_pressed(input.KEY_ENTER) then
        if Search_Open then
            Search_Open = false
            Selected_Particle = Search_Results[Selected_Result_Index]
        else
            Search_Open = true
            Selected_Result_Index = 1
            Search_Text = ""
            Search_Results = nil
        end
    end

    if Search_Open then
        local char = get_pressed_char()
        local updated = false
        if char then
            Search_Text = Search_Text .. char
            updated = true
        else
            if input.key_pressed(input.KEY_BACKSPACE) then
                if input.key_held(input.KEY_LCTRL) then
                    Search_Text = ""
                    updated = true
                else
                    next_backspace = usagi.elapsed + 0.5
                    Search_Text = string.sub(Search_Text, 1, #Search_Text - 1)
                    updated = true
                end
            end
            if input.key_held(input.KEY_BACKSPACE) and #Search_Text > 0 and usagi.elapsed > next_backspace then
                next_backspace = usagi.elapsed + 0.05
                Search_Text = string.sub(Search_Text, 1, #Search_Text - 1)
                updated = true
            end
        end

        if updated or not Search_Results then
            Search_Results = {}
            local i = 1
            while #Search_Results < MAX_RESULTS and i <= #PARTICLE_NAMES do
                local name = PARTICLE_NAMES[i]
                if string.match(name, Search_Text) then
                    table.insert(Search_Results, name)
                end
                i += 1
            end
            Selected_Result_Index = util.clamp(Selected_Result_Index, 1, #Search_Results)
        end

        if input.key_pressed(input.KEY_UP) then
            if Selected_Result_Index == 1 then
                Selected_Result_Index = #Search_Results
            else
                Selected_Result_Index -= 1
            end
        end
        if input.key_pressed(input.KEY_DOWN) then
            if Selected_Result_Index == #Search_Results then
                Selected_Result_Index = 1
            else
                Selected_Result_Index += 1
            end
        end
    else
        if input.key_pressed(input.KEY_C) then
            dandelion.ClearAll()
        end
        if input.key_pressed(input.KEY_K) then
            dandelion.Kill(last_spawned)
        end
    end

    local mx, my = input.mouse()

    if input.mouse_pressed(input.MOUSE_LEFT) and Selected_Particle then
        last_spawned = dandelion.Spawn(Selected_Particle, mx, my)
    end

    if input.mouse_held(input.MOUSE_RIGHT) and Selected_Particle then
        counter += 1
        if counter > 1 then
            dandelion.Spawn(Selected_Particle, mx, my)
            counter = 0
        end
    end

    if input.mouse_released(input.MOUSE_RIGHT) then
        counter = 1
    end
end

local function outlined_text(text, x, y, color, outline)
    for i = -1, 1, 1 do
        for j = -1, 1, 1 do
            gfx.text(text, x + i, y + j, outline)
        end
    end
    gfx.text(text, x, y, color)
end

function _draw(dt)
    gfx.clear(gfx.COLOR_BLACK)

    -- local text = "DANDELION"
    -- local sx, sy = usagi.measure_text(text)
    -- local x = usagi.GAME_W / 2 - sx * 2
    -- local y = usagi.GAME_H / 2 - sy * 2
    -- gfx.text_ex(text, x+2, y, 4, 0, gfx.COLOR_ORANGE, 1)
    -- gfx.text_ex(text, x, y, 4, 0, gfx.COLOR_YELLOW, 1)

    dandelion.DrawExcept()
    if Hide_UI then return end
    dandelion.Debug(dt)

    local text_start = usagi.GAME_W - 102
    if Search_Open then
        local adjusted_text = string.sub(Search_Text, math.max(#Search_Text - 15, 0), #Search_Text)
        local text_size = usagi.measure_text(adjusted_text)
        gfx.rect_fill(text_start - 4, 3, 103, 15, gfx.COLOR_BLACK)
        gfx.rect(text_start - 4, 3, 103, 15, gfx.COLOR_TRUE_WHITE)
        gfx.text(adjusted_text, text_start, 4, gfx.COLOR_TRUE_WHITE)
        if usagi.elapsed % 1 > 0.5 then
            gfx.line(text_start + 1 + text_size, 7, text_start + 1 + text_size, 14, gfx.COLOR_TRUE_WHITE)
        end
        local results_start = 17
        if #Search_Results == 0 then
            outlined_text("No results", text_start, results_start, gfx.COLOR_LIGHT_GRAY, gfx.COLOR_BLACK)
        else
            for i = 1, #Search_Results do
                local color = i == Selected_Result_Index and gfx.COLOR_GREEN or gfx.COLOR_TRUE_WHITE
                outlined_text(Search_Results[i], text_start, results_start + 12 * (i - 1), color,
                    gfx.COLOR_BLACK)
            end
        end
    elseif Selected_Particle then
        local size = usagi.measure_text(Selected_Particle)
        outlined_text(Selected_Particle, usagi.GAME_W - size - 4, 4, gfx.COLOR_TRUE_WHITE, gfx.COLOR_BLACK)
    end

end
