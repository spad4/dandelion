local dandelion = {}

local load_particles = usagi.read_json("dandelion/particles.json")
local load_emitters = usagi.read_json("dandelion/emitters.json")

-- runtime cache of particles and emitters
local particle_cache = {}
local emitter_cache = {}

-- register all particle types and constructor functions
for _, particle in pairs(load_particles) do
    -- no duplicates, first come first serve for names
    if dandelion[string.lower(particle.name)] then goto continue end

    dandelion[string.lower(particle.name)] = function(x, y, vars)
        local new_particle = {
            x = x,
            y = y,
            born = usagi.elapsed
        }

        -- assign all properties from json
        -- TODO: this could probably be a reference to a table
        for k, v in pairs(particle) do
            new_particle[k] = v
        end

        -- unused for now
        if vars then
            for k, v in pairs(vars) do
                -- these properties are immutable
                if k ~= "name" and k ~= "x" and k ~= "y" and k ~= "born" then
                    new_particle[k] = v
                end
            end
        end

        -- these are random values accessible when expressions are computed in particles
        -- via self.random_1, self.random_2, etc
        new_particle.random_1 = math.random()
        new_particle.random_2 = math.random()
        new_particle.random_3 = math.random()
        new_particle.random_4 = math.random()
        table.insert(particle_cache, new_particle)
    end
    ::continue::
end

-- register emitters
for _, emitter in pairs(load_emitters) do
    -- no duplicates, first come first serve for names
    if dandelion[string.lower(emitter.name)] then goto continue end

    dandelion[string.lower(emitter.name)] = function(x, y, vars)
        local new_emitter = {
            x = x,
            y = y,
            born = usagi.elapsed
        }

        -- assign all properties from json
        -- TODO: this can DEFINITELY be a reference to a table
        for k, v in pairs(emitter) do
            new_emitter[k] = v
        end

        -- a table of the last time each particle was emitted
        -- used to distribute particle emissions properly
        new_emitter.last_emit = {}

        -- these are random values accessible when expressions are computed in particles
        -- in emitters, use self.random_1
        -- in particles, use emit.random_1, emit.random_2, etc
        new_emitter.random_1 = math.random()
        new_emitter.random_2 = math.random()
        new_emitter.random_3 = math.random()
        new_emitter.random_4 = math.random()

        -- if vars then
        --     for k, v in pairs(vars) do
        --         -- these properties are immutable
        --         if k ~= "name" and k ~= "x" and k ~= "y" and k ~= "born" then
        --             new_emitter[k] = v
        --         end
        --     end
        -- end

        table.insert(emitter_cache, new_emitter)
    end
    ::continue::
end

local particle_expression_cache = {}

local function compute_particle_expression(particle, expression)
    if type(expression) ~= "string" then
        return expression
    end

    particle.age = usagi.elapsed - particle.born

    if particle_expression_cache[expression] then
        return particle_expression_cache[expression](particle)
    end

    -- this converts an expression into a function that can be called
    local c, err = load("return function (self) return " .. expression .. " end", "expression", "t")
    if not c then return nil end

    local ok, func = pcall(c)
    if not ok then return nil end

    particle_expression_cache[expression] = func
    return func(particle)
end

local emitter_expression_cache = {}

local function compute_emitter_expression(emitter, expression)
    if type(expression) ~= "string" then
        return expression
    end

    emitter.age = usagi.elapsed - emitter.born

    if emitter_expression_cache[expression] then
        return emitter_expression_cache[expression](emitter)
    end

    -- this converts an expression into a function that can be called
    local c, err = load("return function (self) return " .. expression .. " end", "expression", "t")
    if not c then return nil end

    local ok, func = pcall(c)
    if not ok then return nil end

    emitter_expression_cache[expression] = func
    return func(emitter)
end

local function draw_particle(particle)
    local dx = compute_particle_expression(particle, particle.dx or 0)
    local dy = compute_particle_expression(particle, particle.dy or 0)

    if particle.type == "text" then
        local color = gfx[compute_particle_expression(particle, particle.color or "'COLOR_TRUE_WHITE'")]
        local text = compute_particle_expression(particle, particle.text or "'.'") -- MUST BE OPTIMIZED BEFORE RELEASE
        local alpha = compute_particle_expression(particle, particle.alpha or 1)
        gfx.text_ex(text, particle.x + dx, particle.y + dy, 1, 0, color, alpha)
    end
end

-- produces a random position within or on the edge of a rectangle of some width and height
local function rectangle_emitter(emitter, config)
    local width = compute_emitter_expression(emitter, config.width or 16)
    local height = compute_emitter_expression(emitter, config.height or 16)

    local x = 0
    local y = 0
    if not config.outline then
        x = math.random() * width - width * 0.5
        y = math.random() * height - height * 0.5
    else
        if math.random() > 0.5 then
            x = math.random(0, 1) * width - width * 0.5
            y = math.random() * height - height * 0.5
        else
            x = math.random() * width - width * 0.5
            y = math.random(0, 1) * height - height * 0.5
        end
    end

    return x, y
end

-- produces a random position within or on the edge of a circle of some radius
local function circle_emitter(emitter, config)
    local radius = compute_emitter_expression(emitter, config.radius or 16)

    local x = 0
    local y = 0
    local angle = 2 * math.pi * math.random()
    if not config.outline then
        x = math.cos(angle) * math.random() * radius
        y = math.sin(angle) * math.random() * radius
    else
        x = math.cos(angle) * radius
        y = math.sin(angle) * radius
    end

    return x, y
end

-- produces a random position on one of two lines of some length separated by some thickness with some rotation
local function line_emitter(emitter, config)
    local length = compute_emitter_expression(emitter, config.length or 16)
    local thickness = compute_emitter_expression(emitter, config.thickness or 0)
    local rotation = compute_emitter_expression(emitter, config.rotation or 0)
    local velocity = compute_emitter_expression(emitter, config.motion or 0)
    local direction = compute_emitter_expression(emitter, config.direction or 1)

    local side = math.random() > 0.5 and 1 or -1
    local x = math.cos(math.pi * rotation) * length
    local y = math.sin(math.pi * rotation) * length
    local x_offset = math.cos((0.5 * math.pi) + rotation * math.pi) * thickness * side * 0.5
    local y_offset = math.sin((0.5 * math.pi) + rotation * math.pi) * thickness * side * 0.5

    -- local x_motion = math.cos((0.5 * math.pi) + rotation * math.pi) * thickness * side * 0.5
    -- local y_motion = math.sin((0.5 * math.pi) + rotation * math.pi) * thickness * side * 0.5
    local x_velocity = nil
    local y_velocity = nil
    if velocity ~= 0 then
        x_velocity = "self.age * " .. math.cos((rotation + direction) * math.pi) * velocity * side
        y_velocity = "self.age * " .. math.sin((rotation + direction) * math.pi) * velocity * side
    end

    local rand = math.random()
    local center = config.centered and 0.5 or 0

    x *= rand - center
    y *= rand - center

    return x + x_offset, y + y_offset, x_velocity, y_velocity
end

-- local function triangle_emitter(emitter, config)
--     local length = 16
--     if config.length then
--         length = compute_emitter_expression(emitter, config.length)
--     end
--     if type(length) ~= "number" then return 0, 0 end

--     local thickness = 1
--     if config.thickness then
--         thickness = compute_emitter_expression(emitter, config.thickness)
--     end
--     if type(thickness) ~= "number" then return 0, 0 end

--     local rotation = 0
--     if config.rotation then
--         rotation = compute_emitter_expression(emitter, config.rotation)
--     end
--     if type(rotation) ~= "number" then return 0, 0 end


--     local x, y = math.sin(2 * math.pi * rotation) * length, math.cos(2 * math.pi * rotation) * length

--     local rand = math.random()
--     local center = config.centered and 0.5 or 0

--     x *= rand - center
--     y *= rand - center

--     return x, y
-- end

local emitter_shape_function = {
    ["rectangle"] = rectangle_emitter,
    ["circle"] = circle_emitter,
    ["line"] = line_emitter
}

local function emit_particles(emitter)
    local particles = emitter.particles
    if not particles then return end

    local age = usagi.elapsed - emitter.born

    for i, particle in pairs(emitter.particles) do
        if not particle.name then goto continue end
        if particle.name == emitter.name then goto continue end

        if particle.delay then
            if particle.delay > 0 and particle.delay > age then goto continue end
            if particle.delay < 0 and (emitter.duration + particle.delay < age) then goto continue end
        end

        local shape_function = function(_, _) return 0, 0 end
        if emitter_shape_function[particle.shape] and particle.config then
            shape_function = emitter_shape_function[particle.shape]
        end

        local frequency = particle.frequency or 1
        local emit_count = math.floor(age / frequency)

        if emitter.last_emit[i] ~= emit_count then
            emitter.last_emit[i] = emit_count

            local count = particle.count or 1

            for _ = 1, count do
                local dx, dy, mx, my = shape_function(emitter, particle.config)
                local vars = {}
                if mx then vars.dx = mx end
                if my then vars.dy = my end
                dandelion[string.lower(particle.name)](emitter.x + dx, emitter.y + dy, vars)
            end
        end
        ::continue::
    end
end

local removed = 0
local prev_removed = 0

function dandelion:Draw()
    removed = 0
    for i = #emitter_cache, 1, -1 do
        local emitter = emitter_cache[i]
        local age = usagi.elapsed - emitter.born
        if age > emitter.duration then
            table.remove(emitter_cache, i)
        else
            emit_particles(emitter)
        end
    end

    for i = #particle_cache, 1, -1 do
        local particle = particle_cache[i]
        if usagi.elapsed - particle.born > particle.duration then
            table.remove(particle_cache, i)
            removed += 1
        else
            draw_particle(particle)
        end
    end
end

function dandelion:Debug()
    -- gfx.text("EMITTERS: " .. #emitter_cache, 5, 13, gfx.COLOR_BLACK)
    -- gfx.text("EMITTERS: " .. #emitter_cache, 4, 13, gfx.COLOR_BLACK)
    -- gfx.text("EMITTERS: " .. #emitter_cache, 3, 13, gfx.COLOR_BLACK)
    -- gfx.text("EMITTERS: " .. #emitter_cache, 3, 12, gfx.COLOR_BLACK)
    -- gfx.text("EMITTERS: " .. #emitter_cache, 3, 11, gfx.COLOR_BLACK)
    -- gfx.text("EMITTERS: " .. #emitter_cache, 4, 11, gfx.COLOR_BLACK)
    -- gfx.text("EMITTERS: " .. #emitter_cache, 5, 11, gfx.COLOR_BLACK)
    -- gfx.text("EMITTERS: " .. #emitter_cache, 5, 12, gfx.COLOR_BLACK)
    gfx.text("EMITTERS: " .. #emitter_cache, 4, 12, gfx.COLOR_TRUE_WHITE)
    -- gfx.text("PARTICLES: " .. #particle_cache, 5, 25, gfx.COLOR_BLACK)
    -- gfx.text("PARTICLES: " .. #particle_cache, 4, 25, gfx.COLOR_BLACK)
    -- gfx.text("PARTICLES: " .. #particle_cache, 3, 25, gfx.COLOR_BLACK)
    -- gfx.text("PARTICLES: " .. #particle_cache, 3, 24, gfx.COLOR_BLACK)
    -- gfx.text("PARTICLES: " .. #particle_cache, 3, 23, gfx.COLOR_BLACK)
    -- gfx.text("PARTICLES: " .. #particle_cache, 4, 23, gfx.COLOR_BLACK)
    -- gfx.text("PARTICLES: " .. #particle_cache, 5, 23, gfx.COLOR_BLACK)
    -- gfx.text("PARTICLES: " .. #particle_cache, 5, 24, gfx.COLOR_BLACK)
    gfx.text("PARTICLES: " .. #particle_cache, 4, 24, gfx.COLOR_TRUE_WHITE)
    prev_removed = removed == 0 and prev_removed or removed
    gfx.text("REMOVED: " .. prev_removed, 4, 36, gfx.COLOR_TRUE_WHITE)
end

return dandelion
