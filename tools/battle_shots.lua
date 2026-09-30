-- Real-engine capture for Crystal Animated Sprites (dev tool, not a unit test).
-- Pushes a wild battle and screenshots the enemy across a full animation
-- cycle, plus the player's back slot.
--
--   cd C:/g2dev
--   POKEPORT_DRIVER=C:/Users/camwr/Desktop/Gen1Recomp/crystal-animated-sprites/tools/battle_shots.lua \
--     POKEPORT_IDENTITY=cas POKEPORT_TOUCH=0 CAS_SPECIES=PIKACHU \
--     SHOT_DIR=C:/Users/camwr/AppData/Local/Temp/cas/shots \
--     "C:/Program Files/LOVE/lovec.exe" .
--
-- The scratch identity must already hold a Red import and the mod must be
-- enabled (see the plan, Task 11).  Anything that is not a screenshot goes to
-- the driver log.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "C:/tmp/cas/shots"
  local SPECIES = os.getenv("CAS_SPECIES") or "PIKACHU"
  local SHOTS = tonumber(os.getenv("CAS_SHOTS") or "16")
  local GAP = tonumber(os.getenv("CAS_GAP") or "15")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  os.execute('mkdir "' .. DIR:gsub("/", "\\") .. '" 2>nul')

  game.save.party = { Pokemon.new(game.data, "BULBASAUR", 12) }
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  U.wait(10)
  local ow = game.overworld
  U.log(ow and "PASS" or "FAIL", "overworld is up")
  if not ow then return end

  local battle = BattleState.newWild(game, SPECIES, 10)
  battle.onFinish = function() end
  ow:pushBattle(battle)

  -- let the intro slide and the send-out finish before sampling
  for _ = 1, 600 do U.wait(1) end

  -- CAS_TAPS presses A that many times to get past the intro text so the
  -- player's own Pokemon is sent out and its back sprite is on screen.
  for _ = 1, tonumber(os.getenv("CAS_TAPS") or "0") do
    U.tap(game, "a")
    U.wait(60)
  end

  local enemy = battle.enemy
  U.log("enemy sprite image:", tostring(enemy and enemy.sprite))
  for i = 1, SHOTS do
    U.shot(game, ("%s/%s_%02d.png"):format(DIR, SPECIES, i))
    U.log("shot", i, U.frame())
    U.wait(GAP)
  end
  U.log("done", SPECIES)
end
