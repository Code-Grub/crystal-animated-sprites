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
  for _, n in ipairs({ "lz", "rom", "addresses", "pic", "png", "anim" }) do
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
