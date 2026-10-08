package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local Sparkle = H.need("sparkle")

-- Crystal's shiny animation (BattleAnim_SendOutMon, .Shiny): eight sparkles on
-- a circle of radius 16, one every 4 frames, each living 15 frames and stepping
-- through OAM sets 74, 14, 15, 14, 15 at 3 frames each; the script ends 32
-- frames after the last one appears.

H.test("sparkle: eight sparkles, one every four frames, sixty frames in all", function()
  H.eq(Sparkle.COUNT, 8)
  for k = 0, 7 do H.eq(Sparkle.spawnFrame(k), 4 * k, "sparkle " .. k) end
  H.eq(Sparkle.TOTAL, 60, "the script ends 32 frames after the last sparkle appears")
  H.eq(Sparkle.spawnFrame(7) + 32, Sparkle.TOTAL)
end)

H.test("sparkle: they sit on a circle of radius 16, clockwise from the right", function()
  local want = { [0] = { 16, 0 }, [1] = { 11, 11 }, [2] = { 0, 16 }, [3] = { -11, 11 },
    [4] = { -16, 0 }, [5] = { -11, -11 }, [6] = { 0, -16 }, [7] = { 11, -11 } }
  for k = 0, 7 do
    local dx, dy = Sparkle.offset(k)
    H.eq(dx, want[k][1], "x of sparkle " .. k)
    H.eq(dy, want[k][2], "y of sparkle " .. k)
  end
end)

H.test("sparkle: one sparkle steps 74, 14, 15, 14, 15 for three frames each, then is gone", function()
  H.eq(Sparkle.frameId(0, -1), nil, "not yet")
  local want = { 74, 74, 74, 14, 14, 14, 15, 15, 15, 14, 14, 14, 15, 15, 15 }
  for age = 0, 14 do H.eq(Sparkle.frameId(0, age), want[age + 1], "age " .. age) end
  H.eq(Sparkle.frameId(0, 15), nil, "gone after 15 frames")
  -- the same steps start later for a later sparkle
  H.eq(Sparkle.frameId(3, 11), nil, "sparkle 3 appears at frame 12")
  H.eq(Sparkle.frameId(3, 12), 74)
  H.eq(Sparkle.frameId(3, 15), 14)
end)

H.test("sparkle: what is on screen at a frame", function()
  local function ids(frame)
    local out = {}
    for _, s in ipairs(Sparkle.visible(frame)) do out[#out + 1] = s.k .. ":" .. s.id end
    return table.concat(out, " ")
  end
  H.eq(ids(0), "0:74")
  H.eq(ids(10), "0:14 1:15 2:74")
  H.eq(ids(28), "4:15 5:15 6:14 7:74", "sparkle 4 is on its last step, 3 is gone")
  H.eq(ids(59), "", "nothing left at the end")
  H.eq(ids(60), "")
  local first = Sparkle.visible(0)[1]
  H.eq(first.dx, 16)
  H.eq(first.dy, 0)
end)

H.test("sparkle: a fractional frame counts as the frame it is in", function()
  H.eq(#Sparkle.visible(9.9), #Sparkle.visible(9))
  H.eq(Sparkle.visible(9.9)[1].id, Sparkle.visible(9)[1].id)
end)

H.test("sparkle: how many have appeared by a frame, for the chime", function()
  H.eq(Sparkle.appeared(-1), 0)
  H.eq(Sparkle.appeared(0), 1)
  H.eq(Sparkle.appeared(3.9), 1)
  H.eq(Sparkle.appeared(4), 2)
  H.eq(Sparkle.appeared(28), 8)
  H.eq(Sparkle.appeared(500), 8, "never more than eight")
end)

H.test("sparkle: done is the end of the script", function()
  H.eq(Sparkle.done(59.9), false)
  H.eq(Sparkle.done(60), true)
end)

-- ------------------------------------------------------------------ the ROM

local Rom = H.need("rom")
local EXPECTED_CHIME = string.char(0xDB, 0x00, 0x00, 0xD2, 0x00, 0x07, 0x00, 0xD2, 0x40, 0x07,
  0x00, 0xD2, 0x80, 0x07, 0x00, 0xD2, 0xC0, 0x07, 0x0A, 0xE1, 0xE0, 0x07, 0x01, 0x00, 0x00, 0x00, 0xFF)

H.test("sparkle: a ROM that is not Crystal gives no art and no chime, without raising", function()
  local junk = Rom.new(string.rep("\0", 0x100000))
  local tiles, why = Sparkle.tiles(junk)
  H.eq(tiles, nil)
  H.eq(type(why), "string", "says why")
  H.eq(Sparkle.chime(junk), nil)
end)

if H.rom() then
  local rom = Rom.new(H.rom())

  H.test("sparkle: the real ROM's speed graphics decode to nine tiles", function()
    local tiles = assert(Sparkle.tiles(rom))
    for t = 0, 8 do
      H.eq(#tiles[t], 64, "tile " .. t .. " has 64 pixels")
    end
    -- tile 0 is the 8x8 four-point sparkle: its middle row is orange tips round a yellow core
    local function row(t, r) local s = {} for x = 0, 7 do s[#s + 1] = tiles[t][r * 8 + x + 1] end return table.concat(s) end
    H.eq(row(0, 4), "22111220", "tile 0, the middle row")
    H.eq(row(0, 0), "00000000", "tile 0, the empty top row")
    H.eq(row(6, 7), "22211111", "tile 6, the bottom row of the star's quadrant")
    H.eq(row(6, 0), "00000002", "tile 6, the arm along the right edge")
  end)

  H.test("sparkle: the 16x16 star is that quadrant mirrored four ways", function()
    local tiles = assert(Sparkle.tiles(rom))
    local sprites = Sparkle.sprites(tiles)
    local star = sprites.star
    H.eq(star.w, 16)
    H.eq(star.h, 16)
    H.eq(#star.pixels, 256)
    local function at(x, y) return star.pixels[y * 16 + x + 1] end
    for y = 0, 15 do
      for x = 0, 15 do
        H.eq(at(x, y), at(15 - x, y), ("mirrored left to right at %d,%d"):format(x, y))
        H.eq(at(x, y), at(x, 15 - y), ("mirrored top to bottom at %d,%d"):format(x, y))
      end
    end
    -- the quadrant's own pixels sit unflipped in the top-left
    for y = 0, 7 do
      for x = 0, 7 do H.eq(at(x, y), tiles[6][y * 8 + x + 1], ("top-left at %d,%d"):format(x, y)) end
    end
    H.eq(at(7, 7), 1, "the core is yellow")
    H.eq(at(0, 0), 0, "the corners are empty")
    -- the two small sparkles are tiles 0 and 1 as they are
    H.eq(sprites.large.w, 8)
    H.eq(sprites.small.w, 8)
    for i = 1, 64 do
      H.eq(sprites.large.pixels[i], tiles[0][i], "large sparkle pixel " .. i)
      H.eq(sprites.small.pixels[i], tiles[1][i], "small sparkle pixel " .. i)
    end
  end)

  H.test("sparkle: the real ROM holds Crystal's chime exactly once", function()
    H.eq(Sparkle.chime(rom), EXPECTED_CHIME)
    local first = rom.raw:find(EXPECTED_CHIME, 1, true)
    H.eq(rom.raw:find(EXPECTED_CHIME, first + 1, true), nil, "only once")
  end)
else
  H.skip("sparkle: real ROM", "no ROM found (set CRYSTAL_ROM)")
end

-- ---------------------------------------------------------------- where it goes

-- The ring is centred on the picture.  The engine places an enemy front pic in
-- a 7x7 tile slot at hlcoord 12,0, centred across and bottom-aligned (see
-- enemyPicXY in BattleState), so its centre depends on the picture's size; the
-- player's back pic stands with its feet on y=96 from x=8.
H.test("sparkle: the ring is centred on the enemy picture where the engine puts it", function()
  local function at(w, h) local x, y = Sparkle.anchor(true, w, h) return x .. "," .. y end
  H.eq(at(56, 56), "124,28", "a full 7x7 picture: the middle of the slot")
  H.eq(at(40, 40), "124,36", "a 5x5 picture sits low in its slot")
  H.eq(at(32, 32), "128,40", "a 4x4 one lower and a tile to the right of the slot's middle")
  H.eq(at(64, 64), "128,32", "a bigger picture grows out of the slot's top-left, not its middle")
end)

H.test("sparkle: the ring is centred on the player's picture", function()
  local x, y = Sparkle.anchor(false, 48, 48)
  H.eq(x, 32)
  H.eq(y, 72, "feet on y=96")
  x, y = Sparkle.anchor(false, 40, 40)
  H.eq(x, 28)
  H.eq(y, 76)
end)

H.test("sparkle: with no picture to measure, the slot's own centres", function()
  local ex, ey = Sparkle.anchor(true)
  H.eq(ex, 124)
  H.eq(ey, 28)
  local px, py = Sparkle.anchor(false)
  H.eq(px, 36)
  H.eq(py, 68)
end)
