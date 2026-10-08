-- The state of a shiny's entrance: when it started, what is on screen, which
-- chimes are due, and how the cry and the front animation are held back until
-- it is over.  Pure: the engine's pieces (the clock, the option, the shiny
-- test) are handed in, so the rules are testable without the engine.
--
--   deps.now()          seconds, the same clock the sprite swap runs on
--   deps.enabled()      is SHINY ENTRANCE on and the art and chime readable
--   deps.isShiny(mon)   the test the shiny mods use
--
-- Crystal plays the send-out animation, then a shiny's sparkle, and only then
-- the cry and the front animation (ShowSetEnemyMonAndSendOutAnimation).  The
-- engine asks for the entrance cry as the Pokemon takes the field, so that is
-- the moment the entrance starts, and the cry is played after it.
local need = ...
local Sparkle = need("sparkle")

local Entrance = {}
Entrance.__index = Entrance

-- How long a shiny may wait for its cry to be requested before its animation
-- is let go anyway, in case some path never asks.
Entrance.GRACE = 3

local FPS = 60

function Entrance.new(deps)
  return setmetatable({
    deps = deps,
    records = setmetatable({}, { __mode = "k" }),
    waiting = setmetatable({}, { __mode = "k" }),
  }, Entrance)
end

function Entrance:applies(battler)
  return battler ~= nil and battler.mon ~= nil
    and self.deps.enabled() and self.deps.isShiny(battler.mon) and true or false
end

function Entrance:begin(battler)
  self.records[battler] = { start = self.deps.now(), mon = battler.mon, chimed = 0 }
  self.waiting[battler] = nil
end

-- The sparkle's frame (60 to the second), or nil when this battler has no
-- entrance, or has one that belonged to another Pokemon.
function Entrance:frame(battler)
  local record = battler and self.records[battler]
  if not record or record.mon ~= battler.mon then return nil end
  return (self.deps.now() - record.start) * FPS
end

function Entrance:active(battler)
  local frame = self:frame(battler)
  return frame ~= nil and not Sparkle.done(frame)
end

-- What the queue waits on: it only asks whether the sound is still playing,
-- how long to budget for it, and tells it to stop.
function Entrance:gate(battler)
  return {
    isPlaying = function() return self:active(battler) end,
    getDuration = function() return Sparkle.TOTAL / FPS end,
    getPitch = function() return 1 end,
    stop = function() end,
  }
end

-- Wraps the engine's entrance cry.  `original(battle, battler)` plays it and
-- returns the sound to wait on.  For a shiny, starts the sparkle, queues a wait
-- for it and then the real cry, and hands back nothing to wait on yet.
function Entrance:holdCry(battle, battler, original)
  if not self:applies(battler) then return original(battle, battler) end
  self:begin(battler)
  battle:waitSfxNext(function() return self:gate(battler) end)
  battle:actNext(function() battle:waitSfxNext(original(battle, battler)) end)
  return nil
end

-- May this battler's front animation start?  A shiny waits for its sparkle,
-- and for its cry to have been requested, but not for ever.
function Entrance:released(battler)
  if not self:applies(battler) then return true end
  local record = self.records[battler]
  if record and record.mon == battler.mon then return not self:active(battler) end
  local now = self.deps.now()
  local since = self.waiting[battler]
  if not since then
    self.waiting[battler] = now
    return false
  end
  return now - since > Entrance.GRACE
end

-- What to draw now: { id, dx, dy } for each sparkle on screen.
function Entrance:sparkles(battler)
  local frame = self:frame(battler)
  if not frame or Sparkle.done(frame) then return {} end
  return Sparkle.visible(frame)
end

-- How many chimes to play now: one for each sparkle that has appeared since
-- the last look, however late that look is.
function Entrance:chimesDue(battler)
  local record = battler and self.records[battler]
  local frame = self:frame(battler)
  if not record or not frame then return 0 end
  local due = Sparkle.appeared(frame) - record.chimed
  if due <= 0 then return 0 end
  record.chimed = record.chimed + due
  return due
end

return Entrance
