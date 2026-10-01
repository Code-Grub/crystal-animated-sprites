local Playback = {}
Playback.TICKS_PER_SECOND = 60

-- Crystal plays a front animation once, when the picture appears, and then
-- leaves it on its resting frame.  `seconds` is the time since it appeared;
-- nil or negative means it has not appeared yet.
function Playback.frameAt(timeline, seconds)
  if not timeline or #timeline == 0 or not seconds or seconds < 0 then return 0 end
  local total = 0
  for _, step in ipairs(timeline) do total = total + step.ticks / Playback.TICKS_PER_SECOND end
  if seconds >= total then return 0 end
  local t = seconds
  local acc = 0
  for _, step in ipairs(timeline) do
    acc = acc + step.ticks / Playback.TICKS_PER_SECOND
    if t < acc then return step.frame end
  end
  return 0
end

return Playback
