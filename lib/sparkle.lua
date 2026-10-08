-- Crystal's shiny entrance: the schedule, the art and the chime.  Pure: no
-- engine, so the timing is testable without one.
--
-- When a shiny takes the field Crystal plays ANIM_SEND_OUT_MON with parameter 1
-- (BattleAnim_SendOutMon, .Shiny).  Eight sparkles appear on a circle of radius
-- 16 around the picture, one every 4 frames, each with SFX_SHINE; each lives 15
-- frames and steps through OAM sets 74, 14, 15, 14, 15 at 3 frames apiece; the
-- script then waits 32 more frames.  Only after that do the cry and the front
-- animation start.
local need = ...
local Rom, A, LZ = need("rom"), need("addresses"), need("lz")

local Sparkle = {}

Sparkle.COUNT = 8
Sparkle.EVERY = 4    -- frames between one sparkle and the next
Sparkle.LIFE = 15    -- frames a sparkle lasts
Sparkle.RADIUS = 16
Sparkle.TOTAL = 60   -- the script: the last sparkle at frame 28, then a wait of 32

-- the OAM set each 3-frame step shows
local STEPS = { 74, 14, 15, 14, 15 }
local STEP_FRAMES = 3

function Sparkle.spawnFrame(k) return k * Sparkle.EVERY end

-- Offset from the picture's centre, in game pixels.  The cart takes the y
-- offset from a sine and the x offset from a cosine of the angle the object
-- was given (k * 8 of 64 steps round the circle) with y growing downward, so
-- the first sparkle is on the right and they go clockwise.
function Sparkle.offset(k)
  local angle = 2 * math.pi * k / Sparkle.COUNT
  local function round(v) return math.floor(v + 0.5) end
  return round(Sparkle.RADIUS * math.cos(angle)), round(Sparkle.RADIUS * math.sin(angle))
end

-- Which OAM set sparkle k shows at a frame: 74, 14 or 15, or nil before it
-- appears and after it is gone.
function Sparkle.frameId(k, frame)
  local age = math.floor(frame) - Sparkle.spawnFrame(k)
  if age < 0 or age >= Sparkle.LIFE then return nil end
  return STEPS[math.floor(age / STEP_FRAMES) + 1]
end

-- Everything on screen at a frame, in the order the sparkles appeared.
function Sparkle.visible(frame)
  local out = {}
  for k = 0, Sparkle.COUNT - 1 do
    local id = Sparkle.frameId(k, frame)
    if id then
      local dx, dy = Sparkle.offset(k)
      out[#out + 1] = { k = k, id = id, dx = dx, dy = dy }
    end
  end
  return out
end

-- How many sparkles have appeared by a frame; the chime plays each time this
-- goes up.
function Sparkle.appeared(frame)
  if frame < 0 then return 0 end
  return math.min(Sparkle.COUNT, math.floor(frame / Sparkle.EVERY) + 1)
end

function Sparkle.done(frame) return frame >= Sparkle.TOTAL end

-- ------------------------------------------------------------------ the art

-- The nine tiles of the speed graphics as flat, 1-based arrays of 64 shades
-- (0 transparent, 1 yellow, 2 orange, 3 black), or nil and a reason when this
-- ROM does not hold them where Crystal v1.0 and v1.1 do.
function Sparkle.tiles(rom)
  local g = A.sparkleGfx
  local ok, data = pcall(function()
    return (LZ.decompress(rom.raw, Rom.offset(g.bank, g.addr) + 1))
  end)
  if not ok then return nil, "the speed graphics could not be decompressed: " .. tostring(data) end
  if #data ~= 144 then return nil, ("the speed graphics are %d bytes, not 144"):format(#data) end
  local tiles = {}
  for t = 0, 8 do
    local px = {}
    for r = 0, 7 do
      local low, high = data[t * 16 + r * 2 + 1], data[t * 16 + r * 2 + 2]
      for x = 0, 7 do
        local bit = 7 - x
        px[r * 8 + x + 1] = math.floor(low / 2 ^ bit) % 2 + 2 * (math.floor(high / 2 ^ bit) % 2)
      end
    end
    tiles[t] = px
  end
  -- the quadrant's bright core and the small sparkle's centre: a wrong ROM
  -- that happens to decompress to 144 bytes will not have them
  if tiles[6][8 * 7 + 8] == 0 or tiles[0][8 * 4 + 4] == 0 then
    return nil, "the speed graphics do not look like Crystal's sparkle"
  end
  return tiles
end

-- The three pictures a sparkle steps through: the 16x16 star (OAM set 74, one
-- quadrant mirrored four ways) and the two 8x8 sparkles (sets 14 and 15).
function Sparkle.sprites(tiles)
  local star = {}
  for y = 0, 15 do
    for x = 0, 15 do
      local qx = x < 8 and x or 15 - x
      local qy = y < 8 and y or 15 - y
      star[y * 16 + x + 1] = tiles[6][qy * 8 + qx + 1]
    end
  end
  return {
    star = { w = 16, h = 16, pixels = star },
    large = { w = 8, h = 8, pixels = tiles[0] },
    small = { w = 8, h = 8, pixels = tiles[1] },
  }
end

-- ---------------------------------------------------------------- the chime

-- Sfx_Shine_Ch5 (audio/sfx.asm): duty cycle 0, five square notes, return.
-- Found by what it is, 27 bytes that occur once, because the sound data has no
-- table a mod can reach.  Returns the bytes as the ROM holds them, or nil.
local CHIME = string.char(0xDB, 0x00, 0x00, 0xD2, 0x00, 0x07, 0x00, 0xD2, 0x40, 0x07,
  0x00, 0xD2, 0x80, 0x07, 0x00, 0xD2, 0xC0, 0x07, 0x0A, 0xE1, 0xE0, 0x07, 0x01, 0x00, 0x00, 0x00, 0xFF)

function Sparkle.chime(rom)
  local at = rom.raw:find(CHIME, 1, true)
  if not at then return nil end
  return rom.raw:sub(at, at + #CHIME - 1)
end

return Sparkle
