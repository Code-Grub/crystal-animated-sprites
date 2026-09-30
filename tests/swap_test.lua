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
  H.eq(b.sprite, "img:k1")
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
  H.eq(second.sprite, "img:k1")
end)

H.test("swap: missing battler or sprite is safe", function()
  local s = make()
  H.eq(s:tick({}, nil, "front", 0), false)
  H.eq(s:tick({}, { mon = { species = "X" } }, "front", 0), false)
end)
