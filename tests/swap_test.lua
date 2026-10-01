package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local Swap = H.need("swap")

local function make(over)
  local calls = { rebuild = 0 }
  local deps = {
    dexOf = function() return 25 end,
    busy = function() return false end,
    pathFor = function(_, _, t) return "k" .. math.floor(t) end,
    rebuild = function(_, _, key)
      calls.rebuild = calls.rebuild + 1
      return "img:" .. key
    end,
  }
  for k, v in pairs(over or {}) do deps[k] = v end
  return Swap.new(deps), calls
end

local function battler()
  return { mon = { species = "PIKACHU" }, sprite = "vanilla", isPlayer = false }
end

H.test("swap: first tick replaces the sprite with the current frame", function()
  local s = make()
  local b = battler()
  H.eq(s:tick({}, b, "front", 0), true)
  H.eq(b.sprite, "img:k0")
end)

H.test("swap: an unchanged frame does not rebuild", function()
  local s, calls = make()
  local b = battler()
  s:tick({}, b, "front", 0.1)
  s:tick({}, b, "front", 0.9)
  H.eq(calls.rebuild, 1, "rebuilds")
end)

H.test("swap: a new frame rebuilds", function()
  local s, calls = make()
  local b = battler()
  s:tick({}, b, "front", 0)
  H.eq(s:tick({}, b, "front", 1), true)
  H.eq(b.sprite, "img:k1")
  H.eq(calls.rebuild, 2)
end)

H.test("swap: the clock starts when the pic lands, not before", function()
  local landed = false
  local s, calls = make({
    landed = function() return landed end,
    pathFor = function(_, _, t) return t and ("k" .. math.floor(t)) or "rest" end,
  })
  local b = battler()
  s:tick({}, b, "front", 100)
  H.eq(b.sprite, "img:rest", "resting frame while it has not landed")
  s:tick({}, b, "front", 105)
  H.eq(b.sprite, "img:rest", "and still after time has passed")
  landed = true
  s:tick({}, b, "front", 106)
  H.eq(b.sprite, "img:k0", "second 0 is the moment it lands")
  s:tick({}, b, "front", 108.5)
  H.eq(b.sprite, "img:k2", "later frames follow that moment")
end)

H.test("swap: each battler has its own clock", function()
  local s = make({ pathFor = function(_, _, t) return "k" .. math.floor(t) end })
  local a, b = battler(), battler()
  s:tick({}, a, "front", 10)
  s:tick({}, b, "front", 13)
  s:tick({}, a, "front", 14)
  s:tick({}, b, "front", 14)
  H.eq(a.sprite, "img:k4")
  H.eq(b.sprite, "img:k1")
end)

H.test("swap: the frame the engine hook is rebuilt for is the time since landing", function()
  local seen
  local s = make({ rebuild = function(_, _, key, seconds) seen = seconds return "img:" .. key end })
  local b = battler()
  s:tick({}, b, "front", 50)
  s:tick({}, b, "front", 52.25)
  H.eq(seen, 2.25)
end)

H.test("swap: restart plays the animation again from its first frame", function()
  local s = make({ pathFor = function(_, _, t) return "k" .. math.floor(t) end })
  local b = battler()
  s:tick({}, b, "front", 10)
  s:tick({}, b, "front", 15)
  H.eq(b.sprite, "img:k5")
  s:restart(b, 16)
  s:tick({}, b, "front", 16)
  H.eq(b.sprite, "img:k0", "back to the first frame")
  s:tick({}, b, "front", 17.5)
  H.eq(b.sprite, "img:k1", "and running from there")
end)

H.test("swap: restart does nothing before the pic lands or after the engine takes it", function()
  local landed = false
  local s = make({ landed = function() return landed end,
                   pathFor = function(_, _, t) return t and ("k" .. math.floor(t)) or "rest" end })
  local b = battler()
  s:tick({}, b, "front", 1)
  s:restart(b, 2)                     -- not landed: no clock to reset
  landed = true
  s:tick({}, b, "front", 5)
  H.eq(b.sprite, "img:k0", "the clock still starts at landing, not at the restart")
  b.sprite = "transformed"
  s:tick({}, b, "front", 6)
  s:restart(b, 7)
  H.eq(s:tick({}, b, "front", 8), false)
  H.eq(b.sprite, "transformed")
  s:restart(nil, 9)                   -- a missing battler is safe
end)

H.test("swap: an engine-replaced sprite is left alone for good", function()
  local s = make()
  local b = battler()
  s:tick({}, b, "front", 0)
  b.sprite = "transformed"            -- the engine changed it (Transform, ghost)
  H.eq(s:tick({}, b, "front", 1), false)
  H.eq(s:tick({}, b, "front", 2), false)
  H.eq(b.sprite, "transformed")
end)

H.test("swap: a busy battler is skipped and resumes afterwards", function()
  local busy = true
  local s = make({ busy = function() return busy end })
  local b = battler()
  H.eq(s:tick({}, b, "front", 0), false)
  H.eq(b.sprite, "vanilla")
  busy = false
  H.eq(s:tick({}, b, "front", 1), true)
  H.eq(b.sprite, "img:k0", "the clock starts when it is first shown")
end)

H.test("swap: species with no dex in range are skipped", function()
  local s = make({ dexOf = function() return nil end })
  local b = battler()
  H.eq(s:tick({}, b, "front", 0), false)
  H.eq(b.sprite, "vanilla")
end)

H.test("swap: nothing cached yet leaves the vanilla sprite", function()
  local s = make({ pathFor = function() return nil end })
  local b = battler()
  H.eq(s:tick({}, b, "front", 0), false)
  H.eq(b.sprite, "vanilla")
end)

H.test("swap: a failed rebuild leaves the sprite untouched", function()
  local s = make({ rebuild = function() return nil end })
  local b = battler()
  H.eq(s:tick({}, b, "front", 0), false)
  H.eq(b.sprite, "vanilla")
end)

H.test("swap: a new battler table starts fresh", function()
  local s = make()
  local first = battler()
  s:tick({}, first, "front", 0)
  first.sprite = "transformed"
  s:tick({}, first, "front", 1)
  local second = battler()
  H.eq(s:tick({}, second, "front", 1), true)
  H.eq(second.sprite, "img:k0", "and gets a clock of its own")
end)

H.test("swap: missing battler or sprite is safe", function()
  local s = make()
  H.eq(s:tick({}, nil, "front", 0), false)
  H.eq(s:tick({}, { mon = { species = "X" } }, "front", 0), false)
end)
