package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local unpack = table.unpack or unpack
local Rom, A, Palette = H.need("rom"), H.need("addresses"), H.need("palette")

-- 5-bit RGB packed the way the Game Boy Color stores it
local function rgb(r, g, b)
  local v = r + g * 32 + b * 1024
  return string.char(v % 256, math.floor(v / 256))
end

-- a ROM just big enough to hold the palette table, with species 1 and 25 set
local function fakeRom()
  local base = Rom.offset(A.pokemonPalettes.bank, A.pokemonPalettes.addr)
  local raw = {}
  for i = 1, base + 8 * 30 do raw[i] = "\0" end
  local function put(species, normal1, normal2)
    local at = base + 8 * species + 1
    local bytes = rgb(unpack(normal1)) .. rgb(unpack(normal2))
    for i = 1, #bytes do raw[at + i - 1] = bytes:sub(i, i) end
  end
  put(1, { 12, 31, 11 }, { 31, 10, 6 })
  put(25, { 29, 26, 5 }, { 26, 6, 0 })
  return Rom.new(table.concat(raw))
end

H.test("palette: a sprite is drawn white, colour one, colour two, black", function()
  local c = Palette.colors(fakeRom(), 1)
  H.eq(#c, 4)
  H.eq(c[1][1] .. "," .. c[1][2] .. "," .. c[1][3], "255,255,255", "white")
  H.eq(c[4][1] .. "," .. c[4][2] .. "," .. c[4][3], "0,0,0", "black")
end)

H.test("palette: 5-bit channels widen to 8 bits with 31 reaching 255", function()
  local c = Palette.colors(fakeRom(), 1)
  -- (12, 31, 11): 12*8+3, 255, 11*8+2
  H.eq(c[2][1], 99)
  H.eq(c[2][2], 255)
  H.eq(c[2][3], 90)
  -- (31, 10, 6)
  H.eq(c[3][1], 255)
  H.eq(c[3][2], 82)
  H.eq(c[3][3], 49)
end)

H.test("palette: each species reads its own entry", function()
  local rom = fakeRom()
  local a, b = Palette.colors(rom, 1), Palette.colors(rom, 25)
  H.eq(a[2][1] ~= b[2][1], true)
  -- Pikachu (29, 26, 5)
  H.eq(b[2][1], 29 * 8 + 7)
  H.eq(b[2][2], 26 * 8 + 6)
  H.eq(b[2][3], 5 * 8 + 1)
end)

if H.rom() then
  H.test("palette: the real ROM gives Bulbasaur's green and red and Pikachu's yellow", function()
    local rom = Rom.new(H.rom())
    local bulb, pika = Palette.colors(rom, 1), Palette.colors(rom, 25)
    H.eq(bulb[2][2] > bulb[2][1] and bulb[2][2] > bulb[2][3], true, "green first colour")
    H.eq(bulb[3][1] > bulb[3][2], true, "red second colour")
    H.eq(pika[2][1] > 200 and pika[2][2] > 200 and pika[2][3] < 60, true, "yellow")
  end)
else
  H.skip("palette: real ROM", "no ROM found (set CRYSTAL_ROM)")
end

-- Crystal draws a shiny with the SAME picture and the species' second pair of
-- colours, stored right after the normal pair (4 bytes in).  There is no shiny
-- art in the ROM.
local function shinyRom()
  local base = Rom.offset(A.pokemonPalettes.bank, A.pokemonPalettes.addr)
  local raw = {}
  for i = 1, base + 8 * 30 do raw[i] = "\0" end
  local function put(species, n1, n2, s1, s2)
    local at = base + 8 * species + 1
    local bytes = rgb(unpack(n1)) .. rgb(unpack(n2)) .. rgb(unpack(s1)) .. rgb(unpack(s2))
    for i = 1, #bytes do raw[at + i - 1] = bytes:sub(i, i) end
  end
  put(4, { 31, 20, 8 }, { 31, 8, 3 }, { 24, 28, 31 }, { 8, 10, 31 })
  return Rom.new(table.concat(raw))
end

H.test("palette: shiny asks for the second pair, white and black unchanged", function()
  local c = Palette.colors(shinyRom(), 4, true)
  H.eq(#c, 4)
  H.eq(c[1][1] .. "," .. c[1][2] .. "," .. c[1][3], "255,255,255", "white")
  H.eq(c[4][1] .. "," .. c[4][2] .. "," .. c[4][3], "0,0,0", "black")
  -- shiny colour one (24, 28, 31): 24*8+6, 28*8+7, 255
  H.eq(c[2][1], 198)
  H.eq(c[2][2], 231)
  H.eq(c[2][3], 255)
  -- shiny colour two (8, 10, 31): 8*8+2, 10*8+2, 255
  H.eq(c[3][1], 66)
  H.eq(c[3][2], 82)
  H.eq(c[3][3], 255)
end)

H.test("palette: leaving shiny out, or false, still gives the normal pair", function()
  local rom = shinyRom()
  local plain, off = Palette.colors(rom, 4), Palette.colors(rom, 4, false)
  for i = 1, 4 do
    for ch = 1, 3 do H.eq(off[i][ch], plain[i][ch], "false matches the default") end
  end
  -- normal colour one (31, 20, 8): 31*8+7 = 255, 20*8+5, 8*8+2
  H.eq(plain[2][1], 255)
  H.eq(plain[2][2], 165)
  H.eq(plain[2][3], 66)
  H.eq(plain[2][1] ~= Palette.colors(rom, 4, true)[2][1], true, "and the pairs differ")
end)

if H.rom() then
  H.test("palette: the real ROM's shiny pair differs from the normal one for every Kanto species", function()
    local rom = Rom.new(H.rom())
    local same = {}
    for dex = 1, 151 do
      local n, s = Palette.colors(rom, dex), Palette.colors(rom, dex, true)
      if n[2][1] == s[2][1] and n[2][2] == s[2][2] and n[2][3] == s[2][3]
         and n[3][1] == s[3][1] and n[3][2] == s[3][2] and n[3][3] == s[3][3] then
        same[#same + 1] = dex
      end
    end
    H.eq(#same, 0, "species whose shiny colours equal the normal ones: " .. table.concat(same, ","))
  end)

  H.test("palette: the real ROM makes a shiny Gyarados red and a shiny Magikarp gold", function()
    local rom = Rom.new(H.rom())
    local gyaN, gyaS = Palette.colors(rom, 130), Palette.colors(rom, 130, true)
    H.eq(gyaN[3][3] > gyaN[3][1], true, "a normal Gyarados' second colour is blue")
    H.eq(gyaS[3][1] > gyaS[3][3], true, "a shiny Gyarados' second colour is red")
    local magS = Palette.colors(rom, 129, true)
    H.eq(magS[2][1] > 200 and magS[2][2] > 150 and magS[2][3] < 120, true, "a shiny Magikarp is gold")
  end)
end
