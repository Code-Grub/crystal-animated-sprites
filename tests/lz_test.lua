package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local LZ = H.need("lz")
local function S(...) return string.char(...) end

H.test("lz: empty stream", function()
  local out, pos = LZ.decompress(S(0xFF))
  H.arrayEq(out, {})
  H.eq(pos, 2, "position after terminator")
end)

H.test("lz: literal run", function()
  H.arrayEq((LZ.decompress(S(0x02, 0xAA, 0xBB, 0xCC, 0xFF))), { 0xAA, 0xBB, 0xCC })
end)

H.test("lz: iterate", function()
  H.arrayEq((LZ.decompress(S(0x23, 0x55, 0xFF))), { 0x55, 0x55, 0x55, 0x55 })
end)

H.test("lz: alternate", function()
  H.arrayEq((LZ.decompress(S(0x44, 0x01, 0x02, 0xFF))), { 1, 2, 1, 2, 1 })
end)

H.test("lz: zero fill", function()
  H.arrayEq((LZ.decompress(S(0x62, 0xFF))), { 0, 0, 0 })
end)

H.test("lz: repeat with absolute offset", function()
  H.arrayEq((LZ.decompress(S(0x03, 1, 2, 3, 4, 0x82, 0x00, 0x01, 0xFF))),
    { 1, 2, 3, 4, 2, 3, 4 })
end)

H.test("lz: repeat with relative offset", function()
  H.arrayEq((LZ.decompress(S(0x03, 1, 2, 3, 4, 0x81, 0x81, 0xFF))),
    { 1, 2, 3, 4, 3, 4 })
end)

H.test("lz: flip reverses bit order", function()
  H.arrayEq((LZ.decompress(S(0x00, 0x01, 0xA0, 0x80, 0xFF))), { 0x01, 0x80 })
end)

H.test("lz: reverse copies backwards", function()
  H.arrayEq((LZ.decompress(S(0x02, 1, 2, 3, 0xC2, 0x80, 0xFF))),
    { 1, 2, 3, 3, 2, 1 })
end)

H.test("lz: long command form", function()
  local out = LZ.decompress(S(0xE5, 0x2B, 0x07, 0xFF))
  H.eq(#out, 300, "length")
  H.eq(out[1], 7); H.eq(out[300], 7)
end)

H.test("lz: start offset and trailing data", function()
  local out, pos = LZ.decompress(S(0x99, 0x00, 0xAB, 0xFF, 0x77), 2)
  H.arrayEq(out, { 0xAB })
  H.eq(pos, 5, "position")
end)

H.test("lz: truncated stream is an error", function()
  local ok = pcall(LZ.decompress, S(0x02, 0xAA))
  H.eq(ok, false, "truncated must raise")
end)

H.test("lz: bad back-reference is an error", function()
  local ok = pcall(LZ.decompress, S(0x80, 0x00, 0x09, 0xFF))
  H.eq(ok, false, "reference before start must raise")
end)
