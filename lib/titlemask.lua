-- Which part of the title screen's Pokemon is not hidden by Red.
--
-- The title screen draws Red over the Pokemon.  For a true-colour Pokemon the
-- engine redraws its rectangle unshaded after the palette pass, which would put
-- Red's art there in raw grey, so it leaves Red's whole bounding box out.  The
-- part of the Pokemon that reaches into that box but not onto Red's own pixels
-- then gets Red's palette: Scyther's claws turn purple.  This works out the
-- rectangles to redraw instead, leaving out only the pixels Red really covers.
--
-- Everything here is plain geometry; the caller supplies Red's pixels.
local TitleMask = {}

-- alphaAt(x, y) is true where the picture is drawn.  Returns, per row from 0,
-- the list of { x1, x2 } stretches of drawn pixels, inclusive.
function TitleMask.rowRuns(alphaAt, w, h)
  local rows = {}
  for y = 0, h - 1 do
    local runs, start = {}, nil
    for x = 0, w - 1 do
      if alphaAt(x, y) then
        start = start or x
      elseif start then
        runs[#runs + 1] = { start, x - 1 }
        start = nil
      end
    end
    if start then runs[#runs + 1] = { start, w - 1 } end
    rows[y] = runs
  end
  return rows
end

-- the drawn stretches of screen row y: placements are { runs, qx, qy, qw, qh,
-- x, y }, a quad of the source picture with its top-left at screen (x, y)
local function covered(placements, y)
  local spans = {}
  for _, p in ipairs(placements) do
    local sy = y - p.y + p.qy
    if sy >= p.qy and sy < p.qy + p.qh then
      for _, run in ipairs(p.runs[sy] or {}) do
        local a, b = math.max(run[1], p.qx), math.min(run[2], p.qx + p.qw - 1)
        if a <= b then spans[#spans + 1] = { p.x + a - p.qx, p.x + b - p.qx } end
      end
    end
  end
  table.sort(spans, function(l, r) return l[1] < r[1] end)
  return spans
end

-- rect is { x, y, w, h }.  Returns the rects { x, y, w, h } that cover rect
-- minus the pixels the placements draw, with identical spans on neighbouring
-- rows merged into one tall rect.
function TitleMask.freeRects(rect, placements)
  local x0, y0, w, h = rect[1], rect[2], rect[3], rect[4]
  local out, open = {}, {}
  for y = y0, y0 + h - 1 do
    local free, cursor = {}, x0
    for _, span in ipairs(covered(placements, y)) do
      if span[1] > cursor then free[#free + 1] = { cursor, math.min(span[1] - 1, x0 + w - 1) } end
      cursor = math.max(cursor, span[2] + 1)
    end
    if cursor <= x0 + w - 1 then free[#free + 1] = { cursor, x0 + w - 1 } end
    local nextOpen = {}
    for _, f in ipairs(free) do
      if f[2] >= x0 and f[1] <= x0 + w - 1 and f[1] <= f[2] then
        local key = f[1] .. ":" .. f[2]
        local rectOpen = open[key]
        if rectOpen then
          rectOpen[4] = rectOpen[4] + 1
          nextOpen[key] = rectOpen
        else
          local r = { f[1], y, f[2] - f[1] + 1, 1 }
          out[#out + 1] = r
          nextOpen[key] = r
        end
      end
    end
    open = nextOpen
  end
  return out
end

return TitleMask
