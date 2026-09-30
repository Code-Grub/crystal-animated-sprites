package.path = "./?.lua;" .. package.path
local H = require("tests.harness")

local function readFile(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

local function runJob(arg)
  local chunk = assert(loadstring(readFile("jobs/decode.lua"), "@jobs/decode.lua"))
  -- a sandbox-like environment: no require, no io, no os
  local env = { assert = assert, pcall = pcall, tostring = tostring, type = type,
    pairs = pairs, ipairs = ipairs, load = load, loadstring = loadstring,
    setfenv = setfenv, string = string, table = table, math = math, bit = bit,
    select = select, error = error, unpack = unpack, setmetatable = setmetatable }
  setfenv(chunk, env)
  return chunk(arg)
end

local function libs()
  local out = {}
  for _, n in ipairs({ "lz", "rom", "addresses", "pic", "png", "anim", "specks" }) do
    out[n] = readFile("lib/" .. n .. ".lua")
  end
  return out
end

local raw = H.rom()
if not raw then
  H.skip("job: decode batches", "no ROM found (set CRYSTAL_ROM)")
else
  H.test("job: decodes a batch and returns PNG strings", function()
    local r = runJob({ rom = raw, libs = libs(), first = 24, last = 26 })
    H.eq(next(r.errors), nil, "no errors")
    for dex = 24, 26 do
      local s = assert(r.species[dex], "species " .. dex)
      H.eq(s.back:sub(2, 4), "PNG")
      H.eq(s.frames[0]:sub(2, 4), "PNG")
      H.eq(s.flipped[0]:sub(2, 4), "PNG")
      H.eq(s.flipped[0] ~= s.frames[0], true, "mirrored differs from original")
      H.eq(#s.timeline > 0, true)
    end
  end)

  H.test("job: one bad species does not stop the batch", function()
    -- Corrupt species 25's pic pointer row so decode raises for it alone.
    local bad = raw
    local off = 0x48 * 0x4000 + (25 - 1) * 6
    bad = bad:sub(1, off) .. string.rep("\255", 6) .. bad:sub(off + 7)
    local r = runJob({ rom = bad, libs = libs(), first = 24, last = 26 })
    H.eq(type(r.errors[25]), "string", "species 25 reports an error")
    H.eq(r.species[25], nil)
    H.eq(r.species[24] ~= nil and r.species[26] ~= nil, true, "neighbours decode")
  end)
end

-- End to end: the job's PNGs carry an alpha channel with a transparent
-- background, so the sprite can sit on any backdrop.
local function rawScanlines(png)
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

if H.rom() then
  H.test("job: pics are grayscale+alpha with a transparent corner", function()
    local r = runJob({ rom = H.rom(), libs = libs(), first = 25, last = 25 })
    local s = assert(r.species[25], "species 25")
    for label, png in pairs({ front = s.frames[0], mirrored = s.flipped[0], back = s.back }) do
      H.eq(png:byte(26), 4, label .. " colour type")
      local raw = rawScanlines(png)
      H.eq(raw:byte(3), 0, label .. " top-left pixel is transparent")
    end
    -- and something is opaque: the sprite itself
    local raw, opaque = rawScanlines(s.frames[0]), 0
    for i = 3, #raw, 2 do if raw:byte(i) == 255 then opaque = opaque + 1 end end
    H.eq(opaque > 200, true, "the sprite has opaque pixels")
  end)
end

if H.rom() then
  -- alpha byte of pixel (x, y) in a width-w grayscale+alpha PNG
  local function alphaAt(png, w, x, y)
    return rawScanlines(png):byte(y * (1 + 2 * w) + 1 + 2 * x + 2)
  end

  H.test("job: every region reviewed by hand is cleared or kept as decided", function()
    local decisions = dofile("tests/review_decisions.lua")
    local r = runJob({ rom = H.rom(), libs = libs(), first = 1, last = 151 })
    H.eq(next(r.errors), nil, "no species failed")
    local function alpha(dex, x, y)
      local sp = r.species[dex]
      return alphaAt(sp.frames[0], sp.size * 8, x, y)
    end
    for _, d in ipairs(decisions.remove) do
      H.eq(alpha(d[1], d[2], d[3]), 0, ("dex %d (%d,%d) is a hole and must be transparent"):format(d[1], d[2], d[3]))
    end
    for _, d in ipairs(decisions.keep) do
      H.eq(alpha(d[1], d[2], d[3]), 255, ("dex %d (%d,%d) is meant to be white and must stay"):format(d[1], d[2], d[3]))
    end
  end)

  H.test("job: a reviewed hole is cleared in every animation frame, a kept region in none", function()
    local expect = dofile("tests/review_expectations.lua")
    local r = runJob({ rom = H.rom(), libs = libs(), first = 1, last = 151 })
    local function alpha(dex, frame, x, y)
      local sp = r.species[dex]
      return alphaAt(sp.frames[frame], sp.size * 8, x, y)
    end
    for _, e in ipairs(expect.remove) do
      H.eq(alpha(e[1], e[2], e[3], e[4]), 0,
        ("dex %d frame %d (%d,%d) is the same hole in another pose"):format(e[1], e[2], e[3], e[4]))
    end
    for _, e in ipairs(expect.keep) do
      H.eq(alpha(e[1], e[2], e[3], e[4]), 255,
        ("dex %d frame %d (%d,%d) is a kept region and must stay"):format(e[1], e[2], e[3], e[4]))
    end
  end)

  H.test("job: Pikachu's tail-base gap is cleared and his eye glints are not", function()
    local r = runJob({ rom = H.rom(), libs = libs(), first = 25, last = 25 })
    local s = assert(r.species[25], "species 25")
    local w = s.size * 8
    -- frames 0, 1 and 4 have the walled-in pixel at (28, 26)
    for _, index in ipairs({ 0, 1, 4 }) do
      H.eq(alphaAt(s.frames[index], w, 28, 26), 0, "frame " .. index .. " tail-base gap")
      H.eq(alphaAt(s.flipped[index], w, w - 1 - 28, 26), 0, "frame " .. index .. " mirrored")
    end
    -- frames 2 and 3 have plain outline there; it must stay
    for _, index in ipairs({ 2, 3 }) do
      H.eq(alphaAt(s.frames[index], w, 28, 26), 255, "frame " .. index .. " outline stays")
    end
    -- the far eye's glint sits close to the edge of the face but is real detail
    H.eq(alphaAt(s.frames[0], w, 5, 13), 255, "far eye glint stays")
    H.eq(alphaAt(s.frames[0], w, 15, 13), 255, "near eye glint stays")
  end)
end
