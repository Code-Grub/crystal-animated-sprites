package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local ShinyIntro = H.need("shinyintro")

-- SHINY_POKEMON draws its own sparkle and plays its own chime; while our
-- entrance is on it is held off, through the loader's option table and a
-- mod.options_changed event, the way the engine's options screen changes a
-- mod's option at run time.  Nothing is saved.
local function loader(opts)
  local l = { optionSchemas = { SHINY_POKEMON = {} }, modOptions = {}, emitted = {} }
  l.events = { emit = function(_, name, payload) l.emitted[#l.emitted + 1] = { name = name, payload = payload } end }
  for k, v in pairs(opts or {}) do l[k] = v end
  return l
end

H.test("shinyintro: holding it off sets the option and announces the change", function()
  local si, l = ShinyIntro.new("SHINY_POKEMON", "sparkles"), loader()
  H.eq(si:sync(l, true), true)
  H.eq(l.modOptions.SHINY_POKEMON.sparkles, false)
  H.eq(#l.emitted, 1)
  H.eq(l.emitted[1].name, "mod.options_changed")
  H.eq(l.emitted[1].payload.mod, "SHINY_POKEMON")
  H.eq(l.emitted[1].payload.key, "sparkles")
  H.eq(l.emitted[1].payload.value, false)
end)

H.test("shinyintro: asking again does nothing more", function()
  local si, l = ShinyIntro.new("SHINY_POKEMON", "sparkles"), loader()
  si:sync(l, true)
  si:sync(l, true)
  si:sync(l, true)
  H.eq(#l.emitted, 1, "announced once")
end)

H.test("shinyintro: releasing puts the player's own value back", function()
  for _, own in ipairs({ "unset", true }) do
    local si, l = ShinyIntro.new("SHINY_POKEMON", "sparkles"), loader()
    if own == true then l.modOptions.SHINY_POKEMON = { sparkles = true } end
    si:sync(l, true)
    H.eq(l.modOptions.SHINY_POKEMON.sparkles, false, "held off")
    si:sync(l, false)
    H.eq(l.modOptions.SHINY_POKEMON.sparkles, own == true and true or nil, "back to " .. tostring(own))
    H.eq(#l.emitted, 2, "the change back is announced too")
    H.eq(l.emitted[2].payload.value, own == true and true or nil)
  end
end)

H.test("shinyintro: a player who already turned it off keeps it off", function()
  local si, l = ShinyIntro.new("SHINY_POKEMON", "sparkles"), loader()
  l.modOptions.SHINY_POKEMON = { sparkles = false }
  si:sync(l, true)
  H.eq(#l.emitted, 0, "nothing to change")
  si:sync(l, false)
  H.eq(l.modOptions.SHINY_POKEMON.sparkles, false, "still off afterwards")
  H.eq(#l.emitted, 0)
end)

H.test("shinyintro: never held means nothing to give back", function()
  local si, l = ShinyIntro.new("SHINY_POKEMON", "sparkles"), loader()
  H.eq(si:sync(l, false), false)
  H.eq(#l.emitted, 0)
  H.eq(l.modOptions.SHINY_POKEMON, nil, "no bucket made for nothing")
end)

H.test("shinyintro: without the shiny mod, or without a loader, it does nothing", function()
  local si = ShinyIntro.new("SHINY_POKEMON", "sparkles")
  H.eq(si:sync(nil, true), false)
  local l = loader()
  l.optionSchemas = {}
  H.eq(si:sync(l, true), false)
  H.eq(#l.emitted, 0)
  H.eq(l.modOptions.SHINY_POKEMON, nil)
  l.optionSchemas = nil
  H.eq(si:sync(l, true), false)
end)

H.test("shinyintro: it still works when the loader has no event bus", function()
  local si, l = ShinyIntro.new("SHINY_POKEMON", "sparkles"), loader()
  l.events = nil
  H.eq(si:sync(l, true), true)
  H.eq(l.modOptions.SHINY_POKEMON.sparkles, false)
end)
