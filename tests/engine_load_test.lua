-- Engine integration.  Run from the engine checkout, not this repo:
--   cd C:/g2dev && luajit mods/crystal_animated_sprites/tests/engine_load_test.lua
-- Needs baseroms/crystal.gbc (git-ignored) in this mod's folder.  The engine
-- harness has no threads, so the decode result is produced here with the same
-- job script and written through the real cache class, then the mod is
-- loaded on top of it.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

-- The test love stub has no MD5.  The launcher has already validated the
-- import in the real game, so the stub just reports the expected digest.
love.data = love.data or {}
love.data.hash = love.data.hash or function() return "digest" end
love.data.encode = love.data.encode or function()
  return "301899b8087289a6436b0a241fbbb474"
end

local MOD = "mods/crystal_animated_sprites"
local ID = "crystal_animated_sprites"
local T = require("tests.modkit")
local S = require("tests.harness").suite("crystal animated sprites in the engine")
local check, eq = S.check, S.eq

local function readFile(path)
  local f = assert(io.open(path, "rb"), "missing " .. path)
  local s = f:read("*a")
  f:close()
  return s
end

local romBytes = readFile(MOD .. "/baseroms/crystal.gbc")

-- Load the mod's own libraries the way the tests and the job do.
local loaded = {}
local function need(name)
  if not loaded[name] then
    local chunk = assert(loadfile(MOD .. "/lib/" .. name .. ".lua"))
    loaded[name] = chunk(need)
  end
  return loaded[name]
end
local Rom, Cache = need("rom"), need("cache")

local function decodeBatch(first, last)
  local libs = {}
  for _, n in ipairs({ "lz", "rom", "addresses", "pic", "png", "anim", "palette", "icons", "specks", "specks_back", "edits" }) do
    libs[n] = readFile(MOD .. "/lib/" .. n .. ".lua")
  end
  local chunk = assert(loadfile(MOD .. "/jobs/decode.lua"))
  return chunk({ rom = romBytes, libs = libs, first = first, last = last })
end

-- The SDK hands mod.cache a filesystem whose writes land in a private
-- overlay, so a test that wants to pre-seed the cache supplies its own: real
-- files read through, writes and seeds kept in an overlay.
local FsIo = require("tests.fs_io")
local function makeFs()
  local inner = FsIo.new(".")
  local overlay = {}
  local loadstr = loadstring or load
  local fs = setmetatable({ root = inner.root, overlay = overlay }, { __index = inner })
  function fs.read(p)
    if overlay[p] ~= nil then return overlay[p] end
    return inner.read(p)
  end
  function fs.write(p, body) overlay[p] = body return true end
  function fs.load(p)
    if overlay[p] ~= nil then return loadstr(overlay[p], "@" .. p) end
    return inner.load(p)
  end
  function fs.getInfo(p)
    if p == "mods" then return { type = "directory" } end
    if overlay[p] ~= nil then return { type = "file", size = #overlay[p] } end
    return inner.getInfo(p)
  end
  function fs.getDirectoryItems(p)
    if p == "mods" then return { ID } end
    return inner.getDirectoryItems(p)
  end
  return fs
end

-- A cache over that filesystem at the path the engine gives mod.cache.
local function cacheStore(fs)
  local root = "mod_cache/" .. ID .. "/"
  return {
    write = function(key, bytes) return fs.write(root .. key, bytes) end,
    read = function(key) return fs.read(root .. key) end,
    info = function(key) return fs.getInfo(root .. key) end,
    delete = function() end,
  }
end

local function seed(fs, stamp, first, last)
  local cache = Cache.new(cacheStore(fs), stamp, ID)
  cache:begin()
  local r = decodeBatch(first, last)
  for dex, decoded in pairs(r.species) do assert(cache:put(dex, decoded)) end
  return cache
end

local realStamp = Cache.stamp(Rom.new(romBytes))

local function load(fs)
  local Data = require("tests.modkit.fixtures").fresh()
  local run = T.sdk.loadMod(MOD, { data = Data, fs = fs })
  return run, Data
end

local Sprites = require("src.pokemon.Sprites")
local function pathFor(Data, species, side, kind)
  return (Sprites.path(Data, species, side, { kind = kind or "battle" }))
end

-- 1. Species 3 (FIXMON_C in the fixture) is cached; 1 and 2 are not.
do
  local fs = makeFs()
  seed(fs, realStamp, 3, 3)
  local run, Data = load(fs)
  run.loader.modOptions[ID] = { sprite_colors = "game", back_sprites = "crystal" } -- this section checks the grey copies
  eq(run.mod and run.mod.state, "loaded", "the mod loads in the real loader")
  eq(#run.errors, 0, "no load errors")

  local prefix = "mod_cache/" .. ID .. "/" .. realStamp
  local front = pathFor(Data, "FIXMON_C", "front")
  check(front:find(prefix .. "/front/003/", 1, true) == 1,
    "a cached species serves a cached frame path (got " .. tostring(front) .. ")")
  eq(pathFor(Data, "FIXMON_C", "front"), prefix .. "/front/003/0.png",
    "a lookup the engine makes itself (battle start, Transform, ghost reveal) "
    .. "gets the resting frame, not whatever the clock says")
  eq(pathFor(Data, "FIXMON_C", "back"), prefix .. "/back/003.png",
    "back slot serves Crystal's back art when BACK SPRITES is CRYSTAL")
  eq(pathFor(Data, "FIXMON_A", "front"), "tests/fixture_data/assets/fixmon_a_front.png",
    "an uncached species keeps the engine's art")
  for _, kind in ipairs({ "summary", "dex", "evolution", "hof", "trade", "title",
                          "oak", "credits", "box", "hatch", "photo", "overworld" }) do
    eq(pathFor(Data, "FIXMON_C", "front", kind), prefix .. "/front/003/0.png",
      kind .. " screen serves the resting Crystal frame")
  end
  -- a screen with its own clock (Bill's PC Plus' panel) asks Sprites.pic with
  -- ctx.seconds and gets the frame for that moment
  local function at(species, kind, seconds)
    local def = Data.pokemon[species]
    return (Sprites.pic(def.spriteFront, { species = species, side = "front",
      kind = kind, data = Data, seconds = seconds }))
  end
  check(at("FIXMON_C", "summary", 0):find(prefix .. "/front/003/", 1, true) == 1,
    "a summary lookup with a clock serves a cached frame of the species")
  local moved
  for s = 0.05, 6, 0.05 do
    if at("FIXMON_C", "summary", s) ~= prefix .. "/front/003/0.png" then moved = true break end
  end
  check(moved, "a summary lookup with a clock reaches a frame other than the resting one")
  eq(at("FIXMON_C", "dex", 1.0), prefix .. "/front/003/0.png",
    "only the summary kind takes a clock; other screens stay on the resting frame")
  eq(at("FIXMON_A", "summary", 1.0), "tests/fixture_data/assets/fixmon_a_front.png",
    "an uncached species keeps the engine's art with a clock too")
  eq(pathFor(Data, "FIXMON_A", "front", "summary"), "tests/fixture_data/assets/fixmon_a_front.png",
    "an uncached species keeps the engine's art on other screens too")
  eq(pathFor(Data, "FIXMON_C", "front", "online"), "tests/fixture_data/assets/fixmon_c_front.png",
    "other players' sprites in online play are left alone")
  eq(pathFor(Data, "FIXMON_C", "back", "hof"), "tests/fixture_data/assets/fixmon_c_back.png",
    "back pics outside battle keep the engine's art, their layout is not Crystal's size")
  check(Data.battle_sprite_scales.cas_b003 ~= nil
    and Data.battle_sprite_scales.cas_b003.scale == 1,
    "the back pic is registered at 1x")
  check(Data.battle_sprite_scales.cas_f003_0m ~= nil,
    "the mirrored resting frame is registered at 1x")
  check(require("src.mods.Runtime").wantsHook("core.update"),
    "decode results are collected every frame, not only inside a battle")
  check(require("src.ui.PartyMenu").__casDrawIcon ~= nil,
    "the party menu icon wrapper is installed")
  run.release()
end

-- 4. SPRITE COLORS = CRYSTAL serves the colour copies and marks them true colour,
--    which is how the engine is told to leave them out of its own palettes.
do
  local fs = makeFs()
  seed(fs, realStamp, 3, 3)
  local run, Data = load(fs)
  local prefix = "mod_cache/" .. ID .. "/" .. realStamp
  local function lookup(species, side, kind)
    local path, trueColor = Sprites.path(Data, species, side, { kind = kind or "battle" })
    return path, trueColor
  end
  -- no option set: Crystal colours are the default
  local path, tc = lookup("FIXMON_C", "front")
  eq(path, prefix .. "/front/003/0c.png", "by default the colour frame is served")
  eq(tc, true, "and flagged true colour")
  path = lookup("FIXMON_C", "back")
  eq(path, prefix .. "/front/003/0mc.png", "by default the back slot shows the mirrored animated front")

  run.loader.modOptions[ID] = { sprite_colors = "game" }
  path, tc = lookup("FIXMON_C", "front")
  eq(path, prefix .. "/front/003/0.png", "GAME colours serve the grey frame")
  eq(tc, false, "and are not flagged true colour")

  run.loader.modOptions[ID] = { sprite_colors = "crystal", back_sprites = "crystal" }
  path, tc = lookup("FIXMON_C", "front")
  eq(path, prefix .. "/front/003/0c.png", "CRYSTAL colours serve the colour frame")
  eq(tc, true, "and flag it true colour")
  path, tc = lookup("FIXMON_C", "back")
  eq(path, prefix .. "/back/003c.png", "the back sprite follows")
  eq(tc, true, "and is flagged too")
  path, tc = lookup("FIXMON_C", "front", "summary")
  eq(path, prefix .. "/front/003/0c.png", "other screens follow")
  eq(tc, true, "and are flagged too")
  path, tc = lookup("FIXMON_C", "front", "title")
  eq(path, prefix .. "/front/003/0c.png", "the title screen follows the setting too")
  eq(tc, true, "and is flagged true colour")
  path = lookup("FIXMON_A", "front")
  eq(path, "tests/fixture_data/assets/fixmon_a_front.png", "an uncached species still keeps the engine's art")

  run.loader.modOptions[ID] = { sprite_colors = "crystal", back_sprites = "front" }
  path, tc = lookup("FIXMON_C", "back")
  eq(path, prefix .. "/front/003/0mc.png", "ANIMATED FRONT back sprites are mirrored colour frames")
  eq(tc, true, "and flagged")

  check(Data.battle_sprite_scales.cas_b003c ~= nil and Data.battle_sprite_scales.cas_b003c.scale == 1,
    "the colour back pic is registered at 1x")
  check(Data.battle_sprite_scales.cas_f003_0c ~= nil, "the colour resting frame is registered at 1x")
  check(Data.battle_sprite_scales.cas_f003_0mc ~= nil, "the mirrored colour frame is registered at 1x")

  run.loader.modOptions[ID] = { sprite_colors = "game" }
  path, tc = lookup("FIXMON_C", "front")
  eq(path, prefix .. "/front/003/0.png", "switching back to GAME serves grey again")
  eq(tc, false, "unflagged")
  run.release()
end

-- 4b. A shiny Pokemon is the same picture in Crystal's shiny colours.  The hook
--     sees the mon, so a shiny gets the shiny copy and everyone else, and every
--     lookup with no mon at all (the Pokedex, the title), keeps the normal one.
do
  local fs = makeFs()
  seed(fs, realStamp, 3, 3)
  local run, Data = load(fs)
  local prefix = "mod_cache/" .. ID .. "/" .. realStamp
  local function lookup(species, side, kind, mon)
    local path, trueColor = Sprites.path(Data, species, side, { kind = kind or "battle", mon = mon })
    return path, trueColor
  end
  local SHINY_DVS = { attack = 15, defense = 10, speed = 10, special = 10 }
  local PLAIN_DVS = { attack = 8, defense = 8, speed = 8, special = 8 }

  run.loader.modOptions[ID] = { sprite_colors = "crystal", back_sprites = "crystal" }
  local path, tc = lookup("FIXMON_C", "front", "battle", { shiny = true })
  eq(path, prefix .. "/front/003/0cs.png", "a mon flagged shiny gets the shiny frame")
  eq(tc, true, "and it is flagged true colour")
  path = lookup("FIXMON_C", "front", "battle", { dvs = SHINY_DVS })
  eq(path, prefix .. "/front/003/0cs.png", "shiny DVs count as shiny, the way the shiny mods test it")
  path = lookup("FIXMON_C", "front", "battle", { dvs = PLAIN_DVS })
  eq(path, prefix .. "/front/003/0c.png", "a plain mon keeps the normal colours")
  path = lookup("FIXMON_C", "front", "battle", nil)
  eq(path, prefix .. "/front/003/0c.png", "a lookup with no mon keeps the normal colours")
  path = lookup("FIXMON_C", "front", "dex", nil)
  eq(path, prefix .. "/front/003/0c.png", "the Pokedex shows the species, never a shiny")

  path, tc = lookup("FIXMON_C", "back", "battle", { shiny = true })
  eq(path, prefix .. "/back/003cs.png", "the back sprite follows for a shiny")
  eq(tc, true, "and is flagged too")
  path = lookup("FIXMON_C", "front", "summary", { shiny = true })
  eq(path, prefix .. "/front/003/0cs.png", "the summary and other still screens follow")

  run.loader.modOptions[ID] = { sprite_colors = "crystal", back_sprites = "front" }
  path, tc = lookup("FIXMON_C", "back", "battle", { shiny = true })
  eq(path, prefix .. "/front/003/0mcs.png", "ANIMATED FRONT back sprites are mirrored shiny frames")
  eq(tc, true, "and flagged")

  run.loader.modOptions[ID] = { sprite_colors = "game" }
  path, tc = lookup("FIXMON_C", "front", "battle", { shiny = true })
  eq(path, prefix .. "/front/003/0.png", "GAME colours serve the grey frame even for a shiny")
  eq(tc, false, "and are not flagged true colour")

  check(Data.battle_sprite_scales.cas_b003cs ~= nil and Data.battle_sprite_scales.cas_b003cs.scale == 1,
    "the shiny back pic is registered at 1x")
  check(Data.battle_sprite_scales.cas_f003_0cs ~= nil, "the shiny resting frame is registered at 1x")
  check(Data.battle_sprite_scales.cas_f003_0mcs ~= nil, "the mirrored shiny frame is registered at 1x")
  run.release()
end

-- 2. A cache left by a different ROM dump is ignored, never served.
do
  local fs = makeFs()
  local staleFirst = seed(fs, "f1-0000-00", 1, 1)
  local run, Data = load(fs)
  eq(run.mod and run.mod.state, "loaded", "loads with a stale cache present")
  eq(pathFor(Data, "FIXMON_A", "front"), "tests/fixture_data/assets/fixmon_a_front.png",
    "a stale-stamp cache is not served")
  check(staleFirst:meta(1) ~= nil, "(the stale cache itself was written)")
  run.release()
end

-- 3. A meta file whose PNGs were deleted must not be served: the engine would
--    raise trying to load a path that is not there.
do
  local fs = makeFs()
  seed(fs, realStamp, 3, 3)
  fs.overlay["mod_cache/" .. ID .. "/" .. realStamp .. "/back/003.png"] = nil
  local run, Data = load(fs)
  eq(run.mod and run.mod.state, "loaded", "loads with a damaged cache present")
  eq(pathFor(Data, "FIXMON_C", "front"), "tests/fixture_data/assets/fixmon_c_front.png",
    "a species with a missing file keeps the engine's art (front)")
  eq(pathFor(Data, "FIXMON_C", "back"), "tests/fixture_data/assets/fixmon_c_back.png",
    "a species with a missing file keeps the engine's art (back)")
  run.release()
end

-- 5. The shiny entrance: its option, Crystal's chime as the engine's own chip
--    program, and the wrapper on the engine's entrance cry.  Last, because the
--    wrapper stays on BattleState once the mod has loaded.
do
  local BattleState = require("src.battle.BattleState")
  local realCry = BattleState.playEntranceCry
  local played = {}
  -- stands in for the engine's cry, which needs audio
  BattleState.playEntranceCry = function(_, battler) played[#played + 1] = battler return "the cry" end
  local fs = makeFs()
  seed(fs, realStamp, 3, 3)
  local run, Data = load(fs)
  eq(#run.errors, 0, "no load errors with the entrance")

  local row
  for _, r in ipairs(run.loader.optionSchemas[ID] or {}) do
    if r.key == "shiny_entrance" then row = r end
  end
  check(row ~= nil, "the mod defines a shiny_entrance option")
  eq(row and row.label, "SHINY ENTRANCE", "labelled SHINY ENTRANCE")
  eq(row and row.default, "on", "on by default")

  local chime = Data.audio and Data.audio.sfx and Data.audio.sfx.CAS_SHINE
  check(chime ~= nil, "Crystal's chime is registered with the engine")
  eq(chime and chime.generation, 2, "as a Gen 2 program, so the Red engine decodes it with the right commands")
  eq(chime and chime.chip and chime.chip.engine, 2)
  eq(chime and chime.chip and #chime.chip.blob, 27, "the 27 bytes the ROM holds")
  eq(chime and chime.chip and chime.chip.channels[1].number, 5, "on sound channel 5")
  eq(chime and chime.chip and chime.chip.channels[1].address, 0x4000, "at the start of its own program")
  eq(chime and chime.chip and chime.chip.blob:byte(1), 0xDB, "starting with the duty cycle command")

  local queue = {}
  local battle = {
    waitSfxNext = function(_, src) queue[#queue + 1] = { wait = src } end,
    actNext = function(_, fn) queue[#queue + 1] = { act = fn } end,
  }
  local shiny = { mon = { species = "FIXMON_C", shiny = true } }
  eq(BattleState.playEntranceCry(battle, shiny), nil, "a shiny's cry is not played at once")
  eq(#played, 0, "the engine's cry has not run")
  eq(#queue, 2, "it queues a wait for the sparkle, then the cry")
  queue[2].act()
  eq(#played, 1, "and the cry plays when its turn comes")
  eq(played[1], shiny, "for the same Pokemon")
  eq(queue[3] and queue[3].wait, "the cry", "with the queue waiting on it")

  queue = {}
  local plain = { mon = { species = "FIXMON_C" } }
  eq(BattleState.playEntranceCry(battle, plain), "the cry", "a plain Pokemon's cry goes straight through")
  eq(#queue, 0, "with nothing queued")

  run.loader.modOptions[ID] = { shiny_entrance = "off" }
  eq(BattleState.playEntranceCry(battle, shiny), "the cry", "OFF lets a shiny enter like any other")
  eq(#queue, 0)

  -- nothing is held when the options bag is empty again
  run.loader.modOptions[ID] = nil
  run.release()
  BattleState.playEntranceCry = realCry
end

S.finish()
