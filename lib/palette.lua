-- Crystal's own colours for a species.  Every Pokemon has two middle colours;
-- its sprite is drawn with white, colour one, colour two and black.
local need = ...
local Rom, A = need("rom"), need("addresses")

local Palette = {}

local function widen(c5) return c5 * 8 + math.floor(c5 / 4) end -- 31 -> 255

local function colour(rom, offset)
  local v = rom:u16(offset)
  return { widen(v % 32), widen(math.floor(v / 32) % 32), widen(math.floor(v / 1024) % 32) }
end

-- { white, colour one, colour two, black }, each { r, g, b } in 0..255.
-- dex is the national dex number, 1..251.
function Palette.colors(rom, dex)
  local base = Rom.offset(A.pokemonPalettes.bank, A.pokemonPalettes.addr) + 8 * dex
  return { { 255, 255, 255 }, colour(rom, base), colour(rom, base + 2), { 0, 0, 0 } }
end

return Palette
