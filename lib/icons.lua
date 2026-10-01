-- Crystal's party menu icons.  Each Pokemon maps to one of 38 shared shapes;
-- a shape is 16x16 with two animation frames, eight 2bpp tiles in all.
local need = ...
local Rom, A, Pic = need("rom"), need("addresses"), need("pic")

local Icons = {}

-- How Red, Blue and Yellow show object colours (OBP0 %11010000): colour 1
-- as shade 0, colour 2 as shade 1, colour 3 as shade 3.  Colour 0 is never
-- drawn.  Indexed by colour + 1, in the grey values the engine's own art uses.
Icons.SHADES = { 255, 255, 170, 0 }

-- The icon shape for national dex number `dex`.
function Icons.idFor(rom, dex)
  return rom:u8(Rom.offset(A.menuIcons.bank, A.menuIcons.addr) + dex - 1)
end

local function pointerOf(rom, id)
  local table_ = Rom.offset(A.menuIcons.bank, A.menuIcons.addr) + A.menuIconSpecies
  return rom:u16(table_ + 2 * id)
end

-- The sheet's colour indices, 16 wide and 32 tall: frame one on top, frame two
-- below it, each frame's four tiles in reading order.
function Icons.pixels(rom, id)
  local base = Rom.offset(A.menuIcons.bank, pointerOf(rom, id))
  local bytes = {}
  for i = 0, 127 do bytes[i + 1] = rom:u8(base + i) end
  local out = {}
  for tile = 0, 7 do
    local tp = Pic.tilePixels(bytes, tile)
    local tx, ty = (tile % 2) * 8, math.floor(tile / 2) * 8
    for y = 0, 7 do
      for x = 0, 7 do
        out[(ty + y) * 16 + tx + x + 1] = tp[y * 8 + x + 1]
      end
    end
  end
  return out
end

-- Colour 0 is see-through; everything else is drawn.
function Icons.alpha(pixels)
  local out = {}
  for i = 1, #pixels do out[i] = pixels[i] == 0 and 0 or 1 end
  return out
end

return Icons
