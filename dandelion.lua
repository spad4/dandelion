local dandelion = {}

local load_particles = usagi.read_json("dandelion/particles.json")
local load_emitters = usagi.read_json("dandelion/emitters.json")

local particle_names = {}
local emitter_names = {}

-- runtime cache of particles and emitters
local particle_cache = {}
local emitter_cache = {}

local alive_particles = 0

-- which indices in the particle cache contain dead particles
-- new particles will pop an index off this table and replace the dead particle in the cache
local open_indices = {}

-- cache of chunks returned by properties so new functions aren't created every time a chunk is read
local chunk_cache = {}

local function compute_particle_expression(particle, expression)
    if type(expression) ~= "string" then
        return expression
    end

    particle.age = usagi.elapsed - particle.born
    local emit = particle.emitter

    if chunk_cache[expression] then
        return chunk_cache[expression](particle, emit)
    end

    -- this converts an expression into a function that can be called
    local c, err = load("return function (self, emit) return " .. expression .. " end", "expression", "t")
    if not c then return nil end


    local ok, func = pcall(c)
    if not ok then return nil end

    chunk_cache[expression] = func
    return func(particle, emit)
end

local function compute_emitter_expression(emitter, expression)
    if type(expression) ~= "string" then
        return expression
    end

    emitter.age = usagi.elapsed - emitter.born

    if chunk_cache[expression] then
        return chunk_cache[expression](emitter)
    end

    -- this converts an expression into a function that can be called
    local c, err = load("return function (self) return " .. expression .. " end", "expression", "t")
    if not c then return nil end

    local ok, func = pcall(c)
    if not ok then return nil end

    chunk_cache[expression] = func
    return func(emitter)
end

-- register all particle types and constructor functions
for _, particle in pairs(load_particles) do
    -- no duplicates, first come first serve for names
    if dandelion[string.lower(particle.name)] then goto continue end

    table.insert(particle_names, particle.name)
    dandelion[string.lower(particle.name)] = function(x, y, vars)
        -- culling prevents cache sizes from becoming ridiculous
        if not particle.no_cull and alive_particles > 3000 then return end
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

        new_particle.duration = compute_particle_expression(new_particle, new_particle.duration or 1)

        if #open_indices ~= 0 then
            local open = table.remove(open_indices, #open_indices)
            if open <= #particle_cache and particle_cache[open].dead then
                particle_cache[open] = new_particle
            else
                table.insert(particle_cache, new_particle)
            end
            -- end
        else
            table.insert(particle_cache, new_particle)
        end
        alive_particles += 1
    end
    ::continue::
end

-- register emitters
for _, emitter in pairs(load_emitters) do
    -- no duplicates, first come first serve for names
    if dandelion[string.lower(emitter.name)] then goto continue end

    table.insert(emitter_names, emitter.name)
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

        new_emitter.duration = compute_emitter_expression(new_emitter, new_emitter.duration or 1)

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

local function draw_particle(particle)
    if not particle.type or not particle.config then return end

    local adjusted_x = particle.x
    local adjusted_y = particle.y
    adjusted_x += compute_particle_expression(particle, particle.dx or 0)
    adjusted_y += compute_particle_expression(particle, particle.dy or 0)
    adjusted_x += compute_particle_expression(particle, particle.mx or 0)
    adjusted_y += compute_particle_expression(particle, particle.my or 0)

    local color = compute_particle_expression(particle, particle.color or gfx.COLOR_TRUE_WHITE)
    local config = particle.config

    if particle.type == "text" then
        local shadow = gfx[compute_particle_expression(particle, config.shadow)]
        local text = compute_particle_expression(particle, config.text or "'.'")
        local alpha = compute_particle_expression(particle, config.alpha or 1)
        local scale = compute_particle_expression(particle, config.scale or 1)
        local rotation = compute_particle_expression(particle, config.rotation or 0) * math.pi

        if shadow then
            gfx.text_ex("" .. text, adjusted_x + 1, adjusted_y + 1, scale, rotation, shadow, alpha)
        end
        gfx.text_ex("" .. text, adjusted_x, adjusted_y, scale, rotation, color, alpha)
    elseif particle.type == "circle" then
        local radius = compute_particle_expression(particle, config.radius or 1)

        if config.outline then
            local outline = compute_particle_expression(particle, config.outline or 1)
            gfx.circ_ex(adjusted_x, adjusted_y, radius + outline / 2, outline, color)
        else
            gfx.circ_fill(adjusted_x, adjusted_y, radius, color)
        end
    elseif particle.type == "triangle" then
        -- local size = self:compute(self.size)
        local size = compute_particle_expression(particle, config.size or 1)
        local rotation = compute_particle_expression(particle, config.rotation or 0)

        local x = adjusted_x
        local y = adjusted_y

        local x1, y1 = x + math.sin(math.pi * (rotation + 1 / 3)) * size,
            y + math.cos(math.pi * (rotation + 1 / 3)) * size
        local x2, y2 = x + math.sin(math.pi * (rotation + 1)) * size, y + math.cos(math.pi * (rotation + 1)) * size
        local x3, y3 = x + math.sin(math.pi * (rotation + 5 / 3)) * size,
            y + math.cos(math.pi * (rotation + 5 / 3)) * size

        if config.hollow then
            gfx.tri(x1, y1, x2, y2, x3, y3, color)
        else
            gfx.tri_fill(x1, y1, x2, y2, x3, y3, color)
        end

        -- if self.outline_color then
        --     local outline_color = gfx["COLOR_" .. self:compute(self.outline_color)]
        --     gfx.tri(x1, y1, x2, y2, x3, y3, outline_color)
        -- end
    elseif particle.type == "line" then
        local length = compute_particle_expression(particle, config.length or 16)
        local thickness = compute_particle_expression(particle, config.thickness or 1)
        local rotation = compute_particle_expression(particle, config.rotation or 0)

        local x1, y1 = adjusted_x, adjusted_y
        local px, py = math.cos(rotation * math.pi) * length, math.sin(rotation * math.pi) * length

        if config.centered then
            x1 -= px / 2
            y1 -= py / 2
        end

        gfx.line_ex(x1, y1, x1 + px, y1 + py, thickness, color)
    elseif particle.type == "rectangle" then
        local width = compute_particle_expression(particle, config.width or 16)
        local height = compute_particle_expression(particle, config.height or 16)
        local half_width = width / 2
        local half_height = height / 2
        local rotation = compute_particle_expression(particle, config.rotation or 0.25) * math.pi
        local outline = compute_particle_expression(particle, config.outline or 1)

        local x1, y1 = adjusted_x - math.cos(rotation) * (half_width + 0.5), adjusted_y - math.sin(rotation) * (half_height + 0.5)
        local x2, y2 = adjusted_x - math.cos(rotation + math.pi * 0.5) * (half_width + 0.5), adjusted_y - math.sin(rotation + math.pi * 0.5) * (half_height + 0.5)
        local x3, y3 = adjusted_x - math.cos(rotation + math.pi) * (half_width + 0.5), adjusted_y - math.sin(rotation + math.pi) * (half_height + 0.5)
        local x4, y4 = adjusted_x - math.cos(rotation - math.pi * 0.5) * (half_width + 0.5), adjusted_y +-math.sin(rotation - math.pi * 0.5) * (half_height + 0.5)
        
        if config.rotation and config.rotation ~= 0 then
            if config.outline then
                gfx.line_ex(x1, y1, x2, y2, outline, color)
                gfx.line_ex(x2, y2, x3, y3, outline, color)
                gfx.line_ex(x3, y3, x4 - 1, y4, outline, color)
                gfx.line_ex(x4, y4, x1, y1, outline, color)
            else
                gfx.tri_fill(x1, y1, x2, y2, x4, y4, color)
                gfx.tri_fill(x3, y3, x2, y2, x4, y4, color)
            end
        else
            if config.outline then
                gfx.rect_ex(adjusted_x - half_width, adjusted_y - half_height, width, height, outline, color)
            else
                gfx.rect_fill(adjusted_x - half_width, adjusted_y - half_height, width, height, color)
            end
        end


        -- particle.x - math.sin(rotation) * width / 2




        -- local x1, y1 = adjusted_x, adjusted_y
        -- local px, py = math.cos(rotation * math.pi) * length, math.sin(rotation * math.pi) * length

        -- if config.centered then
        --     x1 -= px / 2
        --     y1 -= py / 2
        -- end

        -- gfx.line_ex(x1, y1, x1 + px, y1 + py, thickness, color)
    end
end

local side_to_vector = {
    { x = 0,  y = 1 },
    { x = 1,  y = 0 },
    { x = 0,  y = -1 },
    { x = -1, y = 0 }
}

-- produces a random position within or on the edge of a rectangle of some width and height
local function rectangle_emitter(emitter, config, i, max)
    local percent = i / max
    local width = compute_emitter_expression(emitter, config.width or 16)
    local height = compute_emitter_expression(emitter, config.height or 16)
    local a = math.floor(percent * width * height)
    local distribution = config.distribution or "random"

    local x = 0
    local y = 0
    if config.outline then
        -- particles rotate between each face when emitting
        if distribution == "even" then
            local side = i % 4

            if side == 0 then
                x = percent * width - width * 0.5
                y = height * -0.5
            elseif side == 1 then
                x = width * -0.5
                y = percent * height - height * 0.5
            elseif side == 2 then
                x = percent * width - width * 0.5
                y = height * 0.5
            else
                x = width * 0.5
                y = percent * height - height * 0.5
            end
        else
            -- picks a random face to emit to
            if math.random() > 0.5 then
                x = math.random(0, 1) * width - width * 0.5
                y = math.random() * height - height * 0.5
            else
                x = math.random() * width - width * 0.5
                y = math.random(0, 1) * height - height * 0.5
            end
        end
    else
        -- if distribution == "even" then
            -- local r = width / height
            -- local w, h = r, 1
            -- if r > 1 then
                -- w, h = 1, r
            -- end
            -- local sqrt = math.sqrt(max)
            -- local pw = sqrt * w
            -- local ph = sqrt * h
            -- local px = i % pw
            -- local py = math.floor((i - 1) / ph)
-- 
            -- x = pw * px
            -- y = ph * py
-- 
        -- else
            x = math.random() * width - width * 0.5
            y = math.random() * height - height * 0.5
        -- end
    end

    return x, y
end

-- produces a random position within or on the edge of a circle of some radius
local function circle_emitter(emitter, config, i, max)
    local percent = i / max
    local radius = compute_emitter_expression(emitter, config.radius or 16)
    local distribution = config.distribution or "random"
    local rotation = compute_emitter_expression(emitter, config.rotation or 0)
    local motion = compute_emitter_expression(emitter, config.motion or 0)
    local direction = compute_emitter_expression(emitter, config.direction or 0) + 0.5

    local a = math.random
    -- this causes a spiral to form if outline is not also true
    if distribution == "even" then
        a = function() return percent end
    end

    local x = 0
    local y = 0
    local angle = 2 * math.pi * (a() + rotation)
    local ax = math.cos(angle)
    local ay = math.sin(angle)
    if not config.outline then
        x = ax * a() * radius
        y = ay * a() * radius
    else
        x = ax * radius
        y = ay * radius
    end

    local mx = "self.age * " .. math.cos(angle + (direction + 0.5) * math.pi) * -motion
    local my = "self.age * " .. math.sin(angle + (direction + 0.5) * math.pi) * -motion

    return x, y, mx, my
end

-- produces a random position on one of two lines of some length separated by some thickness with some rotation
local function line_emitter(emitter, config, i, max)
    local percent = i / max
    local length = compute_emitter_expression(emitter, config.length or 16)
    local thickness = compute_emitter_expression(emitter, config.thickness or 0)
    local rotation = compute_emitter_expression(emitter, config.rotation or 0)
    local motion = compute_emitter_expression(emitter, config.motion or 0)
    local direction = compute_emitter_expression(emitter, config.direction or 0) + 0.5
    local distribution = config.distribution or "random"

    local a = math.random
    local side = 1
    if distribution == "even" then
        a = function() return percent end
        side = i % 2 == 0 and 1 or -1
    else
        side = math.random() > 0.5 and 1 or -1
    end

    local x = math.cos(math.pi * rotation) * length
    local y = math.sin(math.pi * rotation) * length
    local x_offset = math.cos((0.5 * math.pi) + rotation * math.pi) * thickness * side * 0.5
    local y_offset = math.sin((0.5 * math.pi) + rotation * math.pi) * thickness * side * 0.5

    -- local x_motion = math.cos((0.5 * math.pi) + rotation * math.pi) * thickness * side * 0.5
    -- local y_motion = math.sin((0.5 * math.pi) + rotation * math.pi) * thickness * side * 0.5
    local x_velocity = nil
    local y_velocity = nil
    local rand = a()
    if motion ~= 0 then
        if side == -1 then
            direction = 1 - direction
        end
        x_velocity = "self.age * " .. math.cos((rotation + direction) * math.pi) * motion * side
        y_velocity = "self.age * " .. math.sin((rotation + direction) * math.pi) * motion * side
    end

    local center = config.centered and 0.5 or 0

    x *= rand - center
    y *= rand - center

    return x + x_offset, y + y_offset, x_velocity, y_velocity
end

local emitter_shape_function = {
    ["rectangle"] = rectangle_emitter,
    ["circle"] = circle_emitter,
    ["line"] = line_emitter
}

local function emit_particles(emitter)
    local particles = emitter.particles
    if not particles then return end

    local age = usagi.elapsed - emitter.born
    local dx = compute_emitter_expression(emitter, emitter.dx or 0)
    local dy = compute_emitter_expression(emitter, emitter.dy or 0)

    for i, particle in pairs(emitter.particles) do
        if not particle.name then goto continue end
        if particle.name == emitter.name then goto continue end

        if particle.delay then
            -- delay > 0 means the particle will wait that long before emitting
            -- delay < 0 means the particle will stop emitting earlier than when the emitter dies
            if particle.delay > 0 and particle.delay > age then goto continue end
            if particle.delay < 0 and (emitter.duration + particle.delay < age) then goto continue end
        end

        local shape_function = function(_, _, _, _) return 0, 0 end
        if emitter_shape_function[particle.shape] and particle.config then
            shape_function = emitter_shape_function[particle.shape]
        end

        local frequency = particle.frequency or 1
        local emit_count = math.floor(age / frequency)

        if emitter.last_emit[i] ~= emit_count then
            emitter.last_emit[i] = emit_count
            local count = particle.count or 1

            for j = 1, count do
                -- mx, my are optional values returned by shape functions that impact
                -- the motion of particles spawned by the emitter
                local sx, sy, mx, my = shape_function(emitter, particle.config, j, count)
                local vars = particle.overrides or {}
                if mx then vars.mx = mx end
                if my then vars.my = my end
                vars.emitter = emitter
                dandelion[string.lower(particle.name)](emitter.x + dx + sx, emitter.y + dy + sy, vars)
            end
        end
        ::continue::
    end
end

function dandelion.Draw()
    -- these hopefully don't need optimized removal, but it can be added later if necessary
    for i = #emitter_cache, 1, -1 do
        local emitter = emitter_cache[i]
        local age = usagi.elapsed - emitter.born

        if age > emitter.duration then
            table.remove(emitter_cache, i)
        else
            emit_particles(emitter)
        end
    end

    -- remove at most 1% of the total number of particles each frame
    local remove_budget = #particle_cache * 0.01

    -- start at the end of the list so remove operations don't make i skip a value
    for i = #particle_cache, 1, -1 do
        local particle = particle_cache[i]
        --[[
            why replace instead of remove?
            in lua, removing an item from the middle of the table shifts all items to the right of it
            which means that removing an item this way will run a loop of n iterations, where n is
            the number of elements to the right of that item
            if we remove every particle immediately when it dies, that means that in the worse case
            particle_cache results in n^2 iterations in a single frame, which is potentially millions
            obviously, that's really bad for performance
            so instead we keep track of which indices can be safely replaced without overwriting a living particle
            and prefer replacing a living particle over increasing the size of the cache
            culling helps even more because then the size of the cache will never exceed an amount that
            would cause table.remove to majorly impact performance
        ]] --
        if particle.dead or usagi.elapsed - particle.born > particle.duration then
            if remove_budget > 0 then
                if not particle.dead then alive_particles = alive_particles - 1 end
                table.remove(particle_cache, i)
                remove_budget -= 1
            else
                if not particle.dead then
                    particle.dead = true
                    alive_particles -= 1
                    -- next time a particle spawns, it will try to replace this one in the table
                    -- instead of expanding the cache
                    table.insert(open_indices, i)
                end
            end
        else
            draw_particle(particle)
        end
    end
end

function dandelion.Particles()
    return particle_names
end

function dandelion.Emitters()
    return emitter_names
end

local fps_history = {}
for i = 1, 60 do
    fps_history[i] = 0
end

function dandelion.ClearAll()
    particle_cache = {}
    emitter_cache = {}
    alive_particles = 0
end

function dandelion.Debug(dt)
    -- stats
    outlined_text("emitters: " .. #emitter_cache, 4, 0, gfx.COLOR_TRUE_WHITE, gfx.COLOR_BLACK)
    outlined_text("particle cache: " .. #particle_cache, 4, 10, gfx.COLOR_TRUE_WHITE, gfx.COLOR_BLACK)
    outlined_text("alive particles: " .. alive_particles, 4, 20, gfx.COLOR_TRUE_WHITE, gfx.COLOR_BLACK)

    -- fps chart
    gfx.rect_fill(4, 110, 68, 76, gfx.COLOR_BLACK)
    table.remove(fps_history, 1)
    table.insert(fps_history, 60, 1 / dt)
    local avg = 0
    for i = 1, 60 do
        avg += fps_history[i] / 60
        local diff = 60 - fps_history[i]
        local color = gfx.COLOR_GREEN
        if diff > 2 then
            color = gfx.COLOR_YELLOW
        end
        if diff > 5 then
            color = gfx.COLOR_ORANGE
        end
        if diff > 10 then
            color = gfx.COLOR_RED
        end
        gfx.line(i + 8, 172, i + 8, 172 - diff + 1, color)
    end
    outlined_text("FPS: " .. string.format("%.1f", avg), 9, 112, gfx.COLOR_TRUE_WHITE, gfx.COLOR_BLACK)
end

return dandelion
