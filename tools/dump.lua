package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local Rom = H.need("rom")
local Anim = H.need("anim")
local PNG = H.need("png")

local dex = tonumber(arg[1]) or 25
local outdir = arg[2] or "out"
local scale = 4
for i = 3, #arg do
  if arg[i] == "--scale" then scale = tonumber(arg[i + 1]) end
  if arg[i] == "--front-order" then Anim.ORDER = arg[i + 1] end
  if arg[i] == "--back-order" then Anim.ORDER_BACK = arg[i + 1] end
end

local raw = assert(H.rom(), "no ROM: set CRYSTAL_ROM")
local r = Anim.decode(Rom.new(raw), dex)

local function upscale(px, w)
  local out, ow = {}, w * scale
  for y = 0, w * scale - 1 do
    for x = 0, ow - 1 do
      out[y * ow + x + 1] = px[math.floor(y / scale) * w + math.floor(x / scale) + 1]
    end
  end
  return out, ow
end

local function write(name, px, w)
  local big, bw = upscale(px, w)
  local f = assert(io.open(outdir .. "/" .. name, "wb"))
  f:write(PNG.encodeGray(big, bw, bw, { 255, 170, 85, 0 }))
  f:close()
  print("wrote " .. name)
end

os.execute('mkdir "' .. outdir .. '" 2>nul')
write(("%03d_back.png"):format(dex), r.back, 48)
for frame, px in pairs(r.frames) do
  write(("%03d_f%d.png"):format(dex, frame), px, r.width)
end
