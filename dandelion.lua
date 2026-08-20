--[[ ###########
      CONSTANTS
     ########### ]]

local VALID_NAME_PATTERN = "^[a-z0-9_.-]+$"
local IMMUTABLE_PROPERTIES = {
    name = true,
    x = true,
    y = true,
    born = true
}
local LOAD_PARTICLES = usagi.read_json("dandelion/particles.json")
local LOAD_EMITTERS = usagi.read_json("dandelion/emitters.json")

local THIRD_OF_PI = math.pi / 3
local HALF_OF_PI = math.pi * 0.5
local FIVE_THIRDS_OF_PI = math.pi * 5 / 3

local total_spawned = 0

local DEFAULT = {
    PARTICLE_GROUP = "none",
    COLOR = gfx.COLOR_TRUE_WHITE,
    ALPHA = 1,
    TEXT = "'.'",
    TEXT_SCALE = 1,
    CIRCLE_RADIUS = 16,
    CIRCLE_OUTLINE = 1,
    TRIANGLE_SIZE = 16,
    LINE_LENGTH = 16,
    LINE_THICKNESS = 1,
    RECTANGLE_SIZE = 16,
    RECT_EMIT_SIZE = 16,
    CIRC_EMIT_RADIUS = 16,
    LINE_EMIT_LENGTH = 16,
    EMITTER_DISTRIBUTION = "random"
}

--[[ ################
      RUNTIME CACHES
     ################ ]]

-- the metatables new particles receive
local particle_metatables = {}
local emitter_metatables = {}

-- runtime caches of particles and emitters
-- particles have groups, so particle_caches is a map of group names to group caches
local particle_caches = {}
local emitter_cache = {}

local alive_particles = 0

-- which indices in each group cache contain dead particles
-- new particles will pop an index off their group's table and replace the dead particle in the cache
local open_indices = {}

-- cache of chunks returned by properties so new functions aren't created every time a chunk is read
local chunk_cache = {}

-- last time particles were emitted; prevents multiple emissions per frame
local last_emit = 0

--[[ #######
      SETUP
     ####### ]]

-- register all particle types and constructor functions
for _, particle in pairs(LOAD_PARTICLES) do
    if not particle.name then
        error("Particle is missing name!")
    end
    if not string.match(particle.name, VALID_NAME_PATTERN) then
        error("Particle name '" ..
            particle.name ..
            "' contains invalid characters. Valid characters are alphanumerics, or _ - .")
    end
    -- NO DUPLICATES!!
    if particle_metatables[particle.name] or emitter_metatables[particle.name] then
        error("Particle '" .. particle.name .. "' is a duplicate and should be renamed")
    end

    local group = particle.group or "none"
    if not particle_caches[group] then
        particle_caches[group] = {}
    end

    if not open_indices[group] then
        open_indices[group] = {}
    end

    particle_metatables[particle.name] = particle
end

-- register emitters
for _, emitter in pairs(LOAD_EMITTERS) do
    if not emitter.name then
        error("Emitter is missing name!")
    end
    if not string.match(emitter.name, VALID_NAME_PATTERN) then
        error("Emitter name '" ..
            emitter.name ..
            "' contains invalid characters. Valid characters are alphanumerics, or _ - .")
    end
    -- NO DUPLICATES!!
    if particle_metatables[emitter.name] or emitter_metatables[emitter.name] then
        error("Error creating emitter: '" .. emitter.name .. "' is a duplicate and should be renamed")
    end

    emitter_metatables[emitter.name] = emitter
end

--[[ ####################
      INTERNAL FUNCTIONS
     #################### ]]

-- converts a string into a chunk that can be called to compute values
local function eval_chunk(object, chunk)
    if type(chunk) ~= "string" then
        return chunk
    end

    object.age = usagi.elapsed - object.born

    -- object.emitter is not populated for emitters, 
    -- but it doesn't really matter since it will be nil either way
    -- functionally the same as not passing it at all
    if chunk_cache[chunk] then
        return chunk_cache[chunk](object, object.emitter)
    end

    -- this converts an expression into a function that can be called
    local c, err = load("return function (self, emit) return " .. chunk .. " end", "expression", "t")
    if not c then return nil end

    local ok, func = pcall(c)
    if not ok then return nil end

    chunk_cache[chunk] = func
    return func(object, object.emitter)
end

local function spawn_particle(name, x, y, vars)
    local particle = particle_metatables[name]
    if not particle.no_cull and alive_particles > 3000 then return end
    local new_particle = {
        x = x,
        y = y,
        born = usagi.elapsed
    }

    setmetatable(new_particle, { __index = particle })

    if vars then
        for k, v in pairs(vars) do
            if not IMMUTABLE_PROPERTIES[k] then
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

    new_particle.duration = eval_chunk(new_particle, new_particle.duration or 1)

    local group = particle.group or "none"
    local group_cache = particle_caches[group]
    local group_indices = open_indices[group]
    if #group_indices ~= 0 then
        local open = table.remove(group_indices, #group_indices)
        if open <= #group_cache and group_cache[open].dead then
            group_cache[open] = new_particle
        else
            table.insert(group_cache, new_particle)
        end
    else
        table.insert(group_cache, new_particle)
    end
    alive_particles += 1
    total_spawned += 1
    return new_particle
end

local function spawn_emitter(name, x, y, vars)
    local emitter = emitter_metatables[name]
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

    new_emitter.duration = eval_chunk(new_emitter, new_emitter.duration or 1)

    if vars then
        for k, v in pairs(vars) do
            if not IMMUTABLE_PROPERTIES[k] then
                new_emitter[k] = v
            end
        end
    end
    table.insert(emitter_cache, new_emitter)
    return new_emitter
end

local function spawn(name, x, y, vars, context)
    if particle_metatables[name] then
        return spawn_particle(name, x, y, vars)
    elseif emitter_metatables[name] then
        return spawn_emitter(name, x, y, vars)
    end

    error(context .. " tried to spawn particle/emitter '" .. name .. "' which does not exist")
end

local function outlined_text(text, x, y, color, outline)
    for i = -1, 1, 1 do
        for j = -1, 1, 1 do
            gfx.text(text, x + i, y + j, outline)
        end
    end
    gfx.text(text, x, y, color)
end

local function draw_particle(particle)
    if not particle.shapes then return end

    -- get dx
    local center_x = particle.x
    local center_y = particle.y
    center_x += eval_chunk(particle, particle.dx or 0)
    center_y += eval_chunk(particle, particle.dy or 0)

    -- mx and my come from emitters: circle & line can push particles in certain
    -- directions depending on the parameters provided to the emitter
    center_x += eval_chunk(particle, particle.mx or 0)
    center_y += eval_chunk(particle, particle.my or 0)

    -- these are used for when the particle dies and needs to spawn a new particle
    particle.prev_x, particle.prev_y = center_x, center_y

    local particle_rotation = eval_chunk(particle, particle.rotation or 0) * math.pi
    local propagated_rotation = particle.rotate_shapes and particle_rotation or 0

    for _, shape in pairs(particle.shapes) do
        -- base shape offset
        local offset_x = eval_chunk(particle, shape.dx or 0)
        local offset_y = eval_chunk(particle, shape.dy or 0)
        -- rotate offset based on particle rotation, and add to the center of the particle
        local final_x = center_x + offset_x * math.cos(particle_rotation) - offset_y * math.sin(particle_rotation)
        local final_y = center_y + offset_x * math.sin(particle_rotation) + offset_y * math.cos(particle_rotation)

        -- other properties shared by all shapes
        local color = eval_chunk(particle, shape.color or gfx.COLOR_TRUE_WHITE)
        local alpha = eval_chunk(particle, shape.alpha or 1)

        if shape.type == "pixel" then
            gfx.px(final_x, final_y, color, alpha)
        elseif shape.type == "text" then
            local shadow = eval_chunk(particle, shape.shadow)
            local outline = eval_chunk(particle, shape.outline)
            local text = tostring(eval_chunk(particle, shape.text or DEFAULT.TEXT))
            local scale = eval_chunk(particle, shape.scale or DEFAULT.TEXT_SCALE)
            local rotation = eval_chunk(particle, shape.rotation or 0) * math.pi + propagated_rotation

            local alignment = 0
            if shape.align == "center" then
                alignment = scale * usagi.measure_text(text) / 2
            elseif shape.align == "right" then
                alignment = scale * usagi.measure_text(text)
            end

            if outline then
                for i = -1, 1, 1 do
                    for j = -1, 1, 1 do
                        gfx.text_ex("" .. text, final_x - alignment + i * scale, final_y + j * scale, scale, rotation,
                            outline, alpha)
                    end
                end
            elseif shadow then
                gfx.text_ex("" .. text, final_x + scale - alignment, final_y + scale, scale, rotation, shadow, alpha)
            end

            gfx.text_ex("" .. text, final_x - alignment, final_y, scale, rotation, color, alpha)
        elseif shape.type == "circle" then
            local radius = eval_chunk(particle, shape.radius or DEFAULT.CIRCLE_RADIUS)

            if shape.outline then
                local outline = eval_chunk(particle, shape.outline or DEFAULT.CIRCLE_OUTLINE)
                gfx.circ_ex(final_x, final_y, radius + outline / 2, outline, color, alpha)
            else
                gfx.circ_fill(final_x, final_y, radius, color, alpha)
            end
        elseif shape.type == "triangle" then
            local size = eval_chunk(particle, shape.size or DEFAULT.TRIANGLE_SIZE)
            local rotation = -(eval_chunk(particle, shape.rotation or 0) * math.pi + propagated_rotation)

            local x = final_x
            local y = final_y

            local x1, y1 =
                x + math.sin(rotation + THIRD_OF_PI) * size,
                y + math.cos(rotation + THIRD_OF_PI) * size
            local x2, y2 =
                x + math.sin(rotation + math.pi) * size,
                y + math.cos(rotation + math.pi) * size
            local x3, y3 =
                x + math.sin(rotation + FIVE_THIRDS_OF_PI) * size,
                y + math.cos(rotation + FIVE_THIRDS_OF_PI) * size

            if shape.hollow then
                gfx.tri(x1, y1, x2, y2, x3, y3, color, alpha)
            else
                gfx.tri_fill(x1, y1, x2, y2, x3, y3, color, alpha)
            end
        elseif shape.type == "line" then
            local length = eval_chunk(particle, shape.length or DEFAULT.LINE_LENGTH)
            local thickness = eval_chunk(particle, shape.thickness or DEFAULT.LINE_THICKNESS)
            local rotation = eval_chunk(particle, shape.rotation or 0) * math.pi + propagated_rotation

            local x1, y1 = final_x, final_y
            local v = util.vec_from_angle(rotation, length)
            local px, py = v.x, v.y
            if shape.centered then
                x1 -= px / 2
                y1 -= py / 2
            end

            gfx.line_ex(x1, y1, x1 + px, y1 + py, thickness, color, alpha)
        elseif shape.type == "rectangle" then
            local width = eval_chunk(particle, shape.width or DEFAULT.RECTANGLE_SIZE)
            local height = eval_chunk(particle, shape.height or DEFAULT.RECTANGLE_SIZE)
            local half_width = width / 2
            local half_height = height / 2
            local rotation = eval_chunk(particle, shape.rotation or 0.25) * math.pi + propagated_rotation
            local outline = eval_chunk(particle, shape.outline or 1)

            local function rotated_corner(x, y)
                local tx = x * math.cos(rotation) - y * math.sin(rotation)
                local ty = x * math.sin(rotation) + y * math.cos(rotation)
                return final_x + tx, final_y + ty
            end

            local x1, y1 = rotated_corner(-half_width, -half_height) -- top left
            local x2, y2 = rotated_corner(half_width, -half_height)  -- top right
            local x3, y3 = rotated_corner(half_width, half_height)   -- bottom right
            local x4, y4 = rotated_corner(-half_width, half_height)  -- bottom left

            if shape.rotation and shape.rotation ~= 0 then
                if shape.outline then
                    gfx.line_ex(x1, y1, x2, y2, outline, color, alpha)
                    gfx.line_ex(x2, y2, x3, y3, outline, color, alpha)
                    gfx.line_ex(x3, y3, x4, y4, outline, color, alpha)
                    gfx.line_ex(x4, y4, x1, y1, outline, color, alpha)
                else
                    gfx.tri_fill(x1, y1, x2, y2, x4, y4, color, alpha)
                    gfx.tri_fill(x3, y3, x2, y2, x4, y4, color, alpha)
                end
            else
                if shape.outline then
                    gfx.rect_ex(final_x - half_width, final_y - half_height, width, height, outline, color, alpha)
                else
                    gfx.rect_fill(final_x - half_width, final_y - half_height, width, height, color, alpha)
                end
            end
        end
    end
end

-- produces a random position within or on the edge of a rectangle of some width and height
local function rectangle_emitter(emitter, config, i, max)
    local percent = i / max
    local width = eval_chunk(emitter, config.width or DEFAULT.RECT_EMIT_SIZE)
    local height = eval_chunk(emitter, config.height or DEFAULT.RECT_EMIT_SIZE)
    local a = math.floor(percent * width * height)
    local distribution = config.distribution or DEFAULT.EMITTER_DISTRIBUTION

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
    local radius = eval_chunk(emitter, config.radius or DEFAULT.CIRC_EMIT_RADIUS)
    local distribution = config.distribution or "random"
    local rotation = eval_chunk(emitter, config.rotation or 0)
    local motion = eval_chunk(emitter, config.motion or 0)
    local direction = eval_chunk(emitter, config.direction or 0) + 0.5

    local a = math.random
    -- this causes a spiral to form if outline is not also true
    if distribution == "even" then
        a = function() return percent end
    end

    local x = 0
    local y = 0
    local angle = math.pi * (2 * a() + rotation)
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
    local length = eval_chunk(emitter, config.length or DEFAULT.LINE_EMIT_LENGTH)
    local thickness = eval_chunk(emitter, config.thickness or 0)
    local rotation = eval_chunk(emitter, config.rotation or 0)
    local motion = eval_chunk(emitter, config.motion or 0)
    local direction = eval_chunk(emitter, config.direction or 0) + 0.5
    local distribution = config.distribution or DEFAULT.EMITTER_DISTRIBUTION

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
    local y_offset = math.sin(HALF_OF_PI + rotation * math.pi) * thickness * side * 0.5
    local x_offset = math.cos(HALF_OF_PI + rotation * math.pi) * thickness * side * 0.5

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
    local dx = eval_chunk(emitter, emitter.dx or 0)
    local dy = eval_chunk(emitter, emitter.dy or 0)

    for i, particle in pairs(emitter.particles) do
        if not particle.name then
            error("A shape from emitter '" .. emitter.name .. "' is missing a particle name")
        end
        if particle.name == emitter.name then
            error("A shape from emitter '" .. emitter.name .. "' is looping")
        end

        if particle.delay then
            -- delay > 0 means the particle will wait that long before emitting
            -- delay < 0 means the particle will stop emitting earlier than when the emitter dies
            if particle.delay > 0 and particle.delay > age then goto continue end
            if particle.delay < 0 and (emitter.duration + particle.delay < age) then goto continue end
        end

        local shape_function = function(_, _, _, _) return 0, 0 end
        if emitter_shape_function[particle.shape] then
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
                local sx, sy, mx, my = shape_function(emitter, particle, j, count)
                local vars = particle.overrides or {}
                if mx then vars.mx = mx end
                if my then vars.my = my end
                vars.emitter = emitter

                -- spawn particle
                spawn(particle.name, emitter.x + dx + sx, emitter.y + dy + sy, vars, "Emitter '" .. emitter.name .. "'")
            end
        end
        ::continue::
    end
end

local function emit()
    last_emit = usagi.elapsed
    -- these hopefully don't need optimized removal, but it can be added later if necessary
    for i = #emitter_cache, 1, -1 do
        local emitter = emitter_cache[i]
        if emitter.killed or usagi.elapsed - emitter.born > emitter.duration then
            table.remove(emitter_cache, i)
        else
            emit_particles(emitter)
        end
    end
end

local function draw_particle_group(group, ignored)
    local group_cache = particle_caches[group]
    if not group_cache then return end
    ignored = ignored or false

    -- remove at most 1% of the total number of particles each frame
    local remove_budget = #group_cache * 0.01

    -- start at the end of the list so remove operations don't make i skip a value
    for i = #group_cache, 1, -1 do
        local particle = group_cache[i]
        --[[
            why replace instead of remove?
            in lua, removing an item from the middle of the table shifts all items to the right of it
            which means that removing an item this way will run a loop of n iterations, where n is
            the number of elements to the right of that item
            if we remove every particle immediately when it dies, that means that in the worse case
            particle_cache results in n^2 iterations in a single frame, which is potentially millions
            obviously, that's really bad for performance
            so instead we keep track of which indices can be safely replaced without overwriting a living particle
            and prefer replacing a dead particle over increasing the size of the cache
            culling helps even more because then the size of the cache will never exceed an amount that
            would cause table.remove to majorly impact performance
        ]] --

        if not particle.dead and (particle.killed or usagi.elapsed - particle.born > particle.duration) then
            particle.dead = true
            alive_particles = math.max(0, alive_particles - 1)
            if particle.create_on_death then
                spawn(particle.create_on_death, particle.prev_x, particle.prev_y, particle.vars,
                    "Particle '" .. particle.name .. "' create_on_death")
            end
            -- if no more particles will be removed this frame,
            -- this index can be overwritten instead of removed
            if remove_budget <= 0 then
                table.insert(open_indices[group], i)
            end
        end

        if particle.dead then
            if remove_budget > 0 then
                table.remove(group_cache, i)
                remove_budget -= 1
            end
        elseif not ignored then
            draw_particle(particle)
        end
    end
end

local function contains(table, item)
    for _, v in pairs(table) do
        if v == item then return true end
    end
    return false
end

--[[ ###########################
      USER FACING API FUNCTIONS
     ########################### ]]

local dandelion = {}

---Creates a particle or emitter at the provided screen coordinates.
---@param name string                   the name of the particle or emitter
---@param x number                      x screen coordinate
---@param y number                      y screen coordinate
---@param vars? table                   optional overrides for the object; see particle/emitter cheat sheets
---@return table table                  a reference to the object created; pass to dandelion.Kill() to immediately remove
function dandelion.Spawn(name, x, y, vars)
    if not name or not x or not y then
        error("dandelion.Spawn is missing name, x, or y")
    end

    return spawn(name, x, y, vars, "dandelion.Spawn")
end

---Immediately removes the passed particle or emitter.
---@param reference table a reference to the particle or emitter to kill
function dandelion.Kill(reference)
    if not reference then return end
    reference.killed = true
end

---Draws EVERY particle group, except the ones which match the passed names.
---If no names are provided, draws every particle group.
---@param ... unknown  A list of group names to ignore.
function dandelion.DrawExcept(...)
    if usagi.elapsed > last_emit then
        emit()
    end
    local ignored_groups = { ... }
    for group, _ in pairs(particle_caches) do
        draw_particle_group(group, contains(ignored_groups, group))
    end
end

---Draws ONLY particle groups which match the passed names.
---If no names are provided, draws nothing.
---@param ... unknown  A list of group names to draw.
function dandelion.DrawGroups(...)
    if usagi.elapsed > last_emit then
        emit()
    end
    local included_groups = { ... }
    for group, _ in pairs(particle_caches) do
        draw_particle_group(group, not contains(included_groups, group))
    end
end

---Returns a table containing the names of all available particles.
---@return table
function dandelion.Particles()
    local to_return = {}
    for k, _ in pairs(particle_metatables) do
        table.insert(to_return, k)
    end
    return to_return
end

---Returns a table containing the names of all available emitters.
---@return table
function dandelion.Emitters()
    local to_return = {}
    for k, v in pairs(emitter_metatables) do
        table.insert(to_return, k)
    end
    return to_return
end

---Removes all emitters and particles
function dandelion.ClearAll()
    dandelion.ClearEmitters()
    dandelion.ClearParticles()
end

---Removes all emitters.
function dandelion.ClearEmitters()
    emitter_cache = {}
end

---Removes all particles.
function dandelion.ClearParticles()
    for group, _ in pairs(particle_caches) do
        particle_caches[group] = {}
        open_indices[group] = {}
    end
    alive_particles = 0
end

---Removes all particles contained within the provided groups.
---If no groups are provided, no particles will be removed.
---@param ... unknown A list of group names to clear particles from.
function dandelion.ClearGroups(...)
    local groups = { ... }
    for _, group in pairs(groups) do
        if particle_caches[group] then
            alive_particles -= #particle_caches[group]
            particle_caches[group] = {}
        end
    end
end

local fps_history = {}
for i = 1, 60 do
    fps_history[i] = 0
end

---Displays the number of emitters and the number of particles in the top left of the screen.
---Displays FPS average and the last 60 frames of FPS history as a bar graph in the bottom right of the screen.
---@param dt number dt is required for FPS calculations
function dandelion.Debug(dt)
    -- stats
    outlined_text("emitters: " .. #emitter_cache, 6, 4, gfx.COLOR_TRUE_WHITE, gfx.COLOR_BLACK)
    outlined_text("particles: " .. alive_particles, 6, 14, gfx.COLOR_TRUE_WHITE, gfx.COLOR_BLACK)

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
