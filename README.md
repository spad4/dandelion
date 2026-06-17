![](https://github.com/spad4/dandelion/blob/main/assets/ezgif-21a2bfb3a56a7057.gif?raw=true)
Dandelion is a data-driven particle library for [Usagi Engine](https://usagiengine.com/). Design complex and beautiful particles without writing a single line of code.

## Installation
Download the latest release from releases and extract. Paste the contents (`dandelion.lua` and `data`) into the top level of your Usagi project.

## Usage
Import the module:
```lua
dandelion = require("dandelion")
```

Call `dandelion.Draw` anywhere in your `_draw` loop:
```lua
function _draw(dt)
  gfx.clear(gfx.COLOR_BLACK)
  dand.Draw()
end
```

To spawn a particle, call `dandelion.<particle_name>(x, y)`. An example which spawns a particle at your cursor:

```lua
function _update(dt)
  if input.mouse_pressed(input.MOUSE_LEFT) then
    dandelion.dandelion(input.mouse())
  end
end
```
> **NOTE:** `dandelion` is available only if the default particles are installed.

To create a new particle, add an object entry to `dandelion/particles.json`. To create a new emitter, add an object entry to `dandelion/emitters.json`