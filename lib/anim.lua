local need = ...
local LZ = need("lz")
local Pic = need("pic")
local A = need("addresses")

local Anim = {}

-- Tile storage order of the decompressed sheets.  Confirmed visually in the
-- dump step; flip here if a species comes out scrambled.
Anim.ORDER = "columns"
Anim.ORDER_BACK = "columns"

local MASK_BYTES = { [5] = 4, [6] = 5, [7] = 7 }

function Anim.dimensions(rom, dex)
  local base = rom:banked(A.baseData.bank, A.baseData.addr)
  local b = rom:u8(base + (dex - 1) * 32 + A.baseDataDimensionsOffset)
  local w, h = b % 16, math.floor(b / 16)
  assert(w == h and MASK_BYTES[w],
    ("dex %d: unexpected pic dimension byte 0x%02X"):format(dex, b))
  return w
end

local function picOffset(rom, dex, back)
  local row = rom:banked(A.picPointers.bank, A.picPointers.addr)
    + (dex - 1) * 6 + (back and 3 or 0)
  return rom:banked(rom:u8(row) + A.picBankBias, rom:u16(row + 1))
end

function Anim.readFront(rom, dex)
  return (LZ.decompress(rom.raw, picOffset(rom, dex, false) + 1))
end

function Anim.readBack(rom, dex)
  return (LZ.decompress(rom.raw, picOffset(rom, dex, true) + 1))
end

function Anim.script(rom, dex)
  local ptr = rom:u16(rom:banked(A.animPointers.bank, A.animPointers.addr)
    + (dex - 1) * 2)
  local off = rom:banked(A.animPointers.bank, ptr)
  local rows = {}
  for _ = 1, 256 do
    local command = rom:u8(off)
    if command == 0xFF then break end
    rows[#rows + 1] = { command, rom:u8(off + 1) }
    off = off + 2
  end
  return rows
end

function Anim.timeline(rows)
  local out, pc, counter, guard = {}, 1, 0, 0
  while rows[pc] and guard < 4096 do
    guard = guard + 1
    local row = rows[pc]
    pc = pc + 1
    if row[1] == 0xFE then
      counter = row[2]
    elseif row[1] == 0xFD then
      if counter > 0 then
        counter = counter - 1
        if counter > 0 then pc = row[2] + 1 end
      end
    else
      out[#out + 1] = { frame = row[1], ticks = row[2] == 0 and 256 or row[2] }
    end
  end
  return out
end

function Anim.frameMap(rom, dex, size, frame)
  if frame == 0 then return Pic.identityMap(size) end
  local fp = A.framesPointers
  local perSpecies = rom:banked(A.kantoFramesBank,
    rom:u16(rom:banked(fp.bank, fp.addr) + (dex - 1) * 2))
  local record = rom:banked(A.kantoFramesBank,
    rom:u16(perSpecies + (frame - 1) * 2))
  local maskIndex = rom:u8(record)
  record = record + 1

  local bp = A.bitmaskPointers
  local maskBase = rom:banked(bp.bank,
    rom:u16(rom:banked(bp.bank, bp.addr) + (dex - 1) * 2))
  local mask = maskBase + maskIndex * MASK_BYTES[size]

  local map = Pic.identityMap(size)
  for i = 0, size * size - 1 do
    local byte = rom:u8(mask + math.floor(i / 8))
    if math.floor(byte / 2 ^ (i % 8)) % 2 == 1 then
      map[i + 1] = rom:u8(record)
      record = record + 1
    end
  end
  return map
end

function Anim.decode(rom, dex)
  local size = Anim.dimensions(rom, dex)
  local sheet = Anim.readFront(rom, dex)
  assert(#sheet % 16 == 0 and #sheet >= size * size * 16,
    ("dex %d: front sheet has %d bytes"):format(dex, #sheet))

  local timeline = Anim.timeline(Anim.script(rom, dex))
  local frames = {}
  local function render(f)
    local px = Pic.compose(sheet, Anim.frameMap(rom, dex, size, f), size, Anim.ORDER)
    return px
  end
  frames[0] = render(0)
  for _, step in ipairs(timeline) do
    if not frames[step.frame] then frames[step.frame] = render(step.frame) end
  end

  local back = Anim.readBack(rom, dex)
  assert(#back == 36 * 16, ("dex %d: back pic has %d bytes"):format(dex, #back))
  local backPixels = Pic.compose(back, Pic.identityMap(6), 6, Anim.ORDER_BACK)

  return { size = size, width = size * 8, frames = frames,
           timeline = timeline, back = backPixels }
end

return Anim
