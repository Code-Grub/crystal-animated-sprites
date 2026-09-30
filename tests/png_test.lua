package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local PNG = H.need("png")

local function be32(s, i)
  local a, b, c, d = s:byte(i, i + 3)
  return ((a * 256 + b) * 256 + c) * 256 + d
end

-- Minimal reader: check every chunk CRC, return IHDR fields and raw IDAT bytes.
local function parse(png)
  H.eq(png:sub(1, 8), "\137PNG\r\n\26\n", "signature")
  local pos, idat, ihdr = 9, {}, nil
  while pos <= #png do
    local len = be32(png, pos)
    local kind = png:sub(pos + 4, pos + 7)
    local body = png:sub(pos + 8, pos + 7 + len)
    H.eq(be32(png, pos + 8 + len), PNG.crc32(kind .. body), kind .. " crc")
    if kind == "IHDR" then
      ihdr = { w = be32(body, 1), h = be32(body, 5), depth = body:byte(9),
               ctype = body:byte(10) }
    elseif kind == "IDAT" then
      idat[#idat + 1] = body
    end
    pos = pos + 12 + len
  end
  return ihdr, table.concat(idat)
end

-- Unwrap a zlib stream made only of stored blocks.
local function inflateStored(z)
  local pos, out = 3, {}
  while true do
    local final = z:byte(pos)
    local len = z:byte(pos + 1) + z:byte(pos + 2) * 256
    local nlen = z:byte(pos + 3) + z:byte(pos + 4) * 256
    H.eq(len + nlen, 65535, "LEN/NLEN")
    out[#out + 1] = z:sub(pos + 5, pos + 4 + len)
    pos = pos + 5 + len
    if final == 1 then break end
  end
  local raw = table.concat(out)
  H.eq(be32(z, pos), PNG.adler32(raw), "adler32")
  return raw
end

H.test("png: crc32 and adler32 known values", function()
  H.eq(PNG.crc32("123456789"), 0xCBF43926)
  H.eq(PNG.adler32("Wikipedia"), 0x11E60398)
end)

H.test("png: 2x2 image round-trips", function()
  local png = PNG.encodeGray({ 0, 1, 2, 3 }, 2, 2, { 255, 170, 85, 0 })
  local ihdr, idat = parse(png)
  H.eq(ihdr.w, 2); H.eq(ihdr.h, 2); H.eq(ihdr.depth, 8); H.eq(ihdr.ctype, 0)
  local raw = inflateStored(idat)
  H.eq(raw, "\0" .. string.char(255, 170) .. "\0" .. string.char(85, 0))
end)

H.test("png: image larger than one stored block", function()
  local w, h, px = 300, 300, {}
  for i = 1, w * h do px[i] = i % 4 end
  local png = PNG.encodeGray(px, w, h, { 255, 170, 85, 0 })
  local _, idat = parse(png)
  local raw = inflateStored(idat)
  H.eq(#raw, (w + 1) * h, "raw length")
  H.eq(raw:byte(2), 170, "first pixel is index 1")
end)
