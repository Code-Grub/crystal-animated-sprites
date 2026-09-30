local Pic = {}

function Pic.tilePixels(data, t)
  local px, base = {}, t * 16
  for row = 0, 7 do
    local lo = data[base + row * 2 + 1] or 0
    local hi = data[base + row * 2 + 2] or 0
    for x = 0, 7 do
      local bit = 7 - x
      px[row * 8 + x + 1] = math.floor(lo / 2 ^ bit) % 2
        + 2 * (math.floor(hi / 2 ^ bit) % 2)
    end
  end
  return px
end

function Pic.identityMap(size)
  local m = {}
  for i = 1, size * size do m[i] = i - 1 end
  return m
end

function Pic.compose(data, map, size, order)
  local width = size * 8
  local out = {}
  for i = 0, size * size - 1 do
    local tileRow, tileCol
    if order == "columns" then
      tileRow, tileCol = i % size, math.floor(i / size)
    else
      tileRow, tileCol = math.floor(i / size), i % size
    end
    local px = Pic.tilePixels(data, map[i + 1])
    for y = 0, 7 do
      for x = 0, 7 do
        out[(tileRow * 8 + y) * width + tileCol * 8 + x + 1] = px[y * 8 + x + 1]
      end
    end
  end
  return out, width, width
end

-- Alpha plane for a pic: 0 for the colour-0 background that is connected to the
-- edge of the pic, 1 for everything else.  Colour 0 that is walled in by the
-- sprite (an eye highlight, a shine) stays opaque, and a corner-to-corner gap
-- does not count as a way out.
function Pic.matte(pixels, width, known)
  local height = #pixels / width
  local alpha, queue, head = {}, {}, 1
  for i = 1, #pixels do alpha[i] = 1 end
  local function visit(x, y)
    local i = y * width + x + 1
    if alpha[i] == 1 and pixels[i] == 0 then
      alpha[i] = 0
      queue[#queue + 1] = i
    end
  end
  for x = 0, width - 1 do visit(x, 0); visit(x, height - 1) end
  for y = 0, height - 1 do visit(0, y); visit(width - 1, y) end
  while head <= #queue do
    local i = queue[head]
    head = head + 1
    local x, y = (i - 1) % width, math.floor((i - 1) / width)
    if x > 0 then visit(x - 1, y) end
    if x < width - 1 then visit(x + 1, y) end
    if y > 0 then visit(x, y - 1) end
    if y < height - 1 then visit(x, y + 1) end
  end

  -- Known holes: a walled-in white region is often a real gap the edge fill
  -- cannot reach (between a tail and a body, inside a hood), but it can equally
  -- be something meant to be white (an eye, a tongue), and the two look the same
  -- to code.  So a region is cleared only where the caller names a pixel of it,
  -- and only while it is still bounded by black outline alone.  That last check
  -- keeps a listed pixel from clearing the wrong thing in an animation frame
  -- where the art around it is different.
  local BLACK = 3
  for _, at in ipairs(known or {}) do
    local x, y = at[1], at[2]
    local start = (x >= 0 and x < width and y >= 0 and y < height) and (y * width + x + 1)
    if start and pixels[start] == 0 and alpha[start] == 1 then
      local comp, members, qi, enclosed = { start }, { [start] = true }, 1, true
      while qi <= #comp and enclosed do
        local i = comp[qi]
        qi = qi + 1
        local cx, cy = (i - 1) % width, math.floor((i - 1) / width)
        local around = { cx > 0 and i - 1, cx < width - 1 and i + 1,
                         cy > 0 and i - width, cy < height - 1 and i + width }
        for k = 1, 4 do
          local n = around[k]
          if not n then enclosed = false break end
          if pixels[n] == 0 and alpha[n] == 1 then
            if not members[n] then members[n] = true; comp[#comp + 1] = n end
          elseif pixels[n] ~= BLACK then
            enclosed = false break
          end
        end
      end
      if enclosed then
        for _, i in ipairs(comp) do alpha[i] = 0 end
      end
    end
  end
  return alpha
end

-- Hand edits on top of the matte: runs { y, x1, x2, "clear" | "keep" }.  "clear"
-- makes white pixels transparent, "keep" makes them opaque.  Only colour-0
-- (white) pixels are ever changed, so an edit can never punch through the
-- sprite's own art, and anything outside the pic or with another action is
-- ignored.  Returns the same alpha table.
function Pic.applyEdits(pixels, alpha, width, runs)
  local height = #pixels / width
  for _, run in ipairs(runs or {}) do
    local y, x1, x2, action = run[1], run[2], run[3], run[4]
    if y >= 0 and y < height and (action == "clear" or action == "keep") then
      local value = action == "keep" and 1 or 0
      for x = math.max(0, x1), math.min(width - 1, x2) do
        local i = y * width + x + 1
        if pixels[i] == 0 then alpha[i] = value end
      end
    end
  end
  return alpha
end

function Pic.mirror(pixels, width)
  local out, height = {}, #pixels / width
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      out[y * width + x + 1] = pixels[y * width + (width - 1 - x) + 1]
    end
  end
  return out
end

return Pic
