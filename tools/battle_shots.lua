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

  -- CAS_PLAYER picks the player's Pokemon, so its back sprite can be checked.
  game.save.party = { Pokemon.new(game.data, os.getenv("CAS_PLAYER") or "BULBASAUR", 12) }
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  U.wait(10)
  local ow = game.overworld
  U.log(ow and "PASS" or "FAIL", "overworld is up")
  if not ow then return end

  -- CAS_BG=world lets the overworld show behind the battle, which is what a
  -- mod that replaces the backdrop looks like to a sprite: any opaque pixel
  -- in the pic shows up against it.  Set in memory because the ruleset can
  -- override the saved option.
  if os.getenv("CAS_BG") then game.save.options.battleBg = os.getenv("CAS_BG") end

  -- CAS_DIAG=1 turns the DIAGNOSTICS readout on for this run (and back off
  -- after), so it can be photographed.
  local diag = os.getenv("CAS_DIAG")
  if diag then
    require("src.mods.LauncherMods").setModOptions("crystal_animated_sprites", { diagnostics = "on" })
    game.save.options.modOptions = game.save.options.modOptions or {}
    game.save.options.modOptions.crystal_animated_sprites =
      game.save.options.modOptions.crystal_animated_sprites or {}
    game.save.options.modOptions.crystal_animated_sprites.diagnostics = "on"
  end

  -- CAS_FIELD=gray|dark repaints the battle field (the white 160x144 fill),
  -- standing in for a mod that replaces the backdrop.  Any opaque white in a
  -- sprite then shows up as a rectangle around it.
  local FIELDS = { gray = 0.6, dark = 0.1 }
  local field = FIELDS[os.getenv("CAS_FIELD") or ""]
  if field then
    local g = love.graphics
    local realRect = g.rectangle
    g.rectangle = function(mode, x, y, w, h, ...)
      if mode == "fill" and x == 0 and y == 0 and w == 160 and h == 144
         and select(1, g.getColor()) == 1 then
        g.setColor(field, field, field, 1)
        realRect(mode, x, y, w, h, ...)
        g.setColor(1, 1, 1, 1)
        return
      end
      return realRect(mode, x, y, w, h, ...)
    end
  end

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
  U.log("bgMode", battle:bgMode(), "isOpaque", tostring(battle.isOpaque), "battleBg option", tostring(game.save.options and game.save.options.battleBg))
  for i = 1, SHOTS do
    U.shot(game, ("%s/%s_%02d.png"):format(DIR, SPECIES, i))
    U.log("shot", i, U.frame())
    U.wait(GAP)
  end
  U.log("done", SPECIES)
end
