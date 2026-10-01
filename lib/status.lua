-- The diagnostics readout: a few short lines drawn over the battle when the
-- DIAGNOSTICS option is on.  Kept pure so it can be tested without a screen.
-- The game font is 8px wide on a 160px screen, so a line holds 20 characters.
local Status = {}

local WIDTH = 20

local function side(prefix, who)
  if not who then return prefix .. "--- ----" end
  return ("%s%03d %s"):format(prefix, who.dex, who.source == "cas" and "CAS" or "GAME")
end

function Status.lines(s)
  local lines = {
    ("V%s %s"):format(s.version, s.stamp:upper()),
    ("READY %d FAIL %d"):format(s.ready, s.failed),
    ("JOB %s RUN %d WAIT %d"):format(s.jobs and "OK" or "NO", s.running, s.waiting),
    side("E", s.enemy) .. " " .. side("P", s.player),
  }
  -- what the Pokedex entry animation last saw, and the newest screens the game
  -- stacked, so a report can say which screen the entry really is
  if s.note then lines[#lines + 1] = tostring(s.note) end
  for i = 1, math.min(2, #(s.screens or {})) do
    lines[#lines + 1] = "SCR " .. tostring(s.screens[i])
  end
  if s.err then lines[#lines + 1] = ("ERR " .. tostring(s.err):upper()):sub(1, WIDTH) end
  for i, line in ipairs(lines) do lines[i] = line:sub(1, WIDTH) end
  return lines
end

return Status
