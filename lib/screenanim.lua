-- Animates the picture on the Pokedex entry and the stats screen.  Those
-- screens load their picture once when they open and draw screen.sprite every
-- frame, so this swaps screen.sprite for the frame that belongs to the time
-- since the picture appeared.  Kept free of the engine: the caller says which screen is on top
-- and supplies the path and image lookups.
--
--   deps.pathFor(screen, seconds)  frame path to show, or nil for none
--   deps.load(path)                an image, or nil when it cannot be loaded
local ScreenAnim = {}
ScreenAnim.__index = ScreenAnim

function ScreenAnim.new(deps)
  return setmetatable({ deps = deps }, ScreenAnim)
end

-- screen: the entry screen when it is the top state, otherwise nil.
function ScreenAnim:tick(screen, now)
  if not screen then
    self.screen = nil
    return
  end
  -- the picture is not on show until the entry's short delay (picDelay) or the
  -- stats screen's opening flash (whiteHold) has run out
  if (screen.picDelay or 0) + (screen.whiteHold or 0) > 0 then return end
  if self.screen ~= screen then
    self.screen, self.start, self.shown = screen, now, nil
  end
  local path = self.deps.pathFor(screen, now - self.start)
  if not path or path == self.shown then return end
  local image = self.deps.load(path)
  if image then
    screen.sprite = image
    -- Battle Art wraps the screen's draw and, unless one of its own sprite
    -- packs applies, sets screen.sprite back to the picture it remembered when
    -- the screen was created, every frame.  Keep that memory current so the
    -- swap above is not undone.
    if screen.__battleArtOriginalSprite ~= nil then
      screen.__battleArtOriginalSprite = image
    end
    self.shown = path
  end
end

return ScreenAnim
