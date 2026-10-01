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
--
-- Redrawn as abutting rects, the join between two can show as a hairline when
-- the screen is scaled by a fraction.  So where the free span changes from one
-- row to the next, the narrower rect grows one row into the wider one's row
-- (every pixel it grows over is free), and spans that only partly overlap get a
-- short rect over the part they share.  No rect is added in the usual case.
function TitleMask.freeRects(rect, placements)
  local x0, y0, w, h = rect[1], rect[2], rect[3], rect[4]
  local right = x0 + w - 1
  local out, open, previous = {}, {}, nil
  for y = y0, y0 + h - 1 do
    local free, cursor = {}, x0
    for _, span in ipairs(covered(placements, y)) do
      if span[1] > cursor then free[#free + 1] = { cursor, math.min(span[1] - 1, right) } end
      cursor = math.max(cursor, span[2] + 1)
    end
    if cursor <= right then free[#free + 1] = { cursor, right } end
    local current, nextOpen = {}, {}
    for _, f in ipairs(free) do
      if f[1] <= f[2] and f[2] >= x0 and f[1] <= right then
        local key = f[1] .. ":" .. f[2]
        local rectOpen = open[key]
        if rectOpen then
          rectOpen[4] = rectOpen[4] + 1
        else
          rectOpen = { f[1], y, f[2] - f[1] + 1, 1 }
          out[#out + 1] = rectOpen
        end
        nextOpen[key] = rectOpen
        current[#current + 1] = { f[1], f[2], rect = rectOpen }
      end
    end
    if previous then
      for _, a in ipairs(previous) do
        for _, b in ipairs(current) do
          local lo, hi = math.max(a[1], b[1]), math.min(a[2], b[2])
          if lo <= hi and not (a[1] == b[1] and a[2] == b[2]) then
            if a[1] <= b[1] and b[2] <= a[2] then
              -- b sits inside the wider row above it: grow it up one row
              if not b.grownUp then
                b.rect[2], b.rect[4], b.grownUp = b.rect[2] - 1, b.rect[4] + 1, true
              end
            elseif b[1] <= a[1] and a[2] <= b[2] then
              -- a sits inside the wider row below it: grow it down one row
              if not a.grownDown then
                a.rect[4], a.grownDown = a.rect[4] + 1, true
              end
            else
              out[#out + 1] = { lo, y - 1, hi - lo + 1, 2 }
            end
          end
        end
      end
    end
    previous = current
    open = nextOpen
  end
  return out
end

return TitleMask
