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
  local ALL_LIBS = { "lz", "rom", "addresses", "pic", "png", "anim", "cache",
                     "playback", "swap", "ingest" }
  local JOB_LIBS = { "lz", "rom", "addresses", "pic", "png", "anim" }

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
  local function warnOnce(key, fmt, ...)
    if warned[key] then return end
    warned[key] = true
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
      local seen = {}
      local function frame(index)
        if seen[index] then return end
        seen[index] = true
        registerScale(("cas_f%03d_%d"):format(dex, index), cache:framePath(dex, index))
        registerScale(("cas_f%03d_%dm"):format(dex, index), cache:framePath(dex, index, true))
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
      for dex = job.first, job.last do failed[dex] = true end
      return
    end
    for dex, message in pairs(result.result.errors) do
      failed[dex] = true
      mod.log:warn("species %d not decoded: %s", dex, tostring(message))
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
  local frozen -- the time a swap is rebuilding for, so the hook agrees with it
  local function clock()
    if frozen then return frozen end
    if love and love.timer then return love.timer.getTime() end
    return 0
  end

  local function dexOf(data, species)
    local def = data and data.pokemon and data.pokemon[species]
    local dex = def and tonumber(def.dex)
    if dex and dex >= 1 and dex <= LAST then return dex end
    return nil
  end

  local function resolve(dex, side, seconds)
    local meta = ready[dex] and not failed[dex] and cache:meta(dex)
    if not meta then return nil end
    if side == "back" then
      if mod.options:get("back_sprites") == "front" then
        return cache:framePath(dex, Playback.frameAt(meta.timeline, seconds), true)
      end
      return cache:backPath(dex)
    end
    return cache:framePath(dex, Playback.frameAt(meta.timeline, seconds))
  end

  mod.hooks:wrap("pokemon.sprite", function(next, originalPath, ctx)
    if not (ctx and ctx.kind == "battle") then return next(originalPath, ctx) end
    pollJobs()
    local dex = dexOf(ctx.data, ctx.species)
    local path = dex and resolve(dex, ctx.side, clock())
    return path or next(originalPath, ctx)
  end, 930)

  local BattleState
  local swap = Swap.new({
    dexOf = function(screen, battler) return dexOf(screen.data, battler.mon.species) end,
    busy = function(screen, battler)
      if screen.ghost or screen.ghostReal or battler.fainted then return true end
      return screen.fxFaintActive and screen:fxFaintActive(battler) or false
    end,
    pathFor = resolve,
    rebuild = function(screen, battler)
      BattleState = BattleState or require("src.battle.BattleState")
      -- makeBattler is pure and resolves the sprite through the engine's own
      -- palette pipeline, which calls the hook above for the frozen time.
      local ok, fresh = pcall(BattleState.makeBattler, screen.data, battler.mon,
        battler.isPlayer and true or false, nil)
      return ok and fresh and fresh.sprite or nil
    end,
  })

  -- Results are collected every frame, so a decode that finished during boot is
  -- already cached by the first battle instead of being written at its start.
  mod.hooks:wrap("core.update", function(next, game, dt)
    pollJobs()
    return next(game, dt)
  end, 930)

  mod.hooks:wrap("battle.overlay", function(next, screen)
    local ok, err = pcall(function()
      pollJobs()
      frozen = clock()
      swap:tick(screen, screen.enemy, "front", frozen)
      swap:tick(screen, screen.player, "back", frozen)
    end)
    frozen = nil
    if not ok then warnOnce("overlay", "sprite swap failed: %s", tostring(err)) end
    return next(screen)
  end, 930)
end
