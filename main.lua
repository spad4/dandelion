local dand = require("dandelion")

function _config()
  ---@type Usagi.Config
  return { name = "Game", game_id = "com.usagiengine.YOURGAMENAME" }
end

function _init()
  -- Live reload preserves globals across saved edits but resets locals.
  -- Stash mutable game state in a capitalized global like `State` so it
  -- survives reloads; F5 calls _init again to reset.
  State = {}
end

local counter = 1

function _update(dt)
  if input.mouse_pressed(input.MOUSE_LEFT) then
    dand.line(input.mouse())
  end

  if input.mouse_held(input.MOUSE_RIGHT) then
    counter += 1
    if counter > 1 then
      dand.line(input.mouse())
      counter = 0
    end
  end

  if input.mouse_released(input.MOUSE_RIGHT) then
    counter = 1
  end
end

function _draw(dt)
  gfx.clear(gfx.COLOR_BLACK)
  dand:Draw()
  dand:Debug()
end
