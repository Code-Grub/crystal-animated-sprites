-- Finds the moment a Pokemon uses a move, so its front animation can play
-- again.  Pure: it only reads the battle screen's fields.
--
-- The engine queues one row per move animation and puts it back at the front
-- of the queue while it waits out a short delay, whether or not the player has
-- battle animations switched on.  That row, seen for the first time, is the
-- signal.  It is the only one that exists with animations OFF, which never
-- start the animation player.  With animations on, the animation starting
-- (animPlaying turning on) is a second signal, kept for a frame the first one
-- slipped past; a move seen by both counts once.
--
-- Ball tosses, send-out poofs and the like are queued the same way, and all
-- their names end in _ANIM; no move's name does.
local Attack = {}

local SAME_MOVE_SECONDS = 0.5

local function isMove(name)
  return type(name) == "string" and not name:find("_ANIM$")
end

-- state: a table kept per screen, starting empty.  Returns the battler that
-- has just started a move, or nil.
function Attack.update(screen, state, now)
  local who
  local item = screen.queue and screen.queue[1]
  if item and item ~= state.item and isMove(item.anim)
     and item.attackerIsPlayer ~= nil and (item.animDelayed or item.animOffDelayed) then
    state.item = item
    who = item.attackerIsPlayer and "player" or "enemy"
  end

  local playing = screen.animPlaying and true or false
  if not who and playing and not state.playing and isMove(screen.animName) then
    who = screen.animAttackerIsPlayer and "player" or "enemy"
    local last = state.last
    if last and last.who == who and now - last.at < SAME_MOVE_SECONDS then who = nil end
  end
  state.playing = playing

  if not who then return nil end
  state.last = { who = who, at = now }
  return screen[who]
end

return Attack
