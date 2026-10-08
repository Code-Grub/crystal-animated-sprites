package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local Cache = H.need("cache")

local function fakeStore()
  local files, s = {}, {}
  function s.write(key, bytes) files[key] = bytes return true end
  function s.read(key) return files[key] end
  function s.info(key) return files[key] and { size = #files[key] } or nil end
  function s.delete(key) files[key] = nil end
  s.files = files
  return s
end

-- what the decode job hands the cache: the grey set, the normal colour set and,
-- now, the same colour set again in the species' shiny colours
local function result(withShiny)
  local r = {
    size = 6,
    timeline = { { frame = 1, ticks = 5 }, { frame = 0, ticks = 12 } },
    frames = { [0] = "PNG0", [1] = "PNG1" },
    flipped = { [0] = "FLP0", [1] = "FLP1" },
    back = "PNGB",
    colorFrames = { [0] = "CPNG0", [1] = "CPNG1" },
    colorFlipped = { [0] = "CFLP0", [1] = "CFLP1" },
    colorBack = "CPNGB",
  }
  if withShiny then
    r.shinyFrames = { [0] = "SPNG0", [1] = "SPNG1" }
    r.shinyFlipped = { [0] = "SFLP0", [1] = "SFLP1" }
    r.shinyBack = "SPNGB"
  end
  return r
end

H.test("cache shiny: the format moved past the normal-colour-only caches", function()
  H.eq(Cache.FORMAT >= 11, true, "FORMAT")
  H.eq(Cache.stamp({ u8 = function() return 0 end }):sub(1, 3) ~= "f10", true)
end)

H.test("cache shiny: shiny paths sit beside the colour ones", function()
  local c = Cache.new(fakeStore(), "s1", "m")
  H.eq(c:framePath(25, 1, false, true, true), "mod_cache/m/s1/front/025/1cs.png")
  H.eq(c:framePath(25, 1, true, true, true), "mod_cache/m/s1/front/025/1mcs.png")
  H.eq(c:backPath(25, true, true), "mod_cache/m/s1/back/025cs.png")
  H.eq(c:framePath(25, 1, false, true), "mod_cache/m/s1/front/025/1c.png", "colour path unchanged")
  H.eq(c:backPath(25, true), "mod_cache/m/s1/back/025c.png", "colour path unchanged")
  H.eq(c:framePath(25, 1), "mod_cache/m/s1/front/025/1.png", "grey path unchanged")
end)

H.test("cache shiny: shiny without colour is meaningless and gives the grey path", function()
  local c = Cache.new(fakeStore(), "s1", "m")
  H.eq(c:framePath(25, 1, false, false, true), "mod_cache/m/s1/front/025/1.png")
  H.eq(c:framePath(25, 1, true, nil, true), "mod_cache/m/s1/front/025/1m.png")
  H.eq(c:backPath(25, false, true), "mod_cache/m/s1/back/025.png")
end)

H.test("cache shiny: put writes every shiny file", function()
  local store = fakeStore()
  local c = Cache.new(store, "s1", "m")
  c:begin()
  H.eq(c:put(25, result(true)), true)
  H.eq(store.files["s1/front/025/1cs.png"], "SPNG1")
  H.eq(store.files["s1/front/025/0mcs.png"], "SFLP0")
  H.eq(store.files["s1/back/025cs.png"], "SPNGB")
  H.eq(store.files["s1/front/025/1c.png"], "CPNG1", "the normal colour files are still written")
  H.eq(c:meta(25).shiny, true)
end)

H.test("cache shiny: complete also needs the shiny files when the species has them", function()
  local store = fakeStore()
  local c = Cache.new(store, "s1", "m")
  c:begin()
  c:put(25, result(true))
  H.eq(c:complete(25), true)
  for _, key in ipairs({ "s1/front/025/1cs.png", "s1/front/025/0mcs.png", "s1/back/025cs.png" }) do
    local saved = store.files[key]
    store.files[key] = nil
    H.eq(c:complete(25), false, key .. " missing")
    store.files[key] = saved
  end
  H.eq(c:complete(25), true, "restored")
end)

H.test("cache shiny: a species cached without shiny frames is complete without them", function()
  local store = fakeStore()
  local c = Cache.new(store, "s1", "m")
  c:begin()
  c:put(25, result(false))
  H.eq(c:meta(25).shiny, false)
  H.eq(c:complete(25), true)
end)
