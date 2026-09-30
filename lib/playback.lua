local Playback = {}
Playback.TICKS_PER_SECOND = 60
Playback.REST_SECONDS = 2

function Playback.frameAt(timeline, seconds)
  if not timeline or #timeline == 0 or not seconds or seconds < 0 then return 0 end
  local total = 0
  for _, step in ipairs(timeline) do total = total + step.ticks / Playback.TICKS_PER_SECOND end
  local t = seconds % (total + Playback.REST_SECONDS)
  if t >= total then return 0 end
  local acc = 0
  for _, step in ipairs(timeline) do
    acc = acc + step.ticks / Playback.TICKS_PER_SECOND
    if t < acc then return step.frame end
  end
  return 0
end

return Playback
