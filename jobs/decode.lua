-- Runs in a background job: no `mod`, no `require`.  The libraries arrive as
-- source strings in the argument and are loaded here.
local arg = ...

local loaded = {}
local function need(name)
  if not loaded[name] then
    local chunk = assert(load(arg.libs[name], "=" .. name))
    loaded[name] = chunk(need)
  end
  return loaded[name]
end

local Rom, Anim, PNG, Pic = need("rom"), need("anim"), need("png"), need("pic")
local Specks = need("specks")
local SHADES = { 255, 170, 85, 0 }
local rom = Rom.new(arg.rom)

local species, errors = {}, {}
for dex = arg.first, arg.last do
  local ok, res = pcall(function()
    local r = Anim.decode(rom, dex)
    -- Every pic is matted: the colour-0 background around the sprite becomes
    -- transparent, so it can sit on any backdrop instead of a white square.
    local function encode(px, alpha, width)
      return PNG.encodeGrayAlpha(px, alpha, width, width, SHADES)
    end
    local frames, flipped = {}, {}
    for index, px in pairs(r.frames) do
      local alpha = Pic.matte(px, r.width, Specks[dex])
      frames[index] = encode(px, alpha, r.width)
      flipped[index] = encode(Pic.mirror(px, r.width), Pic.mirror(alpha, r.width), r.width)
    end
    return {
      size = r.size,
      timeline = r.timeline,
      frames = frames,
      flipped = flipped,
      back = encode(r.back, Pic.matte(r.back, 48), 48),
    }
  end)
  if ok then species[dex] = res else errors[dex] = tostring(res) end
end

return { species = species, errors = errors }
