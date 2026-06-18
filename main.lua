local dandelion = require("dandelion")

function _config()
  ---@type Usagi.Config
  return { name = "Dandelion Field" }
end

function _init()
  -- Live reload preserves globals across saved edits but resets locals.
  -- Stash mutable game state in a capitalized global like `State` so it
  -- survives reloads; F5 calls _init again to reset.
  State = {
    emitter_index = 1
  }
end

local counter = 1
local emitters = dandelion.Emitters()

function _update(dt)

  if input.key_pressed(input.KEY_SPACE) then
    State.emitter_index = (State.emitter_index % #emitters) + 1
  end

  if input.key_pressed(input.KEY_C) then
    dandelion.ClearAll()
  end

  if input.mouse_pressed(input.MOUSE_LEFT) then
    dandelion[emitters[State.emitter_index]](input.mouse())
  end

  if input.mouse_held(input.MOUSE_RIGHT) then
    counter += 1
    if counter > 1 then
      dandelion[emitters[State.emitter_index]](input.mouse())
      counter = 0
    end
  end

  if input.mouse_released(input.MOUSE_RIGHT) then
    counter = 1
  end
end

function outlined_text(text, x, y, color, outline)

  for i = -1, 1, 1 do
    for j = -1, 1, 1 do
      gfx.text(text, x+i, y+j, outline)
    end
  end
  gfx.text(text, x, y, color)
end

function _draw(dt)
  gfx.clear(gfx.COLOR_BLACK)
  dandelion.Draw()
  dandelion.Debug(dt)
  outlined_text(emitters[State.emitter_index], 4, 170, gfx.COLOR_TRUE_WHITE, gfx.COLOR_BLACK)
end
