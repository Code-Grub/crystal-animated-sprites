local PNG = {}

local crcTable
local function buildTable()
  crcTable = {}
  for n = 0, 255 do
    local c = n
    for _ = 1, 8 do
      if bit.band(c, 1) == 1 then
        c = bit.bxor(0xEDB88320, bit.rshift(c, 1))
      else
        c = bit.rshift(c, 1)
      end
    end
    crcTable[n] = c
  end
end

function PNG.crc32(str)
  if not crcTable then buildTable() end
  local c = 0xFFFFFFFF
  for i = 1, #str do
    c = bit.bxor(crcTable[bit.band(bit.bxor(c, str:byte(i)), 0xFF)],
      bit.rshift(c, 8))
  end
  return bit.bxor(c, 0xFFFFFFFF) % 4294967296
end

function PNG.adler32(str)
  local a, b = 1, 0
  for i = 1, #str do
    a = (a + str:byte(i)) % 65521
    b = (b + a) % 65521
  end
  return b * 65536 + a
end

local function u32(n)
  n = n % 4294967296
  return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256,
    math.floor(n / 256) % 256, n % 256)
end

local function chunk(kind, body)
  return u32(#body) .. kind .. body .. u32(PNG.crc32(kind .. body))
end

local function storedZlib(raw)
  local parts, pos, total = { "\120\1" }, 1, #raw
  repeat
    local len = math.min(65535, total - pos + 1)
    local final = (pos + len > total) and 1 or 0
    local nlen = 65535 - len
    parts[#parts + 1] = string.char(final, len % 256, math.floor(len / 256),
      nlen % 256, math.floor(nlen / 256))
    parts[#parts + 1] = raw:sub(pos, pos + len - 1)
    pos = pos + len
  until pos > total
  parts[#parts + 1] = u32(PNG.adler32(raw))
  return table.concat(parts)
end

-- Grayscale plus alpha (colour type 4): a gray byte and an alpha byte per
-- pixel.  alpha[i] is 0 for transparent, 2 for a deliberate gap (written as
-- 1/255, see Pic.gaps), anything else for opaque.
function PNG.encodeGrayAlpha(pixels, alpha, width, height, shades)
  local rows = {}
  for y = 0, height - 1 do
    local bytes = { "\0" }
    local base = y * width
    for x = 1, width do
      bytes[#bytes + 1] = string.char(shades[pixels[base + x] + 1],
        alpha[base + x] == 0 and 0 or (alpha[base + x] == 2 and 1 or 255))
    end
    rows[#rows + 1] = table.concat(bytes)
  end
  local ihdr = u32(width) .. u32(height) .. string.char(8, 4, 0, 0, 0)
  return "\137PNG\r\n\26\n" .. chunk("IHDR", ihdr)
    .. chunk("IDAT", storedZlib(table.concat(rows))) .. chunk("IEND", "")
end

function PNG.encodeGray(pixels, width, height, shades)
  local rows = {}
  for y = 0, height - 1 do
    local bytes = { "\0" }
    local base = y * width
    for x = 1, width do
      bytes[#bytes + 1] = string.char(shades[pixels[base + x] + 1])
    end
    rows[#rows + 1] = table.concat(bytes)
  end
  local ihdr = u32(width) .. u32(height) .. string.char(8, 0, 0, 0, 0)
  return "\137PNG\r\n\26\n" .. chunk("IHDR", ihdr)
    .. chunk("IDAT", storedZlib(table.concat(rows))) .. chunk("IEND", "")
end

return PNG
