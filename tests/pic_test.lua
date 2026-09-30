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

H.test("pic: mirror reverses each row", function()
  H.arrayEq(Pic.mirror({ 1, 2, 3, 0, 1, 2 }, 3), { 3, 2, 1, 2, 1, 0 })
end)

H.test("pic: matte clears only the background connected to the edge", function()
  -- a ring of colour 1 around an enclosed colour-0 centre, colour 0 outside
  local px = {
    0, 0, 0, 0, 0,
    0, 1, 1, 1, 0,
    0, 1, 0, 1, 0,
    0, 1, 1, 1, 0,
    0, 0, 0, 0, 0,
  }
  H.arrayEq(Pic.matte(px, 5), {
    0, 0, 0, 0, 0,
    0, 1, 1, 1, 0,
    0, 1, 1, 1, 0,
    0, 1, 1, 1, 0,
    0, 0, 0, 0, 0,
  })
end)

H.test("pic: matte does not leak through a diagonal gap", function()
  -- the centre touches the outside only at corners, so it is enclosed
  local px = { 0, 1, 0, 1, 0, 1, 0, 1, 0 }
  H.arrayEq(Pic.matte(px, 3), { 0, 1, 0, 1, 1, 1, 0, 1, 0 })
end)

H.test("pic: matte keeps a pic with no colour 0 fully opaque", function()
  local px = { 1, 2, 3, 3, 2, 1, 1, 1, 1 }
  H.arrayEq(Pic.matte(px, 3), { 1, 1, 1, 1, 1, 1, 1, 1, 1 })
end)

H.test("pic: mirror also works on an alpha plane", function()
  H.arrayEq(Pic.mirror({ 1, 0, 0, 0, 1, 1 }, 3), { 0, 0, 1, 1, 1, 0 })
end)

-- Known blemishes.  A single colour-0 pixel boxed in by the outline is often a
-- gap in the sprite that the edge fill cannot reach (Pikachu's tail base), but
-- it can equally be a glint in an eye, and the two look the same up close.  So
-- specks are cleared only where a species' list names them, and only if the
-- pixel really is a walled-in white pixel with black on all four sides.
H.test("pic: matte clears a speck the species list names", function()
  local px = {
    0, 0, 0, 0, 0,
    0, 0, 3, 0, 0,
    0, 3, 0, 3, 0,
    0, 0, 3, 0, 0,
    0, 0, 0, 0, 0,
  }
  local a = Pic.matte(px, 5, { { 2, 2 } })
  H.eq(a[13], 0, "the named speck is transparent")
  H.eq(a[8], 1, "the outline around it stays opaque")
end)

H.test("pic: matte leaves an identical speck that is not on the list", function()
  local px = {
    0, 0, 0, 0, 0,
    0, 0, 3, 0, 0,
    0, 3, 0, 3, 0,
    0, 0, 3, 0, 0,
    0, 0, 0, 0, 0,
  }
  H.eq(Pic.matte(px, 5)[13], 1, "no list, no clearing")
  H.eq(Pic.matte(px, 5, { { 0, 0 } })[13], 1, "a different coordinate, no clearing")
end)

H.test("pic: a listed pixel that is not a speck is left alone", function()
  -- the same coordinate in another animation frame can be plain outline
  local outline = {
    0, 0, 0, 0, 0,
    0, 0, 3, 0, 0,
    0, 3, 3, 3, 0,
    0, 0, 3, 0, 0,
    0, 0, 0, 0, 0,
  }
  H.eq(Pic.matte(outline, 5, { { 2, 2 } })[13], 1, "black outline stays")
  local shine = {
    0, 0, 0, 0, 0,
    0, 0, 3, 0, 0,
    0, 3, 0, 1, 0,
    0, 0, 3, 0, 0,
    0, 0, 0, 0, 0,
  }
  H.eq(Pic.matte(shine, 5, { { 2, 2 } })[13], 1, "a white pixel touching body colour stays")
  H.eq(Pic.matte(outline, 5, { { 9, 9 } })[13], 1, "a coordinate outside the pic is ignored")
end)
