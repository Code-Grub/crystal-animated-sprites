-- A view of the game for PartyMenu.drawIcon, with one species' icon entry
-- pointing at our sheet.  drawIcon reads game.data.icons.bySpecies[species] and
-- draws an entry of the form { image = path, trueColor = bool } whole, with
-- its two frames, so handing it a game whose table has that entry is all it
-- takes.  The real game data is never modified: the view reads through to it.
-- Views are kept per game, species and entry so a menu that draws every frame
-- builds nothing after the first.
local IconShim = {}
IconShim.__index = IconShim

function IconShim.new()
  return setmetatable({ games = setmetatable({}, { __mode = "k" }) }, IconShim)
end

function IconShim:view(game, species, entry)
  local data = game and game.data
  local icons = data and data.icons
  if not icons then return nil end
  local perGame = self.games[game]
  if not perGame then
    perGame = {}
    self.games[game] = perGame
  end
  local kept = perGame[species]
  if kept and kept.image == entry.image and kept.trueColor == (entry.trueColor and true or false) then
    return kept.view
  end
  local bySpecies = setmetatable({ [species] = entry }, { __index = icons.bySpecies })
  local view = setmetatable({
    data = setmetatable({
      icons = setmetatable({ bySpecies = bySpecies }, { __index = icons }),
    }, { __index = data }),
  }, { __index = game })
  perGame[species] = { image = entry.image, trueColor = entry.trueColor and true or false, view = view }
  return view
end

return IconShim
