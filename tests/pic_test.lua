package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local Pic = H.need("pic")

-- One tile: row 0 has low plane 0xFF, high plane 0x00 (all colour 1);
-- row 1 has low 0x00, high 0xFF (all colour 2); row 2 has both (colour 3);
-- the rest are colour 0.
local function tile()
  local t = { 0xFF, 0x00, 0x00, 0xFF, 0xFF, 0xFF }
  for _ = 7, 16 do t[#t + 1] = 0 end
  return t
end

H.test("pic: tilePixels decodes the two bit planes", function()
  local px = Pic.tilePixels(tile(), 0)
  H.eq(#px, 64)
  H.eq(px[1], 1); H.eq(px[8], 1)
  H.eq(px[9], 2); H.eq(px[16], 2)
  H.eq(px[17], 3)
  H.eq(px[25], 0)
end)

H.test("pic: leftmost pixel is the high bit", function()
  local px = Pic.tilePixels({ 0x80, 0x00 }, 0)
  H.eq(px[1], 1); H.eq(px[2], 0)
end)

H.test("pic: identityMap counts up", function()
  H.arrayEq(Pic.identityMap(2), { 0, 1, 2, 3 })
end)

-- Four tiles, each a solid colour index 0..3.
local function solidTiles()
  local d = {}
  for t = 0, 3 do
    for _ = 1, 8 do
      d[#d + 1] = (t % 2 == 1) and 0xFF or 0x00 -- low plane
      d[#d + 1] = (t >= 2) and 0xFF or 0x00     -- high plane
    end
  end
  return d
end

H.test("pic: compose in column order", function()
  local px, w, h = Pic.compose(solidTiles(), Pic.identityMap(2), 2, "columns")
  H.eq(w, 16); H.eq(h, 16)
  -- position 0 = (row0,col0), 1 = (row1,col0), 2 = (row0,col1), 3 = (row1,col1)
  H.eq(px[1], 0)            -- row0 col0 -> tile 0 -> colour 0
  H.eq(px[8 * 16 + 1], 1)   -- row1 col0 -> tile 1 -> colour 1
  H.eq(px[9], 2)            -- row0 col1 -> tile 2 -> colour 2
  H.eq(px[8 * 16 + 9], 3)   -- row1 col1 -> tile 3 -> colour 3
end)

H.test("pic: compose in row order", function()
  local px = Pic.compose(solidTiles(), Pic.identityMap(2), 2, "rows")
  H.eq(px[1], 0)            -- row0 col0 -> tile 0
  H.eq(px[9], 1)            -- row0 col1 -> tile 1
  H.eq(px[8 * 16 + 1], 2)   -- row1 col0 -> tile 2
  H.eq(px[8 * 16 + 9], 3)   -- row1 col1 -> tile 3
end)

H.test("pic: compose honours a non-identity map", function()
  local px = Pic.compose(solidTiles(), { 3, 3, 3, 3 }, 2, "rows")
  H.eq(px[1], 3); H.eq(px[8 * 16 + 9], 3)
end)
