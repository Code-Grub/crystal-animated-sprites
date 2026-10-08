-- Crystal's animated front sprites in Red, Blue and Yellow, decoded from the
-- player's own Crystal ROM.  See docs/superpowers/specs/.
--
-- The pieces: a background job decodes the ROM once into PNG frames under
-- mod_cache/<id>/ (lib/cache.lua), the pokemon.sprite hook serves the frame
-- paths, and battle.overlay swaps each battler's sprite image as the animation
-- advances (lib/swap.lua).  Anything not cached yet keeps the engine's art.
return function(mod)
  local MOD_ID = "crystal_animated_sprites"
  local LAST = 151
  local MAX_JOBS = 2
  local ALL_LIBS = { "lz", "rom", "addresses", "pic", "png", "anim", "cache", "sparkle", "entrance", "shinyintro",
                     "playback", "swap", "attack", "ingest", "status", "screenanim", "palette", "icons", "iconshim", "titlemask", "specks", "specks_back", "edits" }
  local JOB_LIBS = { "lz", "rom", "addresses", "pic", "png", "anim", "palette", "icons", "specks", "specks_back", "edits" }

  -- A mod cannot require its own files: siblings load through mod:read +
  -- load, and each lib chunk receives `need` to reach the others.
  local sources = {}
  for _, name in ipairs(ALL_LIBS) do
    local source = mod:read("lib/" .. name .. ".lua")
    if not source then
      mod.log:error("lib/%s.lua missing from %s -- reinstall the mod", name, mod.path)
      return
    end
    sources[name] = source
  end
  local loaded = {}
  local function need(name)
    if not loaded[name] then
      local chunk, err = load(sources[name], "@" .. mod.path .. "/lib/" .. name .. ".lua")
      if not chunk then error(err) end
      loaded[name] = chunk(need)
    end
    return loaded[name]
  end
  local Rom, Anim, Cache = need("rom"), need("anim"), need("cache")
  local Playback, Swap, Ingest = need("playback"), need("swap"), need("ingest")
  local Attack = need("attack")
  local Status = need("status")
  local ScreenAnim = need("screenanim")
  local IconShim = need("iconshim")
  local TitleMask = need("titlemask")

  local romBytes, readErr = mod.imports:read("crystal_rom", 0, 2097152)
  if not romBytes then
    mod.log:error("could not read the Crystal import: %s", tostring(readErr))
    return
  end
  local rom = Rom.new(romBytes)

  -- mod.cache is colon-called; Cache wants plain functions.
  local store = {
    write = function(key, bytes) return mod.cache:write(key, bytes) end,
    read = function(key) return mod.cache:read(key) end,
    info = function(key) return mod.cache:info(key) end,
    delete = function(key) return mod.cache:delete(key) end,
  }
  local cache = Cache.new(store, Cache.stamp(rom), MOD_ID)
  if not cache:valid() then cache:begin() end

  local warned = {}
  local lastErr -- newest problem, shown by the DIAGNOSTICS readout
  local function warnOnce(key, fmt, ...)
    if warned[key] then return end
    warned[key] = true
    lastErr = fmt:format(...)
    mod.log:warn(fmt, ...)
  end

  ---------------------------------------------------------------------------
  -- Options
  ---------------------------------------------------------------------------
  local rowsSource = mod:read("options.lua")
  local rowsChunk = rowsSource and load(rowsSource, "@" .. mod.path .. "/options.lua")
  if rowsChunk then mod.options:define(rowsChunk()) end

  ---------------------------------------------------------------------------
  -- Sprite scales.  Crystal's back pics are 48px native and the engine draws a
  -- back pic at 2x unless told otherwise, so every path we can serve is
  -- registered at 1x.  The registry freezes after load, so this happens here.
  ---------------------------------------------------------------------------
  local scales = mod.content and mod.content.battle_sprite_scales
  local function registerScale(id, path)
    if scales then scales:register(id, { path = path, scale = 1 }) end
  end
  for dex = 1, LAST do
    local ok, err = pcall(function()
      registerScale(("cas_b%03d"):format(dex), cache:backPath(dex))
      registerScale(("cas_b%03dc"):format(dex), cache:backPath(dex, true))
      registerScale(("cas_b%03dcs"):format(dex), cache:backPath(dex, true, true))
      local seen = {}
      local function frame(index)
        if seen[index] then return end
        seen[index] = true
        registerScale(("cas_f%03d_%d"):format(dex, index), cache:framePath(dex, index))
        registerScale(("cas_f%03d_%dm"):format(dex, index), cache:framePath(dex, index, true))
        registerScale(("cas_f%03d_%dc"):format(dex, index), cache:framePath(dex, index, false, true))
        registerScale(("cas_f%03d_%dmc"):format(dex, index), cache:framePath(dex, index, true, true))
        registerScale(("cas_f%03d_%dcs"):format(dex, index), cache:framePath(dex, index, false, true, true))
        registerScale(("cas_f%03d_%dmcs"):format(dex, index), cache:framePath(dex, index, true, true, true))
      end
      frame(0)
      for _, step in ipairs(Anim.timeline(Anim.script(rom, dex))) do frame(step.frame) end
    end)
    if not ok then warnOnce("scale" .. dex, "species %d: no sprite scale registered: %s", dex, tostring(err)) end
  end

  ---------------------------------------------------------------------------
  -- Decode.  At most MAX_JOBS run at once, each over a contiguous range.
  -- Nothing here blocks: poll runs from the sprite hook and the battle
  -- overlay, so finished work is cached before the next battle draws.
  ---------------------------------------------------------------------------
  -- ready[dex]: every file for that species is on disk and servable.  Only
  -- the complete check (not the meta file alone) makes a species ready, so a
  -- partly deleted cache is re-decoded instead of handed to the engine.
  local failed, pending, running, ready = {}, {}, {}, {}
  local INGEST_BUDGET = 4 -- species written per poll; see lib/ingest.lua
  local ingest = Ingest.new(cache, {
    onPut = function(dex) ready[dex] = true end,
    onFail = function(dex, err)
      failed[dex] = true
      warnOnce("cachewrite", "cache write failed at species %d: %s", dex, err)
    end,
  })

  do
    local first, last
    for dex = 1, LAST do
      if cache:complete(dex) then
        ready[dex] = true
      else
        first = first or dex
        last = dex
      end
    end
    if first then
      local mid = math.floor((first + last) / 2)
      if mid > first and MAX_JOBS > 1 then
        pending[1] = { first = first, last = mid }
        pending[2] = { first = mid + 1, last = last }
      else
        pending[1] = { first = first, last = last }
      end
    end
  end

  local jobLibs = {}
  for _, name in ipairs(JOB_LIBS) do jobLibs[name] = sources[name] end

  local function startJobs()
    if #pending == 0 or not (mod.job and mod.job:available()) then return end
    while #pending > 0 and #running < MAX_JOBS do
      local range = table.remove(pending, 1)
      local handle, reason = mod.job:run("jobs/decode.lua",
        { rom = romBytes, libs = jobLibs, first = range.first, last = range.last },
        { maxSeconds = 30 })
      if not handle then
        table.insert(pending, 1, range)
        warnOnce("jobstart", "decode job not started: %s", tostring(reason))
        return
      end
      running[#running + 1] = { handle = handle, first = range.first, last = range.last }
    end
  end

  local function consume(job, result)
    if result.status ~= "ok" then
      mod.log:error("decode of species %d-%d failed: %s", job.first, job.last, tostring(result.err))
      lastErr = ("decode %d-%d: %s"):format(job.first, job.last, tostring(result.err))
      for dex = job.first, job.last do failed[dex] = true end
      return
    end
    for dex, message in pairs(result.result.errors) do
      failed[dex] = true
      mod.log:warn("species %d not decoded: %s", dex, tostring(message))
      lastErr = ("species %d: %s"):format(dex, tostring(message))
    end
    ingest:enqueue(result.result.species)
  end

  local function pollJobs()
    startJobs()
    for i = #running, 1, -1 do
      local job = running[i]
      local result = mod.job:poll(job.handle)
      if result.status ~= "pending" then
        table.remove(running, i)
        mod.job:release(job.handle)
        consume(job, result)
      end
    end
    ingest:step(INGEST_BUDGET)
  end

  pollJobs()

  ---------------------------------------------------------------------------
  -- Serving frames
  ---------------------------------------------------------------------------
  -- The time since the pic landed that a swap is rebuilding for.  It is nil
  -- outside a swap, and for a pic that has not landed, so a lookup the engine
  -- makes on its own (battle start, Transform, the ghost reveal) gets the
  -- resting frame instead of a mid-animation one.
  local frozen

  local function dexOf(data, species)
    local def = data and data.pokemon and data.pokemon[species]
    local dex = def and tonumber(def.dex)
    if dex and dex >= 1 and dex <= LAST then return dex end
    return nil
  end

  -- Crystal has no shiny art: a shiny is the same picture in the species'
  -- second pair of colours, which the decode job paints into its own copies.
  -- The test is the one the shiny mods use, the flag or DVs that read as
  -- shiny, so all of them agree on who is.  A lookup with no mon at all (the
  -- Pokedex, the title) is never shiny.
  local Stats
  local function isShiny(mon)
    if type(mon) ~= "table" then return false end
    if mon.shiny then return true end
    Stats = Stats or require("src.pokemon.Stats")
    return Stats.isShiny(mon.dvs) and true or false
  end

  -- Returns the path to serve and whether it is the Crystal-colour copy.  The
  -- engine is told about the second through ctx.trueColor, which is how it
  -- knows to leave a picture out of its own palettes.  shiny picks the copy in
  -- the shiny colours, and only means anything alongside Crystal colours: the
  -- grey frames are coloured by the engine's own palettes, which have no shiny.
  local function resolve(dex, side, seconds, shiny)
    local meta = ready[dex] and not failed[dex] and cache:meta(dex)
    if not meta then return nil end
    local color = meta.colors and mod.options:get("sprite_colors") == "crystal"
    local painted = color and shiny and meta.shiny
    if side == "back" then
      if mod.options:get("back_sprites") == "front" then
        return cache:framePath(dex, Playback.frameAt(meta.timeline, seconds), true, color, painted), color
      end
      return cache:backPath(dex, color, painted), color
    end
    return cache:framePath(dex, Playback.frameAt(meta.timeline, seconds), false, color, painted), color
  end

  ---------------------------------------------------------------------------
  -- Shiny entrance (lib/entrance.lua, lib/sparkle.lua).  Crystal plays a ring of
  -- sparkles with a chime when a shiny takes the field, and only then the cry and
  -- the front animation.  The art and the chime come from the player's ROM; if
  -- either is not where Crystal v1.0/v1.1 put it, there is no entrance and the
  -- mod behaves as it did before.
  ---------------------------------------------------------------------------
  local Sparkle, Entrance = need("sparkle"), need("entrance")
  local sparkleSprites
  do
    local tiles, why = Sparkle.tiles(rom)
    if tiles then
      sparkleSprites = Sparkle.sprites(tiles)
    else
      warnOnce("sparkleart", "no shiny entrance: %s", tostring(why))
    end
  end

  -- Crystal's SFX_SHINE, as the 27 bytes the ROM holds, played by the engine's own
  -- chip player: a Gen 2 program on sound channel 5.  Registered now because the
  -- registry freezes after load.
  local CHIME = "CAS_SHINE"
  do
    local bytes = Sparkle.chime(rom)
    if bytes and mod.content and mod.content.sfx then
      local ok, err = pcall(function()
        mod.content.sfx:register(CHIME, {
          generation = 2,
          chip = { blob = bytes, channels = { { number = 5, address = 0x4000 } }, engine = 2 },
        })
      end)
      if not ok then
        warnOnce("sparklechime", "shiny chime not registered: %s", tostring(err))
      end
    end
  end

  local function nowSeconds() return (love and love.timer) and love.timer.getTime() or 0 end
  local entrance = Entrance.new({
    now = nowSeconds,
    enabled = function()
      return sparkleSprites ~= nil and mod.options:get("shiny_entrance") ~= "off"
    end,
    isShiny = isShiny,
  })

  -- The three pictures as images, built on first use: they need a graphics
  -- context, which the mod load does not have.  PAL_BATTLE_OB_YELLOW: shade 1 is
  -- yellow, 2 orange, 3 black; 0 is see-through.
  local SPARKLE_RGB = { [1] = { 255, 255, 57 }, [2] = { 255, 132, 8 }, [3] = { 0, 0, 0 } }
  local SPARKLE_PICTURE = { [74] = "star", [14] = "large", [15] = "small" }
  local sparkleImages = {}
  local function sparkleImage(name)
    local image = sparkleImages[name]
    if image then return image end
    local sprite = sparkleSprites[name]
    local data = love.image.newImageData(sprite.w, sprite.h)
    for y = 0, sprite.h - 1 do
      for x = 0, sprite.w - 1 do
        local c = SPARKLE_RGB[sprite.pixels[y * sprite.w + x + 1]]
        if c then data:setPixel(x, y, c[1] / 255, c[2] / 255, c[3] / 255, 1)
        else data:setPixel(x, y, 0, 0, 0, 0) end
      end
    end
    image = love.graphics.newImage(data)
    image:setFilter("nearest", "nearest")
    sparkleImages[name] = image
    return image
  end

  -- Where the ring goes: the centre of the picture the battler is showing, where
  -- the engine puts it (Sparkle.anchor).  The wide layout composites each side
  -- into its own region, so it uses the spots SHINY_POKEMON uses for the same thing.
  local function sparkleAnchor(screen, battler, isEnemy)
    if screen.wide or (screen.wideLayout and screen:wideLayout()) then
      if isEnemy then return 200, 40 end
      return 60, 100
    end
    local image = battler.sprite
    if image and screen.picImage then
      local ok, shown = pcall(screen.picImage, screen, image)
      if ok and shown then image = shown end
    end
    if type(image) == "userdata" and image.getDimensions then
      return Sparkle.anchor(isEnemy, image:getDimensions())
    end
    return Sparkle.anchor(isEnemy)
  end

  local function drawEntrance(screen, battler, isEnemy)
    if not battler then return end
    local list = entrance:sparkles(battler)
    if #list == 0 then return end
    if entrance:chimesDue(battler) > 0 then
      local game = screen.game
      local data = (game and game.data) or screen.data
      if data then pcall(require("src.core.Sound").play, data, CHIME) end
    end
    local ax, ay = sparkleAnchor(screen, battler, isEnemy)
    local PaletteFX = require("src.render.PaletteFX")
    for _, s in ipairs(list) do
      local image = sparkleImage(SPARKLE_PICTURE[s.id])
      local w, h = image:getDimensions()
      local x, y = math.floor(ax + s.dx - w / 2), math.floor(ay + s.dy - h / 2)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(image, x, y)
      -- full colour, so the game's own palettes leave it alone
      if PaletteFX.markTrueColor then PaletteFX.markTrueColor(x, y, w, h) end
    end
  end

  -- The engine asks for the entrance cry as a Pokemon takes the field, which is
  -- where Crystal plays the sparkle; wrap it so a shiny's cry waits until the
  -- sparkle is over.  A failure here must never lose the cry.
  do
    local BS = require("src.battle.BattleState")
    local originalCry = BS.playEntranceCry
    if originalCry then
      BS.playEntranceCry = function(self, battler)
        local ok, held = pcall(entrance.holdCry, entrance, self, battler, originalCry)
        if ok then return held end
        warnOnce("entrancecry", "shiny entrance failed, playing the cry as usual: %s", tostring(held))
        return originalCry(self, battler)
      end
    end
  end

  -- SHINY_POKEMON draws its own sparkle and plays its own chime when a shiny
  -- appears.  While this entrance is on its intro is held off, and given back if
  -- this entrance is turned off (lib/shinyintro.lua).  Nothing is saved.
  local shinyIntro = need("shinyintro").new("SHINY_POKEMON", "sparkles")
  local function syncShinyIntro(game)
    shinyIntro:sync(game and game.mods,
      sparkleSprites ~= nil and mod.options:get("shiny_entrance") ~= "off")
  end

  -- Screens that show a Pokemon without a battle (summary, Pokedex, evolution,
  -- Hall of Fame, the intro and so on) get the resting Crystal frame.  Only
  -- fronts: Crystal's back art is a different size from the engine's, and
  -- those screens lay their back pics out for the engine's.  Other players'
  -- sprites in online play are left alone.
  local STILL_KINDS = { summary = true, dex = true, evolution = true, hof = true,
    trade = true, title = true, oak = true, credits = true, box = true,
    hatch = true, photo = true, overworld = true }

  mod.hooks:wrap("pokemon.sprite", function(next, originalPath, ctx)
    if not ctx then return next(originalPath, ctx) end
    if ctx.kind == "battle" then
      pollJobs()
      local dex = dexOf(ctx.data, ctx.species)
      local path, color
      if dex then path, color = resolve(dex, ctx.side, frozen, isShiny(ctx.mon)) end
      if path then
        if color then ctx.trueColor = true end
        return path
      end
      return next(originalPath, ctx)
    end
    if STILL_KINDS[ctx.kind] and ctx.side == "front" then
      pollJobs()
      local dex = dexOf(ctx.data, ctx.species)
      local path, color
      -- A screen that keeps its own clock (Bill's PC Plus' side panel) says how
      -- long the picture has been up and gets that moment of the animation;
      -- everyone else gets the resting frame.
      local seconds = ctx.kind == "summary" and tonumber(ctx.seconds) or nil
      if dex then path, color = resolve(dex, "front", seconds, isShiny(ctx.mon)) end
      if path then
        if color then ctx.trueColor = true end
        return path
      end
    end
    return next(originalPath, ctx)
  end, 930)

  local BattleState
  local swap = Swap.new({
    dexOf = function(screen, battler) return dexOf(screen.data, battler.mon.species) end,
    busy = function(screen, battler)
      if screen.ghost or screen.ghostReal or battler.fainted then return true end
      return screen.fxFaintActive and screen:fxFaintActive(battler) or false
    end,
    -- Crystal plays the animation once, as the pic appears with the cry.  The
    -- pic is on show once the intro slide and any send-out grow-in are over,
    -- the same conditions the engine draws it under.  Our own back slot has no
    -- send-out of its own to watch, so it starts once the intro text is done.
    landed = function(screen, battler)
      if (screen.introSlide or 0) > 0 then return false end
      if screen.growInScale and screen:growInScale(battler) then return false end
      local shown
      if battler.isPlayer then
        shown = screen.phase ~= "intro" and screen.phase ~= "messages"
      else
        shown = not (screen.showEnemyTrainer or screen.enemySendingOut or screen.enemyHidden)
      end
      -- a shiny's animation, like its cry, waits for its sparkle
      return shown and entrance:released(battler)
    end,
    pathFor = function(dex, side, seconds, mon)
      return resolve(dex, side, seconds, isShiny(mon))
    end,
    rebuild = function(screen, battler, _, seconds)
      BattleState = BattleState or require("src.battle.BattleState")
      -- makeBattler is pure and resolves the sprite through the engine's own
      -- palette pipeline, which calls the hook above for the frozen time.
      frozen = seconds
      local ok, fresh = pcall(BattleState.makeBattler, screen.data, battler.mon,
        battler.isPlayer and true or false, nil)
      frozen = nil
      return ok and fresh and fresh.sprite or nil
    end,
  })

  -- The Pokedex entry and the stats screen load their picture once, so they
  -- are animated by swapping the image they draw.  Images are kept by path: a
  -- species has a handful of frames and the screen loops over them.
  --
  -- The screens are recognised by the id the engine stamps on every screen it
  -- builds, not by their class, so a UI mod that wraps or replaces one through
  -- the screen registry still counts as long as it draws screen.sprite.
  local ANIMATED = { DexEntryMenu = "DEX", SummaryMenu = "SUM" }
  local function speciesOf(screen)
    if screen.screenId == "SummaryMenu" then return screen.mon and screen.mon.species end
    return screen.species
  end

  local screenImages = {}
  local screenAnim = ScreenAnim.new({
    pathFor = function(screen, seconds)
      local dex = dexOf(screen.game and screen.game.data, speciesOf(screen))
      -- the stats screen shows one Pokemon, so it knows if it is shiny; the
      -- Pokedex entry shows a species and never is
      local mon = screen.screenId == "SummaryMenu" and screen.mon or nil
      return dex and (resolve(dex, "front", seconds, isShiny(mon))) or nil
    end,
    load = function(path)
      local image = screenImages[path]
      if image then return image end
      local ok, loaded = pcall(love.graphics.newImage, path)
      if ok and loaded then
        screenImages[path] = loaded
        return loaded
      end
      return nil
    end,
  })

  -- the newest distinct screen ids on top of the stack, for the readout
  local recentScreens, dexNote = {}, nil
  local function noteScreen(top)
    local id = top and top.screenId
    if not id or recentScreens[1] == id then return end
    table.insert(recentScreens, 1, id)
    recentScreens[4] = nil
  end

  local function tickScreens(game)
    local top = game and game.stack and game.stack:top()
    noteScreen(top)
    local tag = top and ANIMATED[top.screenId]
    if tag and not (speciesOf(top) and top.sprite) then
      -- shown in the DIAGNOSTICS readout, which phones can read
      warnOnce("shape" .. tag, "%s screen: species=%s sprite=%s", tag,
        tostring(speciesOf(top)), tostring(top.sprite))
      tag = nil
    end
    if not tag then top = nil end
    screenAnim:tick(top, (love and love.timer) and love.timer.getTime() or 0)
    if top then
      dexNote = tag .. " " .. (top.sprite and "ON" or "NO IMG") .. " " .. (screenAnim.shown and "SHOWN" or "NONE")
    end
  end

  -- Party and box icons.  PartyMenu.drawIcon, which the party menu and Bill's PC
  -- Plus both call, draws a species entry of the form { image, trueColor }
  -- whole and with its two frames.  For a species whose Crystal icon is built,
  -- it is handed a view of the game whose icon table has that entry.
  local iconShims, iconEntries = IconShim.new(), {}
  local function iconEntry(dex)
    local meta = ready[dex] and not failed[dex] and cache:meta(dex)
    if not (meta and meta.icon) then return nil end
    -- the grey sheet: the engine colours it with the game's palettes, the way it
    -- does its own icons
    local path = cache:iconPath(meta.icon)
    local entry = iconEntries[path]
    if not entry then
      entry = { image = path, trueColor = false }
      iconEntries[path] = entry
    end
    return entry
  end

  local okParty, PartyMenu = pcall(require, "src.ui.PartyMenu")
  if okParty and type(PartyMenu) == "table" and type(PartyMenu.drawIcon) == "function" then
    -- a reload wraps the engine's own function again, not the last wrapper
    local original = PartyMenu.__casDrawIcon or PartyMenu.drawIcon
    PartyMenu.__casDrawIcon = original
    PartyMenu.drawIcon = function(game, mon, ...)
      if mon and mod.options:get("party_icons") ~= "game" then
        local dex = dexOf(game and game.data, mon.species)
        local entry = dex and iconEntry(dex)
        local view = entry and iconShims:view(game, mon.species, entry)
        if view then return original(view, mon, ...) end
      end
      return original(game, mon, ...)
    end
  end

  -- The title screen draws Red over the Pokemon.  For a true-colour Pokemon the
  -- engine redraws its rectangle unshaded, which would put Red's art there in
  -- raw grey, so it leaves Red's whole bounding box out.  Whatever part of the
  -- Pokemon reaches into that box but not onto Red's own pixels then takes Red's
  -- palette (Scyther's claws turn purple).  This replaces the engine's marks
  -- with ones that leave out only the pixels Red really covers.  If anything
  -- about the screen is not what it expects, the engine's marks go through
  -- unchanged.
  local okTitle, TitleState = pcall(require, "src.ui.TitleState")
  if okTitle and type(TitleState) == "table" and type(TitleState.draw) == "function" then
    local original = TitleState.__casDraw or TitleState.draw
    TitleState.__casDraw = original
    local redRows = {}
    local function rowsFor(path)
      local rows = redRows[path]
      if rows == nil then
        local ok, data = pcall(require("src.render.Assets").imageData, path)
        rows = false
        if ok and data then
          local w, h = data:getDimensions()
          rows = TitleMask.rowRuns(function(x, y)
            local _, _, _, a = data:getPixel(x, y)
            return a > 0.5
          end, w, h)
          rows.w, rows.h = w, h
        end
        redRows[path] = rows
      end
      return rows or nil
    end

    -- the rects of the Pokemon the engine just marked, as the Pokemon's own
    -- rectangle minus Red's pixels; nil when the screen is not as expected
    local function monRects(self, marks)
      local sprite = self:currentSprite()
      local rows = self.player and self.playerPath and rowsFor(self.playerPath)
      if not (sprite and rows and self.monOffset) then return nil end
      local w, h = sprite:getDimensions()
      local x, y = 40 + math.floor((56 - w) / 2) + self.monOffset, 136 - h
      for _, m in ipairs(marks) do
        if m[1] < x or m[2] < y or m[1] + m[3] > x + w or m[2] + m[4] > y + h then return nil end
      end
      local placements = {}
      if self.playerQuads and self.ballQuad then
        for _, part in ipairs(self.playerQuads) do
          local qx, qy, qw, qh = part[1]:getViewport()
          placements[#placements + 1] = { runs = rows, qx = qx, qy = qy, qw = qw, qh = qh,
            x = 82 + part[2], y = 80 + part[3] }
        end
        local qx, qy, qw, qh = self.ballQuad:getViewport()
        placements[#placements + 1] = { runs = rows, qx = qx, qy = qy, qw = qw, qh = qh,
          x = 82, y = self.ballY }
      else
        placements[1] = { runs = rows, qx = 0, qy = 0, qw = rows.w, qh = rows.h, x = 82, y = 80 }
      end
      return TitleMask.freeRects({ x, y, w, h }, placements)
    end

    TitleState.draw = function(self, ...)
      local P = require("src.render.PaletteFX")
      local realMark, marks = P.markTrueColor, {}
      P.markTrueColor = function(x, y, w, h) marks[#marks + 1] = { x, y, w, h } end
      local ok, err = pcall(original, self, ...)
      P.markTrueColor = realMark
      local rects
      if ok and #marks > 0 then
        local good, result = pcall(monRects, self, marks)
        if good then rects = result else warnOnce("title", "title screen: %s", tostring(result)) end
      end
      for _, r in ipairs(rects or marks) do realMark(r[1], r[2], r[3], r[4]) end
      if not ok then error(err, 0) end
    end
  end

  -- Results are collected every frame, so a decode that finished during boot is
  -- already cached by the first battle instead of being written at its start.
  mod.hooks:wrap("core.update", function(next, game, dt)
    pollJobs()
    local ok, err = pcall(tickScreens, game)
    if not ok then warnOnce("screenanim", "screen animation failed: %s", tostring(err)) end
    return next(game, dt)
  end, 930)

  -- The DIAGNOSTICS readout.  Phones keep the save folder out of reach, so
  -- the state a bug report needs is drawn on the battle instead of logged.
  local function sideInfo(screen, battler, side)
    local dex = battler and battler.mon and dexOf(screen.data, battler.mon.species)
    if not dex then return false end
    return { dex = dex, source = resolve(dex, side, nil, isShiny(battler.mon)) and "cas" or "game" }
  end

  local function drawStatus(screen)
    local Font = require("src.render.Font")
    local readyCount, failedCount = 0, 0
    for dex = 1, LAST do
      if ready[dex] then readyCount = readyCount + 1 end
    end
    for dex = 1, LAST do
      if failed[dex] then failedCount = failedCount + 1 end
    end
    local lines = Status.lines({
      version = mod.manifest and mod.manifest.version or "?",
      stamp = cache.stamp, ready = readyCount, failed = failedCount,
      running = #running, waiting = #pending,
      jobs = (mod.job and mod.job:available()) and true or false,
      enemy = sideInfo(screen, screen.enemy, "front"),
      player = sideInfo(screen, screen.player, "back"),
      err = lastErr, note = dexNote, screens = recentScreens,
    })
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, 160, #lines * 8 + 2)
    for i, line in ipairs(lines) do Font.draw(line, 0, (i - 1) * 8 + 1) end
    love.graphics.setColor(1, 1, 1, 1)
  end

  local attacking = setmetatable({}, { __mode = "k" })
  mod.hooks:wrap("battle.overlay", function(next, screen)
    local ok, err = pcall(function()
      pollJobs()
      local now = (love and love.timer) and love.timer.getTime() or 0
      -- the moment a Pokemon uses a move, which the engine reports whether or not
      -- the player has battle animations on
      local state = attacking[screen]
      if not state then state = {} attacking[screen] = state end
      local attacker = Attack.update(screen, state, now)
      if attacker and mod.options:get("attack_animation") ~= "off" then
        swap:restart(attacker, now)
      end
      swap:tick(screen, screen.enemy, "front", now)
      swap:tick(screen, screen.player, "back", now)
    end)
    frozen = nil
    if not ok then warnOnce("overlay", "sprite swap failed: %s", tostring(err)) end
    if mod.options:get("diagnostics") == "on" then
      local drew, drawErr = pcall(drawStatus, screen)
      if not drew then warnOnce("status", "diagnostics failed: %s", tostring(drawErr)) end
    end
    pcall(syncShinyIntro, screen.game)
    local result = next(screen)
    -- the sparkles go on top of everything the battle drew
    local drew, drawErr = pcall(function()
      drawEntrance(screen, screen.enemy, true)
      drawEntrance(screen, screen.player, false)
    end)
    if not drew then warnOnce("entrancedraw", "shiny entrance drawing failed: %s", tostring(drawErr)) end
    return result
  end, 930)
end
