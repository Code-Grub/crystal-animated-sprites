package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local Rom, A, Icons = H.need("rom"), H.need("addresses"), H.need("icons")

-- a ROM with just the icon tables: species 1 uses icon 7, icon 7's graphics
-- are eight solid tiles whose colour index is the tile number mod 4
local function fakeRom()
  local base = Rom.offset(A.menuIcons.bank, A.menuIcons.addr)
  local gfxAddr = 0x7000
  local size = Rom.offset(A.menuIcons.bank, gfxAddr) + 128
  local raw = {}
  for i = 1, size do raw[i] = "\0" end
  raw[base + 1] = string.char(7)                       -- species 1 -> icon 7
  local ptrs = base + A.menuIconSpecies              -- IconPointers follows
  local at = ptrs + 2 * 7
  raw[at + 1] = string.char(gfxAddr % 256)
  raw[at + 2] = string.char(math.floor(gfxAddr / 256))
  local gfx = Rom.offset(A.menuIcons.bank, gfxAddr)
  for tile = 0, 7 do
    local c = tile % 4
    local lo = (c % 2 == 1) and 0xFF or 0
    local hi = (c >= 2) and 0xFF or 0
    for row = 0, 7 do
      raw[gfx + tile * 16 + row * 2 + 1] = string.char(lo)
      raw[gfx + tile * 16 + row * 2 + 2] = string.char(hi)
    end
  end
  return Rom.new(table.concat(raw))
end

H.test("icons: a species maps to its icon shape", function()
  H.eq(Icons.idFor(fakeRom(), 1), 7)
end)

H.test("icons: the sheet is 16 wide and two 16-tall frames, tiles in reading order", function()
  local px = Icons.pixels(fakeRom(), 7)
  H.eq(#px, 16 * 32)
  local function at(x, y) return px[y * 16 + x + 1] end
  -- frame one: tiles 0..3 as top-left, top-right, bottom-left, bottom-right
  H.eq(at(0, 0), 0);  H.eq(at(7, 7), 0)     -- tile 0: colour 0
  H.eq(at(8, 0), 1);  H.eq(at(15, 7), 1)    -- tile 1: colour 1
  H.eq(at(0, 8), 2);  H.eq(at(7, 15), 2)    -- tile 2: colour 2
  H.eq(at(8, 8), 3);  H.eq(at(15, 15), 3)   -- tile 3: colour 3
  -- frame two follows below: tiles 4..7
  H.eq(at(0, 16), 0); H.eq(at(8, 16), 1)
  H.eq(at(0, 24), 2); H.eq(at(8, 24), 3)
end)

H.test("icons: colour 0 is see-through and everything else is drawn", function()
  local alpha = Icons.alpha(Icons.pixels(fakeRom(), 7))
  H.eq(alpha[1], 0, "tile 0 is colour 0")
  H.eq(alpha[9], 1, "tile 1 is colour 1")
  H.eq(#alpha, 16 * 32)
end)

H.test("icons: the grey shades match how Red, Blue and Yellow draw object colours", function()
  -- OBP0 shows colour 1 as shade 0 (white), colour 2 as shade 1, colour 3 as shade 3
  H.eq(Icons.SHADES[2], 255)
  H.eq(Icons.SHADES[3], 170)
  H.eq(Icons.SHADES[4], 0)
end)

if H.rom() then
  H.test("icons: the real ROM gives birds the bird icon and Pikachu its own", function()
    local rom = Rom.new(H.rom())
    H.eq(Icons.idFor(rom, 16), 7, "Pidgey")
    H.eq(Icons.idFor(rom, 17), 7, "Pidgeotto")
    H.eq(Icons.idFor(rom, 25), 4, "Pikachu")
    H.eq(Icons.idFor(rom, 1), 22, "Bulbasaur")
    local px = Icons.pixels(rom, 4)
    local drawn, dark = 0, 0
    for i = 1, #px do
      if px[i] ~= 0 then drawn = drawn + 1 end
      if px[i] == 3 then dark = dark + 1 end
    end
    H.eq(drawn > 80 and drawn < 440, true, "a plausible number of drawn pixels, got " .. drawn)
    H.eq(dark > 20, true, "it has an outline")
  end)
  H.test("icons: all 151 species have an icon with graphics", function()
    local rom = Rom.new(H.rom())
    for dex = 1, 151 do
      local id = Icons.idFor(rom, dex)
      H.eq(id >= 1 and id <= A.iconCount, true, "dex " .. dex .. " icon id " .. id)
      local px = Icons.pixels(rom, id)
      local drawn = 0
      for i = 1, #px do if px[i] ~= 0 then drawn = drawn + 1 end end
      H.eq(drawn > 20, true, "dex " .. dex .. " icon is not blank")
    end
  end)
else
  H.skip("icons: real ROM", "no ROM found (set CRYSTAL_ROM)")
end
