package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local Ingest = H.need("ingest")

-- A cache stand-in: put succeeds unless the dex is in `failing`.
local function fakeCache(failing)
  local c = { puts = {} }
  function c:put(dex)
    if failing and failing[dex] then return false, "disk full" end
    self.puts[#self.puts + 1] = dex
    return true
  end
  return c
end

local function species(...)
  local t = {}
  for _, dex in ipairs({ ... }) do t[dex] = { size = 5 } end
  return t
end

H.test("ingest: step writes at most the budget per call", function()
  local cache = fakeCache()
  local ing = Ingest.new(cache, {})
  ing:enqueue(species(5, 3, 9, 1, 7))
  H.eq(ing:pending(), 5)
  H.eq(ing:step(2), 2)
  H.eq(ing:pending(), 3)
  H.arrayEq(cache.puts, { 1, 3 }, "lowest dex first")
end)

H.test("ingest: repeated steps drain the queue in order", function()
  local cache = fakeCache()
  local ing = Ingest.new(cache, {})
  ing:enqueue(species(5, 3, 9, 1, 7))
  while ing:pending() > 0 do ing:step(2) end
  H.arrayEq(cache.puts, { 1, 3, 5, 7, 9 })
  H.eq(ing:step(2), 0, "empty queue does nothing")
end)

H.test("ingest: success and failure are reported per species", function()
  local cache = fakeCache({ [3] = true })
  local ok, failed = {}, {}
  local ing = Ingest.new(cache, {
    onPut = function(dex) ok[#ok + 1] = dex end,
    onFail = function(dex, err) failed[#failed + 1] = dex .. ":" .. err end,
  })
  ing:enqueue(species(1, 3, 5))
  ing:step(10)
  H.arrayEq(ok, { 1, 5 })
  H.arrayEq(failed, { "3:disk full" })
end)

H.test("ingest: a second enqueue adds to the queue", function()
  local cache = fakeCache()
  local ing = Ingest.new(cache, {})
  ing:enqueue(species(1))
  ing:enqueue(species(2))
  H.eq(ing:pending(), 2)
end)
