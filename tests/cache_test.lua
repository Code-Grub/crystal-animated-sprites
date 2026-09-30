package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local Cache = H.need("cache")

local function fakeStore(limit)
  local files, s = {}, {}
  function s.write(key, bytes)
    if limit and #bytes > limit then return nil, "too large" end
    files[key] = bytes
    return true
  end
  function s.read(key) return files[key] end
  function s.info(key) return files[key] and { size = #files[key] } or nil end
  function s.delete(key) files[key] = nil end
  s.files = files
  return s
end

local result = {
  size = 6,
  timeline = { { frame = 1, ticks = 5 }, { frame = 0, ticks = 12 } },
  frames = { [0] = "PNG0", [1] = "PNG1" },
  back = "PNGB",
}

H.test("cache: stamp comes from the header checksum and version", function()
  local rom = { raw = string.rep("\0", 0x14C) .. "\1\0\xAB\xCD" }
  rom.u8 = function(self, o) return self.raw:byte(o + 1) end
  H.eq(Cache.stamp(rom), "f1-abcd-01")
end)

H.test("cache: fresh store is not valid until begun", function()
  local c = Cache.new(fakeStore(), "s1", "m")
  H.eq(c:valid(), false)
  c:begin()
  H.eq(c:valid(), true)
end)

H.test("cache: a different stamp is not valid", function()
  local store = fakeStore()
  Cache.new(store, "s1", "m"):begin()
  H.eq(Cache.new(store, "s2", "m"):valid(), false)
end)

H.test("cache: put then meta round-trips", function()
  local c = Cache.new(fakeStore(), "s1", "m")
  c:begin()
  H.eq(c:meta(25), nil, "absent before put")
  H.eq(c:put(25, result), true)
  local m = c:meta(25)
  H.eq(m.size, 6)
  H.eq(#m.timeline, 2)
  H.eq(m.timeline[1].frame, 1); H.eq(m.timeline[1].ticks, 5)
  H.eq(m.frames[0], true); H.eq(m.frames[1], true)
  H.eq(c:framePath(25, 1), "mod_cache/m/s1/front/025/1.png")
  H.eq(c:backPath(25), "mod_cache/m/s1/back/025.png")
end)

H.test("cache: meta is written last, so a failed write leaves no entry", function()
  local store = fakeStore(5)            -- rejects anything over 5 bytes
  local c = Cache.new(store, "s1", "m")
  c:begin()
  local big = { size = 6, timeline = {}, frames = { [0] = "TOO LARGE" }, back = "B" }
  local ok, err = c:put(1, big)
  H.eq(ok, false)
  H.eq(type(err), "string")
  H.eq(c:meta(1), nil, "no meta after a failed put")
end)
