package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local Pic, PNG = H.need("pic"), H.need("png")

-- '.' is transparent, '#' is opaque.  Returns the alpha array and the width.
local function grid(rows)
  local alpha = {}
  for _, row in ipairs(rows) do
    for c in row:gmatch(".") do alpha[#alpha + 1] = c == "#" and 1 or 0 end
  end
  return alpha, #rows[1]
end

local function at(alpha, w, x, y) return alpha[y * w + x + 1] end

local ring = {
  ".......",
  ".#####.",
  ".#...#.",
  ".#####.",
  ".#.#.#.",
  ".#.#.#.",
}

H.test("gaps: an enclosed hole is marked as a deliberate gap", function()
  local alpha, w = grid(ring)
  local out = Pic.gaps(alpha, w)
  for x = 2, 4 do H.eq(at(out, w, x, 2), 2, "hole pixel " .. x) end
end)

H.test("gaps: a hole open only at the bottom edge is a gap too", function()
  local alpha, w = grid(ring)
  local out = Pic.gaps(alpha, w)
  for y = 4, 5 do
    H.eq(at(out, w, 2, y), 2, "left gap, row " .. y)
    H.eq(at(out, w, 4, y), 2, "right gap, row " .. y)
  end
end)

H.test("gaps: background that reaches the left, right or top stays plain transparent", function()
  local alpha, w = grid(ring)
  local out = Pic.gaps(alpha, w)
  for y = 0, 5 do
    H.eq(at(out, w, 0, y), 0, "left column " .. y)
    H.eq(at(out, w, 6, y), 0, "right column " .. y)
  end
  for x = 0, 6 do H.eq(at(out, w, x, 0), 0, "top row " .. x) end
end)

H.test("gaps: a gap that opens into the empty frame under the figure is still a gap", function()
  -- the band under the feet reaches both side edges, but it is outside the
  -- figure's own bounding box, which is where the paper rule floods
  local alpha, w = grid({
    ".......",
    ".#####.",
    ".#.#.#.",
    ".#.#.#.",
    ".......",
    ".......",
  })
  local out = Pic.gaps(alpha, w)
  H.eq(at(out, w, 2, 2), 2, "gap between the legs")
  H.eq(at(out, w, 4, 3), 2, "gap between the legs, bottom row")
  H.eq(at(out, w, 3, 4), 0, "the empty band under the figure")
  H.eq(at(out, w, 0, 2), 0, "left of the figure")
end)

H.test("gaps: opaque pixels are untouched and the input is not modified", function()
  local alpha, w = grid(ring)
  local before = table.concat(alpha, ",")
  local out = Pic.gaps(alpha, w)
  H.eq(table.concat(alpha, ","), before, "input")
  H.eq(at(out, w, 1, 1), 1)
  H.eq(at(out, w, 3, 4), 1)
end)

-- alpha byte of pixel x in a one-row grayscale+alpha PNG
local function alphaByte(png, w, x)
  local pos, idat = 9, {}
  while pos <= #png do
    local a, b, c, d = png:byte(pos, pos + 3)
    local len = ((a * 256 + b) * 256 + c) * 256 + d
    if png:sub(pos + 4, pos + 7) == "IDAT" then idat[#idat + 1] = png:sub(pos + 8, pos + 7 + len) end
    pos = pos + 12 + len
  end
  local z = table.concat(idat)
  local len = z:byte(4) + z:byte(5) * 256
  local raw = z:sub(8, 7 + len)
  return raw:byte(1 + 1 + 2 * x + 1)
end

H.test("png: alpha level 2 is written as 1/255, invisible but not zero", function()
  local png = PNG.encodeGrayAlpha({ 0, 0, 0 }, { 0, 1, 2 }, 3, 1, { 255, 170, 85, 0 })
  H.eq(alphaByte(png, 3, 0), 0, "transparent")
  H.eq(alphaByte(png, 3, 1), 255, "opaque")
  H.eq(alphaByte(png, 3, 2), 1, "gap")
end)
