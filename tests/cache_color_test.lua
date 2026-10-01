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

local function result(withColor)
  local r = {
    size = 6,
    timeline = { { frame = 1, ticks = 5 }, { frame = 0, ticks = 12 } },
    frames = { [0] = "PNG0", [1] = "PNG1" },
    flipped = { [0] = "FLP0", [1] = "FLP1" },
    back = "PNGB",
  }
  if withColor then
    r.colorFrames = { [0] = "CPNG0", [1] = "CPNG1" }
    r.colorFlipped = { [0] = "CFLP0", [1] = "CFLP1" }
    r.colorBack = "CPNGB"
  end
  return r
end

H.test("cache colour: the format moved past the grey-only caches", function()
  H.eq(Cache.FORMAT >= 10, true, "FORMAT")
  H.eq(Cache.stamp({ u8 = function() return 0 end }):sub(1, 3) ~= "f9-", true)
end)

H.test("cache colour: colour paths sit beside the grey ones", function()
  local c = Cache.new(fakeStore(), "s1", "m")
  H.eq(c:framePath(25, 1, false, true), "mod_cache/m/s1/front/025/1c.png")
  H.eq(c:framePath(25, 1, true, true), "mod_cache/m/s1/front/025/1mc.png")
  H.eq(c:backPath(25, true), "mod_cache/m/s1/back/025c.png")
  H.eq(c:framePath(25, 1), "mod_cache/m/s1/front/025/1.png", "grey path unchanged")
  H.eq(c:backPath(25), "mod_cache/m/s1/back/025.png", "grey path unchanged")
end)

H.test("cache colour: put writes every colour file", function()
  local store = fakeStore()
  local c = Cache.new(store, "s1", "m")
  c:begin()
  H.eq(c:put(25, result(true)), true)
  H.eq(store.files["s1/front/025/1c.png"], "CPNG1")
  H.eq(store.files["s1/front/025/0mc.png"], "CFLP0")
  H.eq(store.files["s1/back/025c.png"], "CPNGB")
  H.eq(c:meta(25).colors, true)
end)

H.test("cache colour: complete also needs the colour files when the species has them", function()
  local store = fakeStore()
  local c = Cache.new(store, "s1", "m")
  c:begin()
  c:put(25, result(true))
  H.eq(c:complete(25), true)
  for _, key in ipairs({ "s1/front/025/1c.png", "s1/front/025/0mc.png", "s1/back/025c.png" }) do
    local saved = store.files[key]
    store.files[key] = nil
    H.eq(c:complete(25), false, key .. " missing")
    store.files[key] = saved
  end
  H.eq(c:complete(25), true, "restored")
end)

H.test("cache colour: a species cached without colour is complete without it", function()
  local store = fakeStore()
  local c = Cache.new(store, "s1", "m")
  c:begin()
  c:put(25, result(false))
  H.eq(c:meta(25).colors, false)
  H.eq(c:complete(25), true)
end)
