package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local ScreenAnim = H.need("screenanim")

-- frame number is whole seconds elapsed, so a test reads at a glance
local function make(over)
  local calls = { load = 0 }
  local deps = {
    pathFor = function(_, seconds) return "frame" .. math.floor(seconds) end,
    load = function(path)
      calls.load = calls.load + 1
      return "img:" .. path
    end,
  }
  for k, v in pairs(over or {}) do deps[k] = v end
  return ScreenAnim.new(deps), calls
end

local function screen() return { picDelay = 0, sprite = "vanilla", species = "X" } end

H.test("screenanim: nothing happens while no entry screen is up", function()
  local a, calls = make()
  a:tick(nil, 0)
  H.eq(calls.load, 0)
end)

H.test("screenanim: the picture is left alone until the entry shows it", function()
  local a = make()
  local s = screen()
  s.picDelay = 12
  a:tick(s, 0)
  H.eq(s.sprite, "vanilla")
end)

H.test("screenanim: frames follow the time since the picture appeared", function()
  local a = make()
  local s = screen()
  a:tick(s, 100)
  H.eq(s.sprite, "img:frame0")
  a:tick(s, 101.5)
  H.eq(s.sprite, "img:frame1")
  a:tick(s, 103.2)
  H.eq(s.sprite, "img:frame3")
end)

H.test("screenanim: the clock starts when the picture appears, not when the screen opens", function()
  local a = make()
  local s = screen()
  s.picDelay = 30
  a:tick(s, 50)
  a:tick(s, 60)
  s.picDelay = 0
  a:tick(s, 61)
  H.eq(s.sprite, "img:frame0", "first visible tick is the first frame")
  a:tick(s, 62)
  H.eq(s.sprite, "img:frame1")
end)

H.test("screenanim: an unchanged frame is not loaded again", function()
  local a, calls = make()
  local s = screen()
  a:tick(s, 0)
  a:tick(s, 0.2)
  a:tick(s, 0.4)
  H.eq(calls.load, 1)
end)

H.test("screenanim: a new entry screen restarts the clock", function()
  local a = make()
  local first = screen()
  a:tick(first, 10)
  a:tick(first, 13)
  H.eq(first.sprite, "img:frame3")
  local second = screen()
  a:tick(second, 14)
  H.eq(second.sprite, "img:frame0")
end)

H.test("screenanim: leaving the screen and coming back restarts it", function()
  local a = make()
  local s = screen()
  a:tick(s, 0)
  a:tick(s, 2)
  a:tick(nil, 3)
  s.sprite = "vanilla"
  a:tick(s, 5)
  H.eq(s.sprite, "img:frame0")
end)

H.test("screenanim: a species with nothing cached keeps the engine's picture", function()
  local a, calls = make({ pathFor = function() return nil end })
  local s = screen()
  a:tick(s, 0)
  a:tick(s, 5)
  H.eq(s.sprite, "vanilla")
  H.eq(calls.load, 0)
end)

H.test("screenanim: a frame that fails to load keeps the last good picture and is retried", function()
  local fail = true
  local a, calls = make({ load = function(path)
    if fail then return nil end
    return "img:" .. path
  end })
  local s = screen()
  a:tick(s, 0)
  H.eq(s.sprite, "vanilla")
  fail = false
  a:tick(s, 0.1)
  H.eq(s.sprite, "img:frame0")
end)

H.test("screenanim: Battle Art's remembered picture follows, or it puts the old one back", function()
  local a = make()
  local s = screen()
  s.__battleArtOriginalSprite = "vanilla"
  a:tick(s, 0)
  H.eq(s.__battleArtOriginalSprite, "img:frame0")
  a:tick(s, 2)
  H.eq(s.__battleArtOriginalSprite, "img:frame2")
  H.eq(s.sprite, "img:frame2")
end)

H.test("screenanim: a screen without that field does not grow one", function()
  local a = make()
  local s = screen()
  a:tick(s, 0)
  H.eq(s.__battleArtOriginalSprite, nil)
end)

H.test("screenanim: the stats screen's opening flash holds the clock back too", function()
  local a = make()
  local s = screen()
  s.picDelay = nil
  s.whiteHold = 20
  a:tick(s, 10)
  H.eq(s.sprite, "vanilla")
  s.whiteHold = 0
  a:tick(s, 11)
  H.eq(s.sprite, "img:frame0")
  a:tick(s, 12)
  H.eq(s.sprite, "img:frame1")
end)
