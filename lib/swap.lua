-- Decides when a battler's sprite image should be replaced by the next
-- animation frame.  Pure: every engine touchpoint is injected, so the rules
-- are testable without the engine.
--
--   deps.dexOf(screen, battler)          national dex 1..151, or nil
--   deps.busy(screen, battler)           true while the engine owns the pic
--   deps.landed(screen, battler)         optional; true once the pic is on show
--   deps.pathFor(dex, side, seconds)     the frame path to show, or nil
--   deps.rebuild(screen, battler, key, seconds)
--                                        an engine-built image for that frame
--
-- The animation plays once, from the moment the pic lands, as in Crystal; a
-- battler whose pic has not landed yet shows the resting frame.  With no
-- `landed` dep the clock starts on the first tick.
--
-- The engine reassigns battler.sprite itself for Transform and the ghost
-- battle.  Rather than naming those cases, a sprite that is no longer the
-- image we last set is treated as engine-owned and left alone for the rest of
-- that battler's life.
local Swap = {}
Swap.__index = Swap

function Swap.new(deps)
  return setmetatable({ deps = deps, owned = setmetatable({}, { __mode = "k" }) }, Swap)
end

function Swap:tick(screen, battler, side, now)
  if not (battler and battler.mon and battler.sprite) then return false end
  local deps = self.deps
  local dex = deps.dexOf(screen, battler)
  if not dex then return false end

  local rec = self.owned[battler]
  if not rec then
    rec = { last = battler.sprite }
    self.owned[battler] = rec
  end
  if battler.sprite ~= rec.last then rec.stolen = true end
  if rec.stolen or deps.busy(screen, battler) then return false end

  if not rec.start and (not deps.landed or deps.landed(screen, battler)) then
    rec.start = now
  end
  local seconds = rec.start and (now - rec.start) or nil
  local key = deps.pathFor(dex, side, seconds)
  if not key or key == rec.key then return false end

  local image = deps.rebuild(screen, battler, key, seconds)
  if not image then return false end
  battler.sprite, rec.last, rec.key = image, image, key
  return true
end

return Swap
