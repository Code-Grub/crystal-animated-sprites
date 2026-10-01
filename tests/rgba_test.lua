package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local PNG = H.need("png")

-- the decompressed scanlines of a stored-deflate PNG
local function scanlines(png)
  local pos, idat = 9, {}
  while pos <= #png do
    local a, b, c, d = png:byte(pos, pos + 3)
    local len = ((a * 256 + b) * 256 + c) * 256 + d
    if png:sub(pos + 4, pos + 7) == "IDAT" then idat[#idat + 1] = png:sub(pos + 8, pos + 7 + len) end
    pos = pos + 12 + len
  end
  local z, out, p = table.concat(idat), {}, 3
  while true do
    local final = z:byte(p)
    local len = z:byte(p + 1) + z:byte(p + 2) * 256
    out[#out + 1] = z:sub(p + 5, p + 4 + len)
    p = p + 5 + len
    if final == 1 then break end
  end
  return table.concat(out)
end

local COLORS = { { 255, 255, 255 }, { 10, 20, 30 }, { 40, 50, 60 }, { 0, 0, 0 } }

-- pixel x of the first row as r, g, b, a
local function pixel(png, x)
  local raw = scanlines(png)
  local at = 1 + 1 + 4 * x
  return raw:byte(at, at + 3)
end

H.test("rgba: the image is 8-bit RGBA, colour type 6", function()
  local png = PNG.encodeRGBA({ 0, 1 }, { 1, 1 }, 2, 1, COLORS)
  H.eq(png:sub(2, 4), "PNG")
  H.eq(png:byte(25), 8, "bit depth")
  H.eq(png:byte(26), 6, "colour type")
end)

H.test("rgba: each shade index takes its colour from the palette", function()
  local png = PNG.encodeRGBA({ 0, 1, 2, 3 }, { 1, 1, 1, 1 }, 4, 1, COLORS)
  local r, g, b = pixel(png, 1)
  H.eq(r .. "," .. g .. "," .. b, "10,20,30")
  r, g, b = pixel(png, 2)
  H.eq(r .. "," .. g .. "," .. b, "40,50,60")
  r, g, b = pixel(png, 3)
  H.eq(r .. "," .. g .. "," .. b, "0,0,0")
end)

H.test("rgba: alpha is written like the grey images: 0, 1/255 for a gap, 255", function()
  local png = PNG.encodeRGBA({ 0, 0, 0 }, { 0, 2, 1 }, 3, 1, COLORS)
  local _, _, _, a0 = pixel(png, 0)
  local _, _, _, a1 = pixel(png, 1)
  local _, _, _, a2 = pixel(png, 2)
  H.eq(a0, 0, "transparent")
  H.eq(a1, 1, "gap")
  H.eq(a2, 255, "opaque")
end)

H.test("rgba: the chunk checksums are valid", function()
  local png = PNG.encodeRGBA({ 0, 1, 2, 3 }, { 1, 1, 1, 1 }, 2, 2, COLORS)
  local pos = 9
  while pos <= #png do
    local a, b, c, d = png:byte(pos, pos + 3)
    local len = ((a * 256 + b) * 256 + c) * 256 + d
    local body = png:sub(pos + 4, pos + 7 + len)
    local w, x, y, z = png:byte(pos + 8 + len, pos + 11 + len)
    H.eq(((w * 256 + x) * 256 + y) * 256 + z, PNG.crc32(body), "crc of " .. png:sub(pos + 4, pos + 7))
    pos = pos + 12 + len
  end
end)
