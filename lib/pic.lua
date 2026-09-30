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

return Pic
