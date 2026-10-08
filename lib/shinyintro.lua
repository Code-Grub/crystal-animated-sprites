-- Holds another mod's intro option off while ours is on, and gives it back.
--
-- SHINY_POKEMON draws a sparkle and plays a chime when a shiny appears; this
-- mod's entrance replaces that, so the two do not both play.  The option is
-- changed the way the engine's own options screen changes a mod's option at run
-- time: the loader's option table first, then mod.options_changed so the mod
-- drops what it cached.  Nothing is saved, so the next launch starts from the
-- player's own setting, and this puts the live value back if the entrance is
-- turned off during a session.
local ShinyIntro = {}
ShinyIntro.__index = ShinyIntro

-- modId: the other mod; key: its intro option
function ShinyIntro.new(modId, key)
  return setmetatable({ modId = modId, key = key, held = nil }, ShinyIntro)
end

-- holdOff true keeps the option off, false gives it back.  Returns true when it
-- changed the option, false when the other mod is not there or nothing needed
-- changing.
function ShinyIntro:sync(loader, holdOff)
  if not (loader and loader.optionSchemas and loader.optionSchemas[self.modId]) then
    return false
  end
  local changed = false
  local function set(value)
    changed = true
    loader.modOptions = loader.modOptions or {}
    local bucket = loader.modOptions[self.modId]
    if not bucket then bucket = {}; loader.modOptions[self.modId] = bucket end
    bucket[self.key] = value
    if loader.events and loader.events.emit then
      loader.events:emit("mod.options_changed",
        { mod = self.modId, key = self.key, value = value })
    end
  end
  local bucket = loader.modOptions and loader.modOptions[self.modId]
  if holdOff then
    if self.held == nil then
      local own = bucket and bucket[self.key]
      self.held = { value = own }
      if own ~= false then set(false) end
    end
  elseif self.held ~= nil then
    local own = self.held.value
    self.held = nil
    -- a player who had it off already never saw a change to undo
    if own ~= false then set(own) end
  end
  return changed
end

return ShinyIntro
