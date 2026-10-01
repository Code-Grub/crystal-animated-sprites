-- Real-engine capture of the non-battle screens that show a Pokemon (dev tool,
-- not a unit test).  Opens each screen with CAS_SPECIES in the party and
-- screenshots it, so the Crystal art can be checked for size and placement.
--
--   cd C:/g2dev
--   POKEPORT_DRIVER=C:/Users/camwr/Desktop/Gen1Recomp/crystal-animated-sprites/tools/screen_shots.lua \
--     POKEPORT_IDENTITY=cas POKEPORT_TOUCH=0 CAS_SPECIES=PIDGEY \
--     SHOT_DIR=C:/Users/camwr/AppData/Local/Temp/cas/screens \
--     "C:/Program Files/LOVE/lovec.exe" .
--
-- CAS_SCREENS=summary,dex,... limits which screens run.  Each screen runs in
-- a pcall, so one that cannot be opened here is logged and skipped.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "C:/tmp/cas/screens"
  local SPECIES = os.getenv("CAS_SPECIES") or "PIDGEY"
  local only = os.getenv("CAS_SCREENS")
  local Pokemon = require("src.pokemon.Pokemon")

  game.save.party = { Pokemon.new(game.data, SPECIES, 20) }
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  U.wait(10)
  if not game.overworld then U.log("FAIL no overworld") return end

  local function wanted(name)
    if not only then return true end
    for n in only:gmatch("[^,]+") do if n == name then return true end end
    return false
  end

  local function show(name, make, frames)
    if not wanted(name) then return end
    local ok, err = pcall(function()
      local state = make()
      game.stack:push(state)
      U.wait(frames or 150)
      U.shot(game, ("%s/%s_%s.png"):format(DIR, name, SPECIES))
      U.log("shot", name, tostring(state.sprite or state.pic))
      game.stack:pop()
      U.wait(5)
    end)
    if not ok then U.log("skipped", name, tostring(err)) end
  end

  -- which art each screen is handed
  for _, kind in ipairs({ "summary", "dex", "evolution", "hof", "trade", "title", "oak", "credits" }) do
    local path = require("src.pokemon.Sprites").path(game.data, SPECIES, "front", { kind = kind })
    U.log("path", kind, tostring(path))
  end

  -- CAS_DEXFRAMES=n: sit on the Pokedex entry and take n shots CAS_GAP frames
  -- apart, to see the picture animate.
  local dexFrames = tonumber(os.getenv("CAS_DEXFRAMES") or "0")
  if dexFrames > 0 then
    -- the route the Pokedex menu takes, so the stamped screenId is there
    local state = require("src.ui.Screens").push(game, "DexEntryMenu", SPECIES)
    U.log("dex screenId", tostring(state.screenId))
    -- the driver steps the game directly and skips the core.update hook the
    -- real loop goes through, so call it here the way love.update would
    local Runtime = require("src.mods.Runtime")
    local function step(n)
      for _ = 1, n do
        Runtime.call("core.update", function() end, game, 1 / 60)
        U.wait(1)
      end
    end
    step(60)
    for i = 1, dexFrames do
      U.shot(game, ("%s/dexanim_%s_%02d.png"):format(DIR, SPECIES, i))
      U.log("dexanim", i, tostring(state.sprite))
      step(tonumber(os.getenv("CAS_GAP") or "10"))
    end
    game.stack:pop()
    return
  end

  local mon = game.save.party[1]
  show("summary", function() return require("src.ui.SummaryMenu").new(game, mon) end, 120)
  show("dex", function()
    return require("src.ui.DexEntryMenu").new(game, { species = SPECIES, forceOwned = true }, function() end)
  end, 200)
  show("evolution", function()
    return require("src.ui.EvolutionState").new(game, mon, SPECIES, function() end, "LEVEL")
  end, 120)
  show("hof", function()
    game.save.hallOfFame = game.save.hallOfFame or {}
    return require("src.ui.HallOfFame").new(game, function() end)
  end, 240)
  show("oak", function() return require("src.ui.OakSpeech").new(game, function() end) end, 400)
  show("title", function() return require("src.ui.TitleState").new(game, {}) end, 300)
  U.log("done", SPECIES)
end
