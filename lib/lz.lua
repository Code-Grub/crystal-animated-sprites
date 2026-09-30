local LZ = {}

local function flip(v)
  local out = 0
  for b = 0, 7 do
    if math.floor(v / 2 ^ b) % 2 == 1 then out = out + 2 ^ (7 - b) end
  end
  return out
end

function LZ.decompress(src, start)
  local pos, out, n = start or 1, {}, 0

  local function byte()
    local v = src:byte(pos)
    assert(v ~= nil, "truncated Crystal LZ stream")
    pos = pos + 1
    return v
  end
  local function emit(v)
    n = n + 1
    out[n] = v
  end

  while true do
    local header = byte()
    if header == 0xFF then break end
    local command, length = math.floor(header / 32), header % 32
    if command == 7 then
      command = math.floor(length / 4)
      length = (length % 4) * 256 + byte()
    end
    length = length + 1

    if command == 0 then
      for _ = 1, length do emit(byte()) end
    elseif command == 1 then
      local v = byte()
      for _ = 1, length do emit(v) end
    elseif command == 2 then
      local a, b = byte(), byte()
      for i = 1, length do emit(i % 2 == 1 and a or b) end
    elseif command == 3 then
      for _ = 1, length do emit(0) end
    elseif command >= 4 and command <= 6 then
      local first = byte()
      local from
      if first >= 0x80 then
        from = n - (first - 0x80)
      else
        from = first * 256 + byte() + 1
      end
      for i = 0, length - 1 do
        local v = out[command == 6 and from - i or from + i]
        assert(v ~= nil, "invalid back-reference in Crystal LZ stream")
        emit(command == 5 and flip(v) or v)
      end
    else
      error("invalid Crystal LZ command " .. command)
    end
  end
  return out, pos
end

return LZ
