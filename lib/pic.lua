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

  -- Known blemishes: a single colour-0 pixel boxed in by the outline is often a
  -- gap the edge fill cannot reach (Pikachu's tail base), but it can equally be
  -- a glint in an eye, and the two look the same up close.  So a speck is
  -- cleared only where the caller names it, and only if it really is a
  -- walled-in white pixel with black on all four sides.
  local BLACK = 3
  for _, at in ipairs(known or {}) do
    local x, y = at[1], at[2]
    if x >= 1 and x < width - 1 and y >= 1 and y < height - 1 then
      local i = y * width + x + 1
      if pixels[i] == 0 and alpha[i] == 1
         and pixels[i - 1] == BLACK and pixels[i + 1] == BLACK
         and pixels[i - width] == BLACK and pixels[i + width] == BLACK then
        alpha[i] = 0
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
