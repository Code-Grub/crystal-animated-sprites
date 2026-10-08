package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local Entrance = H.need("entrance")
local Sparkle = H.need("sparkle")

-- A fake clock and a fake battle whose queue records what the wrapper asks for.
local function make(over)
  local clock = { t = 100 }
  local deps = {
    now = function() return clock.t end,
    enabled = function() return true end,
    isShiny = function(mon) return mon and mon.shiny == true end,
  }
  for k, v in pairs(over or {}) do deps[k] = v end
  return Entrance.new(deps), clock
end

local function fakeBattle()
  local b = { queue = {}, cries = 0 }
  function b:waitSfxNext(src) self.queue[#self.queue + 1] = { wait = src } end
  function b:actNext(fn) self.queue[#self.queue + 1] = { act = fn } end
  return b
end

local function shinyBattler() return { mon = { species = "CHARMANDER", shiny = true } } end
local function plainBattler() return { mon = { species = "CHARMANDER" } } end

local function cry(battle) battle.cries = battle.cries + 1 return "the cry" end

H.test("entrance: a plain Pokemon's cry goes straight through", function()
  local e = make()
  local b, battler = fakeBattle(), plainBattler()
  H.eq(e:holdCry(b, battler, cry), "the cry")
  H.eq(b.cries, 1, "played at once")
  H.eq(#b.queue, 0, "nothing queued")
end)

H.test("entrance: with the option off even a shiny's cry goes straight through", function()
  local e = make({ enabled = function() return false end })
  local b = fakeBattle()
  H.eq(e:holdCry(b, shinyBattler(), cry), "the cry")
  H.eq(#b.queue, 0)
end)

H.test("entrance: a shiny's cry is held behind a wait and played after it", function()
  local e = make()
  local b, battler = fakeBattle(), shinyBattler()
  H.eq(e:holdCry(b, battler, cry), nil, "the caller has nothing to wait on yet")
  H.eq(b.cries, 0, "the cry has not played")
  H.eq(#b.queue, 2, "a wait, then the cry")
  H.eq(type(b.queue[1].wait), "function", "the wait is a source getter, as the engine queue takes")
  H.eq(type(b.queue[2].act), "function")
  b.queue[2].act()
  H.eq(b.cries, 1, "the cry plays when its turn comes")
  H.eq(b.queue[3].wait, "the cry", "and the queue then waits on it")
end)

H.test("entrance: the wait looks like a playing sound until the sparkle is over", function()
  local e, clock = make()
  local b, battler = fakeBattle(), shinyBattler()
  e:holdCry(b, battler, cry)
  local gate = b.queue[1].wait()
  H.eq(gate:isPlaying(), true, "at the start")
  clock.t = clock.t + 0.5
  H.eq(gate:isPlaying(), true, "half way")
  clock.t = clock.t + 0.51
  H.eq(gate:isPlaying(), false, "after sixty frames")
  H.eq(gate:getDuration(), 1.0, "the queue budgets sixty frames for it")
  H.eq(gate:getPitch(), 1)
  gate:stop() -- the queue stops what it waited for; that must be harmless
end)

H.test("entrance: the front animation waits for the sparkle and then starts", function()
  local e, clock = make()
  local b, battler = fakeBattle(), shinyBattler()
  H.eq(e:released(battler), false, "a shiny that has not asked for its cry yet is held")
  e:holdCry(b, battler, cry)
  H.eq(e:released(battler), false, "and held while the sparkle plays")
  clock.t = clock.t + 1.01
  H.eq(e:released(battler), true, "released when it ends")
  H.eq(e:released(plainBattler()), true, "a plain Pokemon is never held")
end)

H.test("entrance: a shiny whose cry is never requested is not held for ever", function()
  local e, clock = make()
  local battler = shinyBattler()
  H.eq(e:released(battler), false)
  clock.t = clock.t + Entrance.GRACE + 0.1
  H.eq(e:released(battler), true, "the grace period ran out")
end)

H.test("entrance: with the option off nothing is held", function()
  local on = true
  local e = make({ enabled = function() return on end })
  local battler = shinyBattler()
  H.eq(e:released(battler), false)
  on = false
  H.eq(e:released(battler), true)
end)

H.test("entrance: what to draw follows the sparkle schedule", function()
  local e, clock = make()
  local b, battler = fakeBattle(), shinyBattler()
  H.eq(#e:sparkles(battler), 0, "nothing before it starts")
  e:holdCry(b, battler, cry)
  local first = e:sparkles(battler)
  H.eq(#first, 1)
  H.eq(first[1].id, 74)
  H.eq(first[1].dx, 16)
  clock.t = clock.t + 10 / 60
  local at10 = e:sparkles(battler)
  H.eq(#at10, 3, "three on screen at frame 10")
  clock.t = clock.t + 1
  H.eq(#e:sparkles(battler), 0, "none once it is over")
end)

H.test("entrance: the chime is due once for each sparkle that appears", function()
  local e, clock = make()
  local b, battler = fakeBattle(), shinyBattler()
  e:holdCry(b, battler, cry)
  H.eq(e:chimesDue(battler), 1, "the first sparkle")
  H.eq(e:chimesDue(battler), 0, "not twice")
  clock.t = clock.t + 9 / 60
  H.eq(e:chimesDue(battler), 2, "two more by frame 9")
  clock.t = clock.t + 5
  H.eq(e:chimesDue(battler), 5, "the rest, once, however late we look")
  H.eq(e:chimesDue(battler), 0)
  H.eq(e:chimesDue(plainBattler()), 0)
end)

H.test("entrance: another send-out of the same Pokemon starts a fresh entrance", function()
  local e, clock = make()
  local b, battler = fakeBattle(), shinyBattler()
  e:holdCry(b, battler, cry)
  clock.t = clock.t + 5
  H.eq(e:active(battler), false)
  e:holdCry(b, battler, cry)
  H.eq(e:active(battler), true, "running again")
  H.eq(e:chimesDue(battler), 1, "and chiming again")
end)

H.test("entrance: a different Pokemon in the same slot does not inherit the last one's entrance", function()
  local e, clock = make()
  local b, battler = fakeBattle(), shinyBattler()
  e:holdCry(b, battler, cry)
  battler.mon = { species = "PIDGEY" }
  H.eq(e:active(battler), false)
  H.eq(#e:sparkles(battler), 0)
end)
