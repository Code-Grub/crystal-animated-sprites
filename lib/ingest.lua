-- Writes decoded species into the cache a few at a time.  A full decode is
-- about 1,600 small files, and writing them all in one frame is a visible
-- hitch, so results are queued here and drained by a per-frame budget.
--
--   hooks.onPut(dex)        a species was written
--   hooks.onFail(dex, err)  a species could not be written
local Ingest = {}
Ingest.__index = Ingest

function Ingest.new(cache, hooks)
  return setmetatable({ cache = cache, hooks = hooks or {}, queue = {} }, Ingest)
end

function Ingest:enqueue(species)
  for dex, decoded in pairs(species) do
    self.queue[#self.queue + 1] = { dex = dex, decoded = decoded }
  end
  table.sort(self.queue, function(a, b) return a.dex < b.dex end)
end

function Ingest:pending()
  return #self.queue
end

function Ingest:step(budget)
  local done = 0
  while done < budget and #self.queue > 0 do
    local item = table.remove(self.queue, 1)
    local ok, err = self.cache:put(item.dex, item.decoded)
    if ok then
      if self.hooks.onPut then self.hooks.onPut(item.dex) end
    elseif self.hooks.onFail then
      self.hooks.onFail(item.dex, tostring(err))
    end
    done = done + 1
  end
  return done
end

return Ingest
