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

local function result(withIcon)
  local r = {
    size = 5,
    timeline = { { frame = 0, ticks = 5 } },
    frames = { [0] = "PNG0" },
    flipped = { [0] = "FLP0" },
    back = "PNGB",
  }
  if withIcon then r.icon = { id = 7, gray = "IGRAY" } end
  return r
end

H.test("cache icons: icon paths", function()
  local c = Cache.new(fakeStore(), "s1", "m")
  H.eq(c:iconPath(7), "mod_cache/m/s1/icons/07.png")
end)

H.test("cache icons: put writes the grey sheet for the icon shape", function()
  local store = fakeStore()
  local c = Cache.new(store, "s1", "m")
  c:begin()
  H.eq(c:put(16, result(true)), true)
  H.eq(store.files["s1/icons/07.png"], "IGRAY")
  H.eq(c:meta(16).icon, 7)
end)

H.test("cache icons: complete also needs the icon files when the species has an icon", function()
  local store = fakeStore()
  local c = Cache.new(store, "s1", "m")
  c:begin()
  c:put(16, result(true))
  H.eq(c:complete(16), true)
  for _, key in ipairs({ "s1/icons/07.png" }) do
    local saved = store.files[key]
    store.files[key] = nil
    H.eq(c:complete(16), false, key .. " missing")
    store.files[key] = saved
  end
  H.eq(c:complete(16), true, "restored")
end)

H.test("cache icons: a species cached without an icon is complete without one", function()
  local store = fakeStore()
  local c = Cache.new(store, "s1", "m")
  c:begin()
  c:put(16, result(false))
  H.eq(c:meta(16).icon, nil)
  H.eq(c:complete(16), true)
end)
