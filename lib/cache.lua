local Cache = {}
Cache.__index = Cache
Cache.FORMAT = 3 -- 1: opaque white backgrounds, 2: matted, 3: matted and known gaps cleared

function Cache.stamp(rom)
  return ("f%d-%02x%02x-%02x"):format(Cache.FORMAT, rom:u8(0x14E), rom:u8(0x14F),
    rom:u8(0x14C))
end

function Cache.new(store, stamp, modId)
  return setmetatable({ store = store, stamp = stamp, modId = modId, memo = {} }, Cache)
end

function Cache:key(rest) return self.stamp .. "/" .. rest end

function Cache:valid()
  return self.store.read("stamp") == self.stamp
end

function Cache:begin()
  return self.store.write("stamp", self.stamp)
end

function Cache:framePath(dex, index, mirrored)
  return ("mod_cache/%s/%s/front/%03d/%d%s.png"):format(self.modId, self.stamp, dex,
    index, mirrored and "m" or "")
end

function Cache:backPath(dex)
  return ("mod_cache/%s/%s/back/%03d.png"):format(self.modId, self.stamp, dex)
end

local function encodeMeta(result, frameIndexes)
  local steps = {}
  for _, s in ipairs(result.timeline) do steps[#steps + 1] = s.frame .. ":" .. s.ticks end
  return ("size=%d\nframes=%s\ntimeline=%s\n"):format(result.size,
    table.concat(frameIndexes, ","), table.concat(steps, ","))
end

local function decodeMeta(text)
  local size = tonumber(text:match("size=(%d+)"))
  if not size then return nil end
  local meta = { size = size, frames = {}, timeline = {} }
  for n in (text:match("frames=([%d,]*)") or ""):gmatch("%d+") do
    meta.frames[tonumber(n)] = true
  end
  for frame, ticks in (text:match("timeline=([%d:,]*)") or ""):gmatch("(%d+):(%d+)") do
    meta.timeline[#meta.timeline + 1] = { frame = tonumber(frame), ticks = tonumber(ticks) }
  end
  return meta
end

function Cache:put(dex, result)
  local indexes = {}
  for index in pairs(result.frames) do indexes[#indexes + 1] = index end
  table.sort(indexes)
  for _, index in ipairs(indexes) do
    local ok, err = self.store.write(self:key(("front/%03d/%d.png"):format(dex, index)),
      result.frames[index])
    if not ok then return false, tostring(err) end
    local mirrored = result.flipped and result.flipped[index]
    if mirrored then
      ok, err = self.store.write(self:key(("front/%03d/%dm.png"):format(dex, index)), mirrored)
      if not ok then return false, tostring(err) end
    end
  end
  local ok, err = self.store.write(self:key(("back/%03d.png"):format(dex)), result.back)
  if not ok then return false, tostring(err) end
  ok, err = self.store.write(self:key(("meta/%03d"):format(dex)), encodeMeta(result, indexes))
  if not ok then return false, tostring(err) end
  self.memo[dex] = nil
  return true
end

function Cache:meta(dex)
  local hit = self.memo[dex]
  if hit ~= nil then return hit or nil end
  local text = self.store.read(self:key(("meta/%03d"):format(dex)))
  local meta = text and decodeMeta(text) or nil
  self.memo[dex] = meta or false
  return meta
end

-- True only when the meta entry parses AND every file it promises is still
-- on disk.  A meta file alone is not enough: a partly deleted cache would
-- otherwise hand the engine a path it cannot load.
function Cache:complete(dex)
  local meta = self:meta(dex)
  if not meta then return false end
  local function present(rest) return self.store.info(self:key(rest)) ~= nil end
  if not present(("back/%03d.png"):format(dex)) then return false end
  for index in pairs(meta.frames) do
    if not present(("front/%03d/%d.png"):format(dex, index)) then return false end
    if not present(("front/%03d/%dm.png"):format(dex, index)) then return false end
  end
  return true
end

return Cache
