package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local Status = H.need("status")

local function state(over)
  local s = {
    version = "0.1.3", stamp = "f8-18d2-01", ready = 151, failed = 0,
    running = 0, waiting = 0, jobs = true,
    enemy = { dex = 37, source = "cas" }, player = { dex = 44, source = "cas" },
  }
  for k, v in pairs(over or {}) do s[k] = v end
  return s
end

H.test("status: lines fit the 20-character battle screen", function()
  local lines = Status.lines(state({ err = "a very long error message indeed" }))
  for i, line in ipairs(lines) do
    H.eq(#line <= 20, true, "line " .. i .. " is " .. #line .. " long: " .. line)
  end
end)

H.test("status: names the code version through the cache stamp", function()
  local lines = Status.lines(state())
  H.eq(lines[1], "V0.1.3 F8-18D2-01")
end)

H.test("status: reports the cache and job counts", function()
  local lines = Status.lines(state({ ready = 12, failed = 3, running = 2, waiting = 1, jobs = false }))
  H.eq(lines[2], "READY 12 FAIL 3")
  H.eq(lines[3], "JOB NO RUN 2 WAIT 1")
end)

H.test("status: says whether each side is served by this mod", function()
  local lines = Status.lines(state({
    enemy = { dex = 37, source = "cas" }, player = { dex = 44, source = "game" } }))
  H.eq(lines[4], "E037 CAS P044 GAME")
end)

H.test("status: a side with no battler shows dashes", function()
  local lines = Status.lines(state({ enemy = false, player = false }))
  H.eq(lines[4], "E--- ---- P--- ----")
end)

H.test("status: an error gets its own line, upper-cased and cut to fit", function()
  local lines = Status.lines(state({ err = "decode of species 1-75 failed" }))
  H.eq(lines[5], "ERR DECODE OF SPECIE")
  H.eq(#Status.lines(state()), 4, "no error line when there is no error")
end)
