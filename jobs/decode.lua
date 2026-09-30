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
local SHADES = { 255, 170, 85, 0 }
local rom = Rom.new(arg.rom)

local species, errors = {}, {}
for dex = arg.first, arg.last do
  local ok, res = pcall(function()
    local r = Anim.decode(rom, dex)
    local frames, flipped = {}, {}
    for index, px in pairs(r.frames) do
      frames[index] = PNG.encodeGray(px, r.width, r.width, SHADES)
      flipped[index] = PNG.encodeGray(Pic.mirror(px, r.width), r.width, r.width, SHADES)
    end
    return {
      size = r.size,
      timeline = r.timeline,
      frames = frames,
      flipped = flipped,
      back = PNG.encodeGray(r.back, 48, 48, SHADES),
    }
  end)
  if ok then species[dex] = res else errors[dex] = tostring(res) end
end

return { species = species, errors = errors }
