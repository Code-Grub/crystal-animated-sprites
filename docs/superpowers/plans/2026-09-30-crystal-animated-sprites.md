# Crystal Animated Sprites Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Gen1Recomp mod that plays Crystal's animated front sprites in Red/Blue/Yellow battles, with every pixel decoded from the player's own Crystal ROM and cached locally.

**Architecture:** Pure-Lua libraries (LZ decoder, 2bpp tile decoder, animation/bitmask parser, PNG encoder) turn the ROM into 8-bit grayscale PNG frames plus a timeline. A background job does the decode once (the main thread reads the ROM through `mod.imports` and hands the bytes to the job, because a job has no `mod` object). Frames land in `mod_cache/crystal_animated_sprites/`, and a `pokemon.sprite` hook plus a battle-screen tick serve the current frame.

**Tech Stack:** Lua 5.1 / LuaJIT (mod sandbox: `bit`, `string`, `table`, `math`, `load`; no `require`, no `io`). Tests run under bare `luajit`. Engine integration is checked in `C:/g2dev` (current engine), never in `game/` (stale).

**Spec:** `docs/superpowers/specs/2026-09-30-crystal-animated-sprites-design.md`

## Global Constraints

- Mod id `crystal_animated_sprites`; manifest `api` 2, `profile` `content`, `games` `["gen1"]`.
- `required_imports`: id `crystal_rom`, file `crystal.gbc`, `format` `raw`, size `2097152`, MD5 `9f2922b235a5eeb78d65594e82ef5dde` or `301899b8087289a6436b0a241fbbb474`. The mod does not load without the ROM.
- `conflicts`: `crystal_animated_sprites_with_shiny_visuals`, `gen2_shiny_visuals`, `shiny_visuals`, `CRYSTAL_251`. (Never itself.)
- Permissions: `engine_internals` and `background` (jobs). Nothing else.
- No Nintendo art in the repo, no code copied from the original mod or from `gen1recomp-mod-crystal-251` (neither has a license). Decoders are written from the format. Crystal 251 output is a cross-check only.
- Mod code cannot `require`. Sibling files load through `mod:read` + `load`; every `lib/*.lua` is a chunk that receives a `need(name)` function as its first vararg and returns its module table.
- Job scripts are pure compute: no `mod`, no `require`. Library source is passed into the job as strings.
- Reads from the import are zero-based and capped at 8 MiB per call; a single `mod.cache:write` is capped at 64 MiB.
- Frames are 8-bit grayscale PNGs using exactly the shades `255, 170, 85, 0` (Game Boy index 0..3). The engine's palette pass thresholds red at `>0.83`, `>0.5`, `>0.17`, so these four values round-trip into the four palette slots.
- Commits: author `Code-Grub <34581585+Code-Grub@users.noreply.github.com>` (set per repo), message body only. No `Co-Authored-By`, no `Claude-Session`, no tool-attribution lines, no em-dashes in anything that could be published.
- v1 scope only: species 1 to 151, front animation, `BACK SPRITES` option. No shiny, sparkle, cry or sound work.

## Review Focus

Failure modes the spec implies but no single task's happy path exercises. Each has a test in the task that owns the code.

1. **One species fails to decode** (truncated LZ, unexpected dimension byte). The other 150 must still work; the bad one keeps the vanilla sprite and logs once. (Task 7 job, Task 9 main)
2. **A battle starts while the first-boot decode is still running.** Vanilla sprites until that species is cached; no hitch, no error, and the animation starts on the next battle. (Task 9)
3. **Cache is stale** because the player swapped v1.0 for v1.1, or the decoder changed. Re-decode rather than serve old frames. (Task 7 cache)
4. **Engine effects own the pic.** Substitute, faint, Transform, slide-in and fades replace or hide `battler.sprite`; our per-frame swap must yield to them and never resurrect a hidden or fainted mon. (Task 10)
5. **Cache write fails** (disk full, 64 MiB cap). The mod logs once and falls back to vanilla for the affected species instead of erroring every frame. (Task 7 cache, Task 9)

## File Structure

```
crystal-animated-sprites/
  manifest.json
  options.lua               option rows (BACK SPRITES)
  main.lua                  entry: load siblings, job orchestration, hooks
  lib/
    lz.lua                  Crystal LZ decompressor
    rom.lua                 bounds-checked banked ROM reader
    addresses.lua           ROM table addresses (bank, address)
    pic.lua                 2bpp tiles -> pixel indices, tile-map composition
    png.lua                 8-bit grayscale PNG encoder (stored deflate)
    anim.lua                dimensions, pic pointers, script, frame maps, decode
    cache.lua               stamp, per-species put/meta/framePath over a store
    playback.lua            pure: timeline + elapsed time -> frame index
  jobs/
    decode.lua              self-contained job: libs arrive as strings
  tools/
    dump.lua                dev tool: write a species' frames to PNG files
  tests/
    harness.lua  run.lua
    lz_test.lua rom_test.lua pic_test.lua png_test.lua
    anim_test.lua cache_test.lua playback_test.lua job_test.lua
  docs/superpowers/{specs,plans}/
```

Run all standalone tests from the repo root: `luajit tests/run.lua`. Engine-integration steps run from `C:/g2dev` through a junction (Task 1).

The ROM for tests: `CRYSTAL_ROM` env var, default `C:/Users/camwr/Desktop/Gen1Recomp/game/Pokemon - Crystal Version (USA, Europe) (Rev 1).gbc` (MD5 `301899b8087289a6436b0a241fbbb474`, verified). ROM-backed tests print `SKIP` when it is missing and `REQUIRE_ROM=1` turns any skip into a failure.

---

### Task 1: Scaffold, manifest, harness, engine junction

**Files:**
- Create: `manifest.json`, `options.lua`, `tests/harness.lua`, `tests/run.lua`, `.gitignore`
- Modify: `docs/superpowers/specs/2026-09-30-crystal-animated-sprites-design.md` (add "Constraints found while planning")

**Interfaces:**
- Produces: `H.test(name, fn)`, `H.skip(name, why)`, `H.eq(actual, expected, msg)`, `H.arrayEq(actual, expected, msg)`, `H.need(name)` (loads `lib/<name>.lua` passing `need`), `H.rom()` (ROM bytes or `nil`), `H.finish()` (prints summary, exits non-zero on failure).

- [ ] **Step 1: Write `manifest.json`**

```json
{
  "id": "crystal_animated_sprites",
  "name": "Crystal Animated Sprites",
  "version": "0.1.0",
  "api": 2,
  "entry": "main.lua",
  "profile": "content",
  "category": "VISUAL",
  "games": ["gen1"],
  "game_version": ">=0.0.0-0 <2.0.0",
  "priority": 980,
  "permissions": ["engine_internals", "background"],
  "dependencies": [],
  "optional_dependencies": [],
  "conflicts": [
    "crystal_animated_sprites_with_shiny_visuals",
    "gen2_shiny_visuals",
    "shiny_visuals",
    "CRYSTAL_251"
  ],
  "options_schema": "options.lua",
  "description": "Crystal's animated front sprites in Red, Blue and Yellow, decoded from your own Pokemon Crystal ROM. No artwork is included.",
  "github": "Code-Grub/crystal-animated-sprites",
  "required_imports": [
    {
      "id": "crystal_rom",
      "name": "Pokemon Crystal (English UE) ROM",
      "description": "Your own Pokemon Crystal ROM. English UE v1.0 and v1.1 are supported.",
      "file": "crystal.gbc",
      "format": "raw",
      "size": 2097152,
      "md5": [
        "9f2922b235a5eeb78d65594e82ef5dde",
        "301899b8087289a6436b0a241fbbb474"
      ]
    }
  ]
}
```

- [ ] **Step 2: Write `options.lua`** (same row shape as `pokebag-plus/options.lua`)

```lua
-- CRYSTAL is Crystal's own static back art.  ANIMATED FRONT plays the front
-- animation mirrored in the back slot, which is what the older sprite mods
-- did.  Read by the mod manager (manifest.options_schema) and by main.lua.
return {
  {
    key = "back_sprites",
    type = "choice",
    label = "BACK SPRITES",
    default = "crystal",
    choices = { { "CRYSTAL", "crystal" }, { "ANIMATED FRONT", "front" } },
  },
}
```

- [ ] **Step 3: Write `tests/harness.lua`**

```lua
local H = { passed = 0, failed = 0, skipped = 0 }

function H.test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    H.passed = H.passed + 1
    print("PASS  " .. name)
  else
    H.failed = H.failed + 1
    print("FAIL  " .. name .. "\n      " .. tostring(err))
  end
end

function H.skip(name, why)
  H.skipped = H.skipped + 1
  print("SKIP  " .. name .. " (" .. why .. ")")
end

function H.eq(actual, expected, msg)
  if actual ~= expected then
    error((msg or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual), 2)
  end
end

function H.arrayEq(actual, expected, msg)
  H.eq(#actual, #expected, (msg or "array") .. " length")
  for i = 1, #expected do
    if actual[i] ~= expected[i] then
      error((msg or "array") .. " differs at " .. i .. ": expected "
        .. tostring(expected[i]) .. ", got " .. tostring(actual[i]), 2)
    end
  end
end

local cache = {}
local function need(name)
  if not cache[name] then
    local chunk = assert(loadfile("lib/" .. name .. ".lua"))
    cache[name] = chunk(need)
  end
  return cache[name]
end
H.need = need

local DEFAULT_ROM = "C:/Users/camwr/Desktop/Gen1Recomp/game/"
  .. "Pokemon - Crystal Version (USA, Europe) (Rev 1).gbc"

function H.rom()
  local path = os.getenv("CRYSTAL_ROM") or DEFAULT_ROM
  local f = io.open(path, "rb")
  if not f then return nil end
  local raw = f:read("*a")
  f:close()
  return raw
end

function H.finish()
  print(("\n%d passed, %d failed, %d skipped"):format(H.passed, H.failed, H.skipped))
  local strict = os.getenv("REQUIRE_ROM") == "1" and H.skipped > 0
  os.exit((H.failed > 0 or strict) and 1 or 0)
end

return H
```

- [ ] **Step 4: Write `tests/run.lua`**

```lua
package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local files = {
  "lz_test", "rom_test", "pic_test", "png_test",
  "anim_test", "cache_test", "playback_test", "job_test",
}
for _, name in ipairs(files) do
  local path = "tests/" .. name .. ".lua"
  local f = io.open(path, "rb")
  if f then
    f:close()
    print("== " .. name)
    dofile(path)
  end
end
H.finish()
```

Test files call `local H = require("tests.harness")` and do not call `H.finish()` themselves; `run.lua` does.

- [ ] **Step 5: Write `.gitignore`**

```
out/
*.gbc
baseroms/
```

- [ ] **Step 6: Amend the spec** with a short "Constraints found while planning" section stating: a job has no `mod` object so the main thread reads the ROM with `mod.imports:read("crystal_rom", 0, 2097152)` and passes it in the job argument; libraries reach the job as source strings; the manifest needs the `background` permission; frames are cached as PNGs under `mod_cache/<id>/` and referenced by path (Kanto-Reforged does the same); jobs are batched because the budget is clamped to 30 s and two jobs may run per mod.

- [ ] **Step 7: Verify the harness runs with nothing in it**

Run: `luajit tests/run.lua`
Expected: `0 passed, 0 failed, 0 skipped`, exit code 0.

- [ ] **Step 8: Create the engine junction (never delete it recursively)**

Run (PowerShell): `New-Item -ItemType Junction -Path C:\g2dev\mods\crystal_animated_sprites -Target C:\Users\camwr\Desktop\Gen1Recomp\crystal-animated-sprites`
Undo with `cmd /c rmdir C:\g2dev\mods\crystal_animated_sprites` only. `rm -rf` and `Remove-Item -Recurse` follow the junction and destroy the repo.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "Scaffold manifest, options and test harness"
```

---

### Task 2: Crystal LZ decompressor

**Files:**
- Create: `lib/lz.lua`
- Test: `tests/lz_test.lua`

**Interfaces:**
- Produces: `LZ.decompress(src: string, start: integer|nil) -> out: number[], nextPos: integer`. `out` is a 1-based array of bytes. `start` is a 1-based string index (default 1). `nextPos` is the index just after the terminating `0xFF`.

The stream is a sequence of commands. Header byte `h`: `0xFF` ends. Otherwise `command = h >> 5`, `length = (h & 0x1F) + 1`; if `command == 7` the real command is `(h >> 2) & 7` and the length is `(((h & 3) << 8) | nextByte) + 1`. Commands: 0 literal run, 1 one byte repeated, 2 two bytes alternating, 3 zero fill, 4 copy from earlier output, 5 copy with each byte bit-reversed, 6 copy backwards. For 4 to 6 the next byte selects the source: high bit set means relative (`out length - (b & 0x7F)`, 1-based), otherwise absolute 16-bit big-endian offset (0-based, so `+1`).

- [ ] **Step 1: Write the failing tests**

```lua
package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local LZ = H.need("lz")
local function S(...) return string.char(...) end

H.test("lz: empty stream", function()
  local out, pos = LZ.decompress(S(0xFF))
  H.arrayEq(out, {})
  H.eq(pos, 2, "position after terminator")
end)

H.test("lz: literal run", function()
  H.arrayEq((LZ.decompress(S(0x02, 0xAA, 0xBB, 0xCC, 0xFF))), { 0xAA, 0xBB, 0xCC })
end)

H.test("lz: iterate", function()
  H.arrayEq((LZ.decompress(S(0x23, 0x55, 0xFF))), { 0x55, 0x55, 0x55, 0x55 })
end)

H.test("lz: alternate", function()
  H.arrayEq((LZ.decompress(S(0x44, 0x01, 0x02, 0xFF))), { 1, 2, 1, 2, 1 })
end)

H.test("lz: zero fill", function()
  H.arrayEq((LZ.decompress(S(0x62, 0xFF))), { 0, 0, 0 })
end)

H.test("lz: repeat with absolute offset", function()
  H.arrayEq((LZ.decompress(S(0x03, 1, 2, 3, 4, 0x82, 0x00, 0x01, 0xFF))),
    { 1, 2, 3, 4, 2, 3, 4 })
end)

H.test("lz: repeat with relative offset", function()
  H.arrayEq((LZ.decompress(S(0x03, 1, 2, 3, 4, 0x81, 0x81, 0xFF))),
    { 1, 2, 3, 4, 3, 4 })
end)

H.test("lz: flip reverses bit order", function()
  H.arrayEq((LZ.decompress(S(0x00, 0x01, 0xA0, 0x80, 0xFF))), { 0x01, 0x80 })
end)

H.test("lz: reverse copies backwards", function()
  H.arrayEq((LZ.decompress(S(0x02, 1, 2, 3, 0xC2, 0x80, 0xFF))),
    { 1, 2, 3, 3, 2, 1 })
end)

H.test("lz: long command form", function()
  local out = LZ.decompress(S(0xE5, 0x2B, 0x07, 0xFF))
  H.eq(#out, 300, "length")
  H.eq(out[1], 7); H.eq(out[300], 7)
end)

H.test("lz: start offset and trailing data", function()
  local out, pos = LZ.decompress(S(0x99, 0x00, 0xAB, 0xFF, 0x77), 2)
  H.arrayEq(out, { 0xAB })
  H.eq(pos, 5, "position")
end)

H.test("lz: truncated stream is an error", function()
  local ok = pcall(LZ.decompress, S(0x02, 0xAA))
  H.eq(ok, false, "truncated must raise")
end)

H.test("lz: bad back-reference is an error", function()
  local ok = pcall(LZ.decompress, S(0x80, 0x00, 0x09, 0xFF))
  H.eq(ok, false, "reference before start must raise")
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `luajit tests/run.lua`
Expected: error loading `lib/lz.lua` (file missing).

- [ ] **Step 3: Write `lib/lz.lua`**

```lua
local LZ = {}

local function flip(v)
  local out = 0
  for b = 0, 7 do
    if math.floor(v / 2 ^ b) % 2 == 1 then out = out + 2 ^ (7 - b) end
  end
  return out
end

function LZ.decompress(src, start)
  local pos, out, n = start or 1, {}, 0

  local function byte()
    local v = src:byte(pos)
    assert(v ~= nil, "truncated Crystal LZ stream")
    pos = pos + 1
    return v
  end
  local function emit(v)
    n = n + 1
    out[n] = v
  end

  while true do
    local header = byte()
    if header == 0xFF then break end
    local command, length = math.floor(header / 32), header % 32
    if command == 7 then
      command = math.floor(length / 4)
      length = (length % 4) * 256 + byte()
    end
    length = length + 1

    if command == 0 then
      for _ = 1, length do emit(byte()) end
    elseif command == 1 then
      local v = byte()
      for _ = 1, length do emit(v) end
    elseif command == 2 then
      local a, b = byte(), byte()
      for i = 1, length do emit(i % 2 == 1 and a or b) end
    elseif command == 3 then
      for _ = 1, length do emit(0) end
    elseif command >= 4 and command <= 6 then
      local first = byte()
      local from
      if first >= 0x80 then
        from = n - (first - 0x80)
      else
        from = first * 256 + byte() + 1
      end
      for i = 0, length - 1 do
        local v = out[command == 6 and from - i or from + i]
        assert(v ~= nil, "invalid back-reference in Crystal LZ stream")
        emit(command == 5 and flip(v) or v)
      end
    else
      error("invalid Crystal LZ command " .. command)
    end
  end
  return out, pos
end

return LZ
```

- [ ] **Step 4: Run to verify pass**

Run: `luajit tests/run.lua`
Expected: all `lz:` tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/lz.lua tests/lz_test.lua
git commit -m "Add Crystal LZ decompressor"
```

---

### Task 3: ROM reader and table addresses

**Files:**
- Create: `lib/rom.lua`, `lib/addresses.lua`
- Test: `tests/rom_test.lua`

**Interfaces:**
- Produces: `Rom.new(raw) -> rom` with `rom.raw`, `rom:u8(offset)`, `rom:u16(offset)` (little-endian), `rom:banked(bank, addr) -> offset`. `Rom.offset(bank, addr)` is the same arithmetic without an instance. All offsets are zero-based file offsets; `u8` raises on a read past the end.
- Produces `addresses` table: `baseData`, `picPointers`, `animPointers`, `bitmaskPointers`, `framesPointers` (each `{ bank, addr }`), `picBankBias = 0x36`, `kantoFramesBank = 0x35`.

These addresses describe Crystal's layout in pret/pokecrystal, identical in UE v1.0 and v1.1. The ROM-backed test checks structure rather than trusting them.

- [ ] **Step 1: Write the failing tests**

```lua
package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local Rom = H.need("rom")
local A = H.need("addresses")

H.test("rom: bank 0 is a flat address", function()
  H.eq(Rom.offset(0, 0x0150), 0x150)
end)

H.test("rom: switchable banks map 0x4000-0x7FFF", function()
  H.eq(Rom.offset(0x14, 0x5424), 0x51424)
  H.eq(Rom.offset(1, 0x4000), 0x4000)
end)

H.test("rom: banked address below 0x4000 is rejected", function()
  H.eq(pcall(Rom.offset, 5, 0x1234), false)
end)

H.test("rom: u8 and u16 read little-endian and bound-check", function()
  local rom = Rom.new(string.char(0x34, 0x12, 0xFF))
  H.eq(rom:u8(0), 0x34)
  H.eq(rom:u16(0), 0x1234)
  H.eq(pcall(rom.u8, rom, 3), false, "read past end must raise")
end)

local raw = H.rom()
if not raw then
  H.skip("rom: real Crystal image checks", "no ROM found (set CRYSTAL_ROM)")
else
  H.test("rom: real image is Crystal and 2 MiB", function()
    H.eq(#raw, 2097152)
    H.eq(raw:sub(0x135, 0x13E), "PM_CRYSTAL")
  end)

  H.test("rom: base data first record is Bulbasaur-shaped", function()
    local rom = Rom.new(raw)
    local off = rom:banked(A.baseData.bank, A.baseData.addr)
    H.eq(rom:u8(off), 1, "dex number of record 1")
    H.eq(rom:u8(off + 32), 2, "dex number of record 2")
    H.eq(rom:u8(off + 24 * 32), 25, "record 25 is Pikachu")
  end)
end
```

- [ ] **Step 2: Run to verify failure**

Run: `luajit tests/run.lua`
Expected: `lib/rom.lua` missing.

- [ ] **Step 3: Write `lib/rom.lua`**

```lua
local Rom = {}
Rom.__index = Rom

function Rom.offset(bank, addr)
  if bank == 0 then return addr end
  assert(addr >= 0x4000 and addr < 0x8000,
    ("banked address 0x%04X is outside 0x4000-0x7FFF"):format(addr))
  return bank * 0x4000 + (addr - 0x4000)
end

function Rom.new(raw)
  return setmetatable({ raw = raw }, Rom)
end

function Rom:u8(offset)
  local v = self.raw:byte(offset + 1)
  assert(v ~= nil, ("read past end of ROM at 0x%X"):format(offset))
  return v
end

function Rom:u16(offset)
  return self:u8(offset) + self:u8(offset + 1) * 256
end

function Rom:banked(bank, addr)
  return Rom.offset(bank, addr)
end

return Rom
```

- [ ] **Step 4: Write `lib/addresses.lua`**

```lua
-- Crystal UE v1.0 / v1.1 (identical layout), from pret/pokecrystal.
-- Each entry is { bank, address }.  Tables are indexed by national dex
-- number minus one.
return {
  baseData        = { bank = 0x14, addr = 0x5424 }, -- 32-byte records
  picPointers     = { bank = 0x48, addr = 0x4000 }, -- 6 bytes: front, back
  animPointers    = { bank = 0x34, addr = 0x4695 }, -- dw per species
  bitmaskPointers = { bank = 0x34, addr = 0x64EF }, -- dw per species
  framesPointers  = { bank = 0x35, addr = 0x4000 }, -- dw per species
  picBankBias     = 0x36, -- pic bank bytes are stored minus this
  kantoFramesBank = 0x35, -- frame records for species 1-151
  baseDataDimensionsOffset = 0x11,
}
```

- [ ] **Step 5: Run to verify pass**

Run: `luajit tests/run.lua`
Expected: all `rom:` tests PASS (or the ROM test SKIP if the ROM is absent). If the base-data test FAILS, the address is wrong for this image: stop and cross-check against a pret/pokecrystal symbol file before continuing.

- [ ] **Step 6: Commit**

```bash
git add lib/rom.lua lib/addresses.lua tests/rom_test.lua
git commit -m "Add ROM reader and Crystal table addresses"
```

---

### Task 4: 2bpp tile decoding and tile-map composition

**Files:**
- Create: `lib/pic.lua`
- Test: `tests/pic_test.lua`

**Interfaces:**
- Produces: `Pic.tilePixels(data, t) -> number[64]` (palette index 0..3, row-major). `data` is a 1-based byte array (as returned by `LZ.decompress`), `t` a 0-based tile index. `Pic.identityMap(size) -> number[size*size]` (tile ids `0..size*size-1`). `Pic.compose(data, map, size, order) -> pixels, width, height`. `map[i+1]` is the source tile for position `i` (0-based). `order` is `"columns"` (position `i` is row `i % size`, column `floor(i/size)`) or `"rows"` (row `floor(i/size)`, column `i % size`). `pixels` is row-major, `width = height = size*8`.

- [ ] **Step 1: Write the failing tests**

```lua
package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local Pic = H.need("pic")

-- One tile: row 0 has low plane 0xFF, high plane 0x00 (all colour 1);
-- row 1 has low 0x00, high 0xFF (all colour 2); row 2 has both (colour 3);
-- the rest are colour 0.
local function tile()
  local t = { 0xFF, 0x00, 0x00, 0xFF, 0xFF, 0xFF }
  for _ = 7, 16 do t[#t + 1] = 0 end
  return t
end

H.test("pic: tilePixels decodes the two bit planes", function()
  local px = Pic.tilePixels(tile(), 0)
  H.eq(#px, 64)
  H.eq(px[1], 1); H.eq(px[8], 1)
  H.eq(px[9], 2); H.eq(px[16], 2)
  H.eq(px[17], 3)
  H.eq(px[25], 0)
end)

H.test("pic: leftmost pixel is the high bit", function()
  local px = Pic.tilePixels({ 0x80, 0x00 }, 0)
  H.eq(px[1], 1); H.eq(px[2], 0)
end)

H.test("pic: identityMap counts up", function()
  H.arrayEq(Pic.identityMap(2), { 0, 1, 2, 3 })
end)

-- Four tiles, each a solid colour index 0..3.
local function solidTiles()
  local d = {}
  for t = 0, 3 do
    for _ = 1, 8 do
      d[#d + 1] = (t % 2 == 1) and 0xFF or 0x00 -- low plane
      d[#d + 1] = (t >= 2) and 0xFF or 0x00     -- high plane
    end
  end
  return d
end

H.test("pic: compose in column order", function()
  local px, w, h = Pic.compose(solidTiles(), Pic.identityMap(2), 2, "columns")
  H.eq(w, 16); H.eq(h, 16)
  -- position 0 = (row0,col0), 1 = (row1,col0), 2 = (row0,col1), 3 = (row1,col1)
  H.eq(px[1], 0)            -- row0 col0 -> tile 0 -> colour 0
  H.eq(px[8 * 16 + 1], 1)   -- row1 col0 -> tile 1 -> colour 1
  H.eq(px[9], 2)            -- row0 col1 -> tile 2 -> colour 2
  H.eq(px[8 * 16 + 9], 3)   -- row1 col1 -> tile 3 -> colour 3
end)

H.test("pic: compose in row order", function()
  local px = Pic.compose(solidTiles(), Pic.identityMap(2), 2, "rows")
  H.eq(px[1], 0)            -- row0 col0 -> tile 0
  H.eq(px[9], 1)            -- row0 col1 -> tile 1
  H.eq(px[8 * 16 + 1], 2)   -- row1 col0 -> tile 2
  H.eq(px[8 * 16 + 9], 3)   -- row1 col1 -> tile 3
end)

H.test("pic: compose honours a non-identity map", function()
  local px = Pic.compose(solidTiles(), { 3, 3, 3, 3 }, 2, "rows")
  H.eq(px[1], 3); H.eq(px[8 * 16 + 9], 3)
end)
```


- [ ] **Step 2: Run to verify failure**

Run: `luajit tests/run.lua`
Expected: `lib/pic.lua` missing.

- [ ] **Step 3: Write `lib/pic.lua`**

```lua
local Pic = {}

function Pic.tilePixels(data, t)
  local px, base = {}, t * 16
  for row = 0, 7 do
    local lo = data[base + row * 2 + 1] or 0
    local hi = data[base + row * 2 + 2] or 0
    for x = 0, 7 do
      local bit = 7 - x
      px[row * 8 + x + 1] = math.floor(lo / 2 ^ bit) % 2
        + 2 * (math.floor(hi / 2 ^ bit) % 2)
    end
  end
  return px
end

function Pic.identityMap(size)
  local m = {}
  for i = 1, size * size do m[i] = i - 1 end
  return m
end

function Pic.compose(data, map, size, order)
  local width = size * 8
  local out = {}
  for i = 0, size * size - 1 do
    local tileRow, tileCol
    if order == "columns" then
      tileRow, tileCol = i % size, math.floor(i / size)
    else
      tileRow, tileCol = math.floor(i / size), i % size
    end
    local px = Pic.tilePixels(data, map[i + 1])
    for y = 0, 7 do
      for x = 0, 7 do
        out[(tileRow * 8 + y) * width + tileCol * 8 + x + 1] = px[y * 8 + x + 1]
      end
    end
  end
  return out, width, width
end

return Pic
```

- [ ] **Step 4: Run to verify pass**

Run: `luajit tests/run.lua`
Expected: all `pic:` tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/pic.lua tests/pic_test.lua
git commit -m "Add 2bpp tile decoding and tile-map composition"
```

---

### Task 5: PNG encoder

**Files:**
- Create: `lib/png.lua`
- Test: `tests/png_test.lua`

**Interfaces:**
- Produces: `PNG.crc32(str) -> integer` (0..2^32-1), `PNG.adler32(str) -> integer`, `PNG.encodeGray(pixels, width, height, shades) -> string`. `pixels` is a row-major array of indices; `shades[index + 1]` is the 0..255 grey value written. The output is a valid 8-bit grayscale PNG using stored (uncompressed) deflate blocks. Uses the sandbox `bit` library.

- [ ] **Step 1: Write the failing tests**

```lua
package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local PNG = H.need("png")

local function be32(s, i)
  local a, b, c, d = s:byte(i, i + 3)
  return ((a * 256 + b) * 256 + c) * 256 + d
end

-- Minimal reader: check every chunk CRC, return IHDR fields and raw IDAT bytes.
local function parse(png)
  H.eq(png:sub(1, 8), "\137PNG\r\n\26\n", "signature")
  local pos, idat, ihdr = 9, {}, nil
  while pos <= #png do
    local len = be32(png, pos)
    local kind = png:sub(pos + 4, pos + 7)
    local body = png:sub(pos + 8, pos + 7 + len)
    H.eq(be32(png, pos + 8 + len), PNG.crc32(kind .. body), kind .. " crc")
    if kind == "IHDR" then
      ihdr = { w = be32(body, 1), h = be32(body, 5), depth = body:byte(9),
               ctype = body:byte(10) }
    elseif kind == "IDAT" then
      idat[#idat + 1] = body
    end
    pos = pos + 12 + len
  end
  return ihdr, table.concat(idat)
end

-- Unwrap a zlib stream made only of stored blocks.
local function inflateStored(z)
  local pos, out = 3, {}
  while true do
    local final = z:byte(pos)
    local len = z:byte(pos + 1) + z:byte(pos + 2) * 256
    local nlen = z:byte(pos + 3) + z:byte(pos + 4) * 256
    H.eq(len + nlen, 65535, "LEN/NLEN")
    out[#out + 1] = z:sub(pos + 5, pos + 4 + len)
    pos = pos + 5 + len
    if final == 1 then break end
  end
  local raw = table.concat(out)
  H.eq(be32(z, pos), PNG.adler32(raw), "adler32")
  return raw
end

H.test("png: crc32 and adler32 known values", function()
  H.eq(PNG.crc32("123456789"), 0xCBF43926)
  H.eq(PNG.adler32("Wikipedia"), 0x11E60398)
end)

H.test("png: 2x2 image round-trips", function()
  local png = PNG.encodeGray({ 0, 1, 2, 3 }, 2, 2, { 255, 170, 85, 0 })
  local ihdr, idat = parse(png)
  H.eq(ihdr.w, 2); H.eq(ihdr.h, 2); H.eq(ihdr.depth, 8); H.eq(ihdr.ctype, 0)
  local raw = inflateStored(idat)
  H.eq(raw, "\0" .. string.char(255, 170) .. "\0" .. string.char(85, 0))
end)

H.test("png: image larger than one stored block", function()
  local w, h, px = 300, 300, {}
  for i = 1, w * h do px[i] = i % 4 end
  local png = PNG.encodeGray(px, w, h, { 255, 170, 85, 0 })
  local _, idat = parse(png)
  local raw = inflateStored(idat)
  H.eq(#raw, (w + 1) * h, "raw length")
  H.eq(raw:byte(2), 170, "first pixel is index 1")
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `luajit tests/run.lua`
Expected: `lib/png.lua` missing.

- [ ] **Step 3: Write `lib/png.lua`**

```lua
local PNG = {}

local crcTable
local function buildTable()
  crcTable = {}
  for n = 0, 255 do
    local c = n
    for _ = 1, 8 do
      if bit.band(c, 1) == 1 then
        c = bit.bxor(0xEDB88320, bit.rshift(c, 1))
      else
        c = bit.rshift(c, 1)
      end
    end
    crcTable[n] = c
  end
end

function PNG.crc32(str)
  if not crcTable then buildTable() end
  local c = 0xFFFFFFFF
  for i = 1, #str do
    c = bit.bxor(crcTable[bit.band(bit.bxor(c, str:byte(i)), 0xFF)],
      bit.rshift(c, 8))
  end
  return bit.bxor(c, 0xFFFFFFFF) % 4294967296
end

function PNG.adler32(str)
  local a, b = 1, 0
  for i = 1, #str do
    a = (a + str:byte(i)) % 65521
    b = (b + a) % 65521
  end
  return b * 65536 + a
end

local function u32(n)
  n = n % 4294967296
  return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256,
    math.floor(n / 256) % 256, n % 256)
end

local function chunk(kind, body)
  return u32(#body) .. kind .. body .. u32(PNG.crc32(kind .. body))
end

local function storedZlib(raw)
  local parts, pos, total = { "\120\1" }, 1, #raw
  repeat
    local len = math.min(65535, total - pos + 1)
    local final = (pos + len > total) and 1 or 0
    local nlen = 65535 - len
    parts[#parts + 1] = string.char(final, len % 256, math.floor(len / 256),
      nlen % 256, math.floor(nlen / 256))
    parts[#parts + 1] = raw:sub(pos, pos + len - 1)
    pos = pos + len
  until pos > total
  parts[#parts + 1] = u32(PNG.adler32(raw))
  return table.concat(parts)
end

function PNG.encodeGray(pixels, width, height, shades)
  local rows = {}
  for y = 0, height - 1 do
    local bytes = { "\0" }
    local base = y * width
    for x = 1, width do
      bytes[#bytes + 1] = string.char(shades[pixels[base + x] + 1])
    end
    rows[#rows + 1] = table.concat(bytes)
  end
  local ihdr = u32(width) .. u32(height) .. string.char(8, 0, 0, 0, 0)
  return "\137PNG\r\n\26\n" .. chunk("IHDR", ihdr)
    .. chunk("IDAT", storedZlib(table.concat(rows))) .. chunk("IEND", "")
end

return PNG
```

- [ ] **Step 4: Run to verify pass**

Run: `luajit tests/run.lua`
Expected: all `png:` tests PASS. (`Wikipedia` adler32 is `0x11E60398`; `123456789` CRC is `0xCBF43926`.)

- [ ] **Step 5: Commit**

```bash
git add lib/png.lua tests/png_test.lua
git commit -m "Add grayscale PNG encoder"
```

---

### Task 6: Animation decoder

**Files:**
- Create: `lib/anim.lua`
- Test: `tests/anim_test.lua`

**Interfaces:**
- Consumes: `Rom` (`rom:u8`, `rom:u16`, `rom:banked`, `rom.raw`), `LZ.decompress`, `Pic.compose`, `Pic.identityMap`, `addresses`.
- Produces (module `Anim`):
  - `Anim.ORDER = "columns"`, `Anim.ORDER_BACK = "columns"` (confirmed or flipped in Task 7).
  - `Anim.dimensions(rom, dex) -> size` (5, 6 or 7 tiles per side).
  - `Anim.readFront(rom, dex) -> data` and `Anim.readBack(rom, dex) -> data` (decompressed byte arrays).
  - `Anim.script(rom, dex) -> rows` where `rows[i] = { command, arg }`.
  - `Anim.timeline(rows) -> { { frame = n, ticks = n }, ... }` (repeat commands expanded; `ticks` is 1..256; a stored 0 means 256).
  - `Anim.frameMap(rom, dex, size, frame) -> map` (`frame` 0 is the resting pic).
  - `Anim.decode(rom, dex) -> { size, frames = { [index] = pixels }, timeline, back = pixels, width }`.

Format facts (pret/pokecrystal): pic pointer rows are 6 bytes per species, `bank-0x36, lo, hi` for the front then the back. The decompressed front sheet starts with the resting `size*size` tiles and carries extra tiles after them. The script is two-byte rows `{command, arg}` ending at a row whose first byte is `0xFF`; `0xFE n` sets a repeat counter and `0xFD k` jumps back to row index `k` while the counter is above zero after decrementing. Frame `f >= 1` has a record `{ bitmaskIndex, tileId... }` reached through the per-species frame table; each set bit `i` in the bitmask replaces tile position `i` with the next tile id. Bitmask bytes per pic: 4, 5, 7 for sizes 5, 6, 7.

- [ ] **Step 1: Write the failing tests** (synthetic first, then ROM-backed)

```lua
package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local Anim = H.need("anim")
local Rom = H.need("rom")

H.test("anim: timeline with no repeats", function()
  local t = Anim.timeline({ { 1, 5 }, { 2, 8 }, { 0, 3 } })
  H.eq(#t, 3)
  H.eq(t[1].frame, 1); H.eq(t[1].ticks, 5)
  H.eq(t[3].frame, 0); H.eq(t[3].ticks, 3)
end)

H.test("anim: zero duration means 256 ticks", function()
  H.eq(Anim.timeline({ { 1, 0 } })[1].ticks, 256)
end)

H.test("anim: setrepeat/dorepeat loops the body n-1 more times", function()
  -- setrepeat 3; frame 1; frame 2; dorepeat back to row index 1
  local rows = { { 0xFE, 3 }, { 1, 4 }, { 2, 4 }, { 0xFD, 1 } }
  local t = Anim.timeline(rows)
  local seq = {}
  for _, e in ipairs(t) do seq[#seq + 1] = e.frame end
  -- first pass, then two more passes: 1 2 1 2 1 2
  H.arrayEq(seq, { 1, 2, 1, 2, 1, 2 })
end)

H.test("anim: dorepeat with no counter falls through", function()
  local t = Anim.timeline({ { 1, 4 }, { 0xFD, 0 }, { 2, 4 } })
  H.eq(#t, 2)
end)

local raw = H.rom()
if not raw then
  H.skip("anim: real ROM checks", "no ROM found (set CRYSTAL_ROM)")
else
  local rom = Rom.new(raw)

  H.test("anim: every Kanto species has a 5, 6 or 7 tile pic", function()
    for dex = 1, 151 do
      local size = Anim.dimensions(rom, dex)
      H.eq(size >= 5 and size <= 7, true, "dex " .. dex)
    end
  end)

  H.test("anim: every back pic is 6x6 tiles", function()
    for dex = 1, 151 do
      H.eq(#Anim.readBack(rom, dex), 36 * 16, "dex " .. dex)
    end
  end)

  H.test("anim: front sheet holds the resting pic plus extra tiles", function()
    for dex = 1, 151 do
      local size = Anim.dimensions(rom, dex)
      local data = Anim.readFront(rom, dex)
      H.eq(#data % 16, 0, "dex " .. dex .. " whole tiles")
      H.eq(#data >= size * size * 16, true, "dex " .. dex .. " has resting pic")
    end
  end)

  H.test("anim: every tile id a frame names exists in the sheet", function()
    for dex = 1, 151 do
      local size = Anim.dimensions(rom, dex)
      local tiles = #Anim.readFront(rom, dex) / 16
      local seen = {}
      for _, e in ipairs(Anim.timeline(Anim.script(rom, dex))) do
        if not seen[e.frame] then
          seen[e.frame] = true
          for _, id in ipairs(Anim.frameMap(rom, dex, size, e.frame)) do
            H.eq(id < tiles, true, ("dex %d frame %d tile %d"):format(dex, e.frame, id))
          end
        end
      end
    end
  end)

  H.test("anim: Pikachu decodes to a non-trivial timeline", function()
    local r = Anim.decode(rom, 25)
    H.eq(#r.timeline > 1, true, "more than one step")
    H.eq(r.width, r.size * 8)
    H.eq(#r.frames[0], r.width * r.width)
    H.eq(#r.back, 48 * 48)
  end)

  H.test("anim: all 151 species decode", function()
    for dex = 1, 151 do
      local ok, err = pcall(Anim.decode, rom, dex)
      H.eq(ok, true, "dex " .. dex .. ": " .. tostring(err))
    end
  end)
end
```

- [ ] **Step 2: Run to verify failure**

Run: `luajit tests/run.lua`
Expected: `lib/anim.lua` missing.

- [ ] **Step 3: Write `lib/anim.lua`**

```lua
local need = ...
local LZ = need("lz")
local Pic = need("pic")
local A = need("addresses")

local Anim = {}

-- Tile storage order of the decompressed sheets.  Confirmed visually in the
-- dump step; flip here if a species comes out scrambled.
Anim.ORDER = "columns"
Anim.ORDER_BACK = "columns"

local MASK_BYTES = { [5] = 4, [6] = 5, [7] = 7 }

function Anim.dimensions(rom, dex)
  local base = rom:banked(A.baseData.bank, A.baseData.addr)
  local b = rom:u8(base + (dex - 1) * 32 + A.baseDataDimensionsOffset)
  local w, h = b % 16, math.floor(b / 16)
  assert(w == h and MASK_BYTES[w],
    ("dex %d: unexpected pic dimension byte 0x%02X"):format(dex, b))
  return w
end

local function picOffset(rom, dex, back)
  local row = rom:banked(A.picPointers.bank, A.picPointers.addr)
    + (dex - 1) * 6 + (back and 3 or 0)
  return rom:banked(rom:u8(row) + A.picBankBias, rom:u16(row + 1))
end

function Anim.readFront(rom, dex)
  return (LZ.decompress(rom.raw, picOffset(rom, dex, false) + 1))
end

function Anim.readBack(rom, dex)
  return (LZ.decompress(rom.raw, picOffset(rom, dex, true) + 1))
end

function Anim.script(rom, dex)
  local ptr = rom:u16(rom:banked(A.animPointers.bank, A.animPointers.addr)
    + (dex - 1) * 2)
  local off = rom:banked(A.animPointers.bank, ptr)
  local rows = {}
  for _ = 1, 256 do
    local command = rom:u8(off)
    if command == 0xFF then break end
    rows[#rows + 1] = { command, rom:u8(off + 1) }
    off = off + 2
  end
  return rows
end

function Anim.timeline(rows)
  local out, pc, counter, guard = {}, 1, 0, 0
  while rows[pc] and guard < 4096 do
    guard = guard + 1
    local row = rows[pc]
    pc = pc + 1
    if row[1] == 0xFE then
      counter = row[2]
    elseif row[1] == 0xFD then
      if counter > 0 then
        counter = counter - 1
        if counter > 0 then pc = row[2] + 1 end
      end
    else
      out[#out + 1] = { frame = row[1], ticks = row[2] == 0 and 256 or row[2] }
    end
  end
  return out
end

function Anim.frameMap(rom, dex, size, frame)
  if frame == 0 then return Pic.identityMap(size) end
  local fp = A.framesPointers
  local perSpecies = rom:banked(A.kantoFramesBank,
    rom:u16(rom:banked(fp.bank, fp.addr) + (dex - 1) * 2))
  local record = rom:banked(A.kantoFramesBank,
    rom:u16(perSpecies + (frame - 1) * 2))
  local maskIndex = rom:u8(record)
  record = record + 1

  local bp = A.bitmaskPointers
  local maskBase = rom:banked(bp.bank,
    rom:u16(rom:banked(bp.bank, bp.addr) + (dex - 1) * 2))
  local mask = maskBase + maskIndex * MASK_BYTES[size]

  local map = Pic.identityMap(size)
  for i = 0, size * size - 1 do
    local byte = rom:u8(mask + math.floor(i / 8))
    if math.floor(byte / 2 ^ (i % 8)) % 2 == 1 then
      map[i + 1] = rom:u8(record)
      record = record + 1
    end
  end
  return map
end

function Anim.decode(rom, dex)
  local size = Anim.dimensions(rom, dex)
  local sheet = Anim.readFront(rom, dex)
  assert(#sheet % 16 == 0 and #sheet >= size * size * 16,
    ("dex %d: front sheet has %d bytes"):format(dex, #sheet))

  local timeline = Anim.timeline(Anim.script(rom, dex))
  local frames = {}
  local function render(f)
    local px = Pic.compose(sheet, Anim.frameMap(rom, dex, size, f), size, Anim.ORDER)
    return px
  end
  frames[0] = render(0)
  for _, step in ipairs(timeline) do
    if not frames[step.frame] then frames[step.frame] = render(step.frame) end
  end

  local back = Anim.readBack(rom, dex)
  assert(#back == 36 * 16, ("dex %d: back pic has %d bytes"):format(dex, #back))
  local backPixels = Pic.compose(back, Pic.identityMap(6), 6, Anim.ORDER_BACK)

  return { size = size, width = size * 8, frames = frames,
           timeline = timeline, back = backPixels }
end

return Anim
```

- [ ] **Step 4: Run to verify pass**

Run: `luajit tests/run.lua`
Expected: synthetic tests PASS. ROM tests PASS or, if a structural assertion fails, stop: a failing `every tile id` or `dimensions` test means an address or layout fact is wrong, and Task 7 must not start until it is fixed.

- [ ] **Step 5: Commit**

```bash
git add lib/anim.lua tests/anim_test.lua
git commit -m "Add animation decoder"
```

---

### Task 7: Visual gate (decision checkpoint)

The test suite cannot see pixels, and tile order is the one fact the structural tests cannot confirm. This task exists to look at real output before anything is built on it.

**Files:**
- Create: `tools/dump.lua`

**Interfaces:**
- Produces: `luajit tools/dump.lua <dex> <outdir> [--scale N] [--front-order rows|columns] [--back-order rows|columns]` writes `<dex>_back.png` and `<dex>_f<frame>.png` for every frame in the timeline, nearest-neighbour upscaled by `N` (default 4).

- [ ] **Step 1: Write `tools/dump.lua`**

```lua
package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local Rom = H.need("rom")
local Anim = H.need("anim")
local PNG = H.need("png")

local dex = tonumber(arg[1]) or 25
local outdir = arg[2] or "out"
local scale = 4
for i = 3, #arg do
  if arg[i] == "--scale" then scale = tonumber(arg[i + 1]) end
  if arg[i] == "--front-order" then Anim.ORDER = arg[i + 1] end
  if arg[i] == "--back-order" then Anim.ORDER_BACK = arg[i + 1] end
end

local raw = assert(H.rom(), "no ROM: set CRYSTAL_ROM")
local r = Anim.decode(Rom.new(raw), dex)

local function upscale(px, w)
  local out, ow = {}, w * scale
  for y = 0, w * scale - 1 do
    for x = 0, ow - 1 do
      out[y * ow + x + 1] = px[math.floor(y / scale) * w + math.floor(x / scale) + 1]
    end
  end
  return out, ow
end

local function write(name, px, w)
  local big, bw = upscale(px, w)
  local f = assert(io.open(outdir .. "/" .. name, "wb"))
  f:write(PNG.encodeGray(big, bw, bw, { 255, 170, 85, 0 }))
  f:close()
  print("wrote " .. name)
end

os.execute('mkdir "' .. outdir .. '" 2>nul')
write(("%03d_back.png"):format(dex), r.back, 48)
for frame, px in pairs(r.frames) do
  write(("%03d_f%d.png"):format(dex, frame), px, r.width)
end
```

- [ ] **Step 2: Dump Pikachu, Charizard and Mewtwo with the defaults**

Run:
```bash
luajit tools/dump.lua 25 out
luajit tools/dump.lua 6 out
luajit tools/dump.lua 150 out
```
Expected: PNG files in `out/`, no errors.

- [ ] **Step 3: Look at them**

Open `out/025_f0.png`, `out/025_f1.png` (or whichever frames were written) and `out/025_back.png` with the Read tool, and the same for 6 and 150. Decision table:

| What you see | Action |
|---|---|
| Front is a recognisable Pikachu; animation frames differ only slightly (ear/tail/body shift) | Front order is right |
| Front is scrambled, tiles transposed, or looks like diagonal stripes | Re-run with `--front-order rows`; if that looks right, set `Anim.ORDER = "rows"` in `lib/anim.lua` |
| Back is a recognisable back view (Pikachu from behind) | Back order is right |
| Back is scrambled | Re-run with `--back-order rows`; set `Anim.ORDER_BACK = "rows"` if that is right |
| Animation frames show shifted, torn or black blocks | The bitmask bit order or frame record is wrong: re-check `Anim.frameMap` against the format notes in Task 6 before continuing |
| Colours inverted (dark where light should be) | Not expected: index 0 is white, 3 is black. Stop and investigate `Pic.tilePixels` bit order |

- [ ] **Step 4: Record the verdict** in the plan file under this task (one line per confirmed order and the species viewed), apply any `Anim.ORDER` change, and re-run `luajit tests/run.lua`.

- [ ] **Step 5: Commit**

```bash
git add tools/dump.lua lib/anim.lua docs/superpowers/plans/2026-09-30-crystal-animated-sprites.md
git commit -m "Add dump tool and confirm tile order against real output"
```

**Checkpoint:** do not start Task 8 until the front and back of three species look right. If they cannot be made to look right, the format facts are wrong; stop and report rather than building on them.

---

### Task 8: Cache and background decode job

**Files:**
- Create: `lib/cache.lua`, `jobs/decode.lua`
- Test: `tests/cache_test.lua`, `tests/job_test.lua`

**Interfaces:**
- Produces (module `Cache`, pure, over an injected `store` with `write(key, bytes) -> ok, err`, `read(key) -> bytes|nil`, `info(key) -> table|nil`, `delete(key)`):
  - `Cache.FORMAT = 1`
  - `Cache.stamp(rom) -> string` from the cartridge header: `"f" .. FORMAT .. "-" .. hex(global checksum bytes at 0x14E, 0x14F) .. "-" .. hex(version byte at 0x14C)`
  - `Cache.new(store, stamp, modId) -> cache`
  - `cache:valid() -> boolean` (the stored `stamp` key equals the stamp)
  - `cache:begin()` writes the stamp
  - `cache:put(dex, result) -> ok, err` writes each frame PNG, the back PNG, then `meta` last
  - `cache:meta(dex) -> { size, timeline, frames } | nil`
  - `cache:framePath(dex, index) -> "mod_cache/<modId>/<stamp>/front/<dex>/<index>.png"`, `cache:backPath(dex) -> ".../back/<dex>.png"`
- Produces (job `jobs/decode.lua`): argument `{ rom = string, libs = { [name] = source }, first, last }`; returns `{ species = { [dex] = { size, timeline, frames = { [index] = pngString }, back = pngString } }, errors = { [dex] = message } }`. One species failing never stops the rest.

- [ ] **Step 1: Write `tests/cache_test.lua`**

```lua
package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local Cache = H.need("cache")

local function fakeStore(limit)
  local files, s = {}, {}
  function s.write(key, bytes)
    if limit and #bytes > limit then return nil, "too large" end
    files[key] = bytes
    return true
  end
  function s.read(key) return files[key] end
  function s.info(key) return files[key] and { size = #files[key] } or nil end
  function s.delete(key) files[key] = nil end
  s.files = files
  return s
end

local result = {
  size = 6,
  timeline = { { frame = 1, ticks = 5 }, { frame = 0, ticks = 12 } },
  frames = { [0] = "PNG0", [1] = "PNG1" },
  back = "PNGB",
}

H.test("cache: stamp comes from the header checksum and version", function()
  local rom = { raw = string.rep("\0", 0x14C) .. "\1\0\xAB\xCD" }
  rom.u8 = function(self, o) return self.raw:byte(o + 1) end
  H.eq(Cache.stamp(rom), "f1-abcd-01")
end)

H.test("cache: fresh store is not valid until begun", function()
  local c = Cache.new(fakeStore(), "s1", "m")
  H.eq(c:valid(), false)
  c:begin()
  H.eq(c:valid(), true)
end)

H.test("cache: a different stamp is not valid", function()
  local store = fakeStore()
  Cache.new(store, "s1", "m"):begin()
  H.eq(Cache.new(store, "s2", "m"):valid(), false)
end)

H.test("cache: put then meta round-trips", function()
  local c = Cache.new(fakeStore(), "s1", "m")
  c:begin()
  H.eq(c:meta(25), nil, "absent before put")
  H.eq(c:put(25, result), true)
  local m = c:meta(25)
  H.eq(m.size, 6)
  H.eq(#m.timeline, 2)
  H.eq(m.timeline[1].frame, 1); H.eq(m.timeline[1].ticks, 5)
  H.eq(m.frames[0], true); H.eq(m.frames[1], true)
  H.eq(c:framePath(25, 1), "mod_cache/m/s1/front/025/1.png")
  H.eq(c:backPath(25), "mod_cache/m/s1/back/025.png")
end)

H.test("cache: meta is written last, so a failed write leaves no entry", function()
  local store = fakeStore(5)            -- rejects anything over 5 bytes
  local c = Cache.new(store, "s1", "m")
  c:begin()
  local big = { size = 6, timeline = {}, frames = { [0] = "TOO LARGE" }, back = "B" }
  local ok, err = c:put(1, big)
  H.eq(ok, false)
  H.eq(type(err), "string")
  H.eq(c:meta(1), nil, "no meta after a failed put")
end)
```

- [ ] **Step 2: Run to verify failure**, then write `lib/cache.lua`

Expected before: `lib/cache.lua` missing.

```lua
local Cache = {}
Cache.__index = Cache
Cache.FORMAT = 1

function Cache.stamp(rom)
  return ("f%d-%02x%02x-%02x"):format(Cache.FORMAT, rom:u8(0x14E), rom:u8(0x14F),
    rom:u8(0x14C))
end

function Cache.new(store, stamp, modId)
  return setmetatable({ store = store, stamp = stamp, modId = modId, memo = {} }, Cache)
end

function Cache:key(rest) return self.stamp .. "/" .. rest end

function Cache:valid()
  return self.store.read("stamp") == self.stamp
end

function Cache:begin()
  return self.store.write("stamp", self.stamp)
end

function Cache:framePath(dex, index)
  return ("mod_cache/%s/%s/front/%03d/%d.png"):format(self.modId, self.stamp, dex, index)
end

function Cache:backPath(dex)
  return ("mod_cache/%s/%s/back/%03d.png"):format(self.modId, self.stamp, dex)
end

local function encodeMeta(result, frameIndexes)
  local steps = {}
  for _, s in ipairs(result.timeline) do steps[#steps + 1] = s.frame .. ":" .. s.ticks end
  return ("size=%d\nframes=%s\ntimeline=%s\n"):format(result.size,
    table.concat(frameIndexes, ","), table.concat(steps, ","))
end

local function decodeMeta(text)
  local size = tonumber(text:match("size=(%d+)"))
  if not size then return nil end
  local meta = { size = size, frames = {}, timeline = {} }
  for n in (text:match("frames=([%d,]*)") or ""):gmatch("%d+") do
    meta.frames[tonumber(n)] = true
  end
  for frame, ticks in (text:match("timeline=([%d:,]*)") or ""):gmatch("(%d+):(%d+)") do
    meta.timeline[#meta.timeline + 1] = { frame = tonumber(frame), ticks = tonumber(ticks) }
  end
  return meta
end

function Cache:put(dex, result)
  local indexes = {}
  for index in pairs(result.frames) do indexes[#indexes + 1] = index end
  table.sort(indexes)
  for _, index in ipairs(indexes) do
    local ok, err = self.store.write(self:key(("front/%03d/%d.png"):format(dex, index)),
      result.frames[index])
    if not ok then return false, tostring(err) end
  end
  local ok, err = self.store.write(self:key(("back/%03d.png"):format(dex)), result.back)
  if not ok then return false, tostring(err) end
  ok, err = self.store.write(self:key(("meta/%03d"):format(dex)), encodeMeta(result, indexes))
  if not ok then return false, tostring(err) end
  self.memo[dex] = nil
  return true
end

function Cache:meta(dex)
  local hit = self.memo[dex]
  if hit ~= nil then return hit or nil end
  local text = self.store.read(self:key(("meta/%03d"):format(dex)))
  local meta = text and decodeMeta(text) or nil
  self.memo[dex] = meta or false
  return meta
end

return Cache
```

Note: `mod.cache:write` keys are relative to `mod_cache/<id>/`, which is why `key()` omits the prefix that `framePath` includes.

- [ ] **Step 3: Run to verify the cache tests pass**

Run: `luajit tests/run.lua`
Expected: all `cache:` tests PASS.

- [ ] **Step 4: Write `tests/job_test.lua`** (runs the job script the way the engine will: libs as strings, no `require`)

```lua
package.path = "./?.lua;" .. package.path
local H = require("tests.harness")

local function readFile(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

local function runJob(arg)
  local chunk = assert(loadstring(readFile("jobs/decode.lua"), "@jobs/decode.lua"))
  -- a sandbox-like environment: no require, no io, no os
  local env = { assert = assert, pcall = pcall, tostring = tostring, type = type,
    pairs = pairs, ipairs = ipairs, load = load, loadstring = loadstring,
    setfenv = setfenv, string = string, table = table, math = math, bit = bit,
    select = select, error = error, unpack = unpack, setmetatable = setmetatable }
  setfenv(chunk, env)
  return chunk(arg)
end

local function libs()
  local out = {}
  for _, n in ipairs({ "lz", "rom", "addresses", "pic", "png", "anim" }) do
    out[n] = readFile("lib/" .. n .. ".lua")
  end
  return out
end

local raw = H.rom()
if not raw then
  H.skip("job: decode batches", "no ROM found (set CRYSTAL_ROM)")
else
  H.test("job: decodes a batch and returns PNG strings", function()
    local r = runJob({ rom = raw, libs = libs(), first = 24, last = 26 })
    H.eq(next(r.errors), nil, "no errors")
    for dex = 24, 26 do
      local s = assert(r.species[dex], "species " .. dex)
      H.eq(s.back:sub(2, 4), "PNG")
      H.eq(s.frames[0]:sub(2, 4), "PNG")
      H.eq(#s.timeline > 0, true)
    end
  end)

  H.test("job: one bad species does not stop the batch", function()
    -- Corrupt species 25's pic pointer row so decode raises for it alone.
    local bad = raw
    local off = 0x48 * 0x4000 + (25 - 1) * 6
    bad = bad:sub(1, off) .. string.rep("\255", 6) .. bad:sub(off + 7)
    local r = runJob({ rom = bad, libs = libs(), first = 24, last = 26 })
    H.eq(type(r.errors[25]), "string", "species 25 reports an error")
    H.eq(r.species[25], nil)
    H.eq(r.species[24] ~= nil and r.species[26] ~= nil, true, "neighbours decode")
  end)
end
```

- [ ] **Step 5: Run to verify failure**, then write `jobs/decode.lua`

Expected before: `jobs/decode.lua` missing.

```lua
-- Runs in a background job: no `mod`, no `require`.  The libraries arrive as
-- source strings in the argument and are loaded here.
local arg = ...

local loaded = {}
local function need(name)
  if not loaded[name] then
    local chunk = assert(load(arg.libs[name], "=" .. name))
    loaded[name] = chunk(need)
  end
  return loaded[name]
end

local Rom, Anim, PNG = need("rom"), need("anim"), need("png")
local SHADES = { 255, 170, 85, 0 }
local rom = Rom.new(arg.rom)

local species, errors = {}, {}
for dex = arg.first, arg.last do
  local ok, res = pcall(function()
    local r = Anim.decode(rom, dex)
    local frames = {}
    for index, px in pairs(r.frames) do
      frames[index] = PNG.encodeGray(px, r.width, r.width, SHADES)
    end
    return {
      size = r.size,
      timeline = r.timeline,
      frames = frames,
      back = PNG.encodeGray(r.back, 48, 48, SHADES),
    }
  end)
  if ok then species[dex] = res else errors[dex] = tostring(res) end
end

return { species = species, errors = errors }
```

`lib/png.lua` and `lib/anim.lua` both take `need` as a vararg, and `lib/rom.lua`, `lib/lz.lua`, `lib/pic.lua`, `lib/addresses.lua` ignore it, so one loader serves all of them.

- [ ] **Step 6: Run to verify pass**

Run: `luajit tests/run.lua`
Expected: `job:` tests PASS. Note the time a 3-species batch takes (`time luajit tests/run.lua`); Task 9 uses it to size batches.

- [ ] **Step 7: Measure a full decode** to size the batches

Run: `luajit -e "package.path='./?.lua;'..package.path; local H=require('tests.harness'); local Rom=H.need('rom'); local Anim=H.need('anim'); local PNG=H.need('png'); local rom=Rom.new(H.rom()); local t=os.clock(); for d=1,151 do local r=Anim.decode(rom,d); for _,px in pairs(r.frames) do PNG.encodeGray(px,r.width,r.width,{255,170,85,0}) end end; print('seconds', os.clock()-t)"`
Expected: a number. If it is under about 8 seconds, batches of 25 species fit comfortably inside the default 5-second job budget only if each batch stays under it, so use `maxSeconds = 30` and 25-species batches regardless. Record the number in the commit message.

- [ ] **Step 8: Commit**

```bash
git add lib/cache.lua jobs/decode.lua tests/cache_test.lua tests/job_test.lua
git commit -m "Add frame cache and background decode job"
```

---

### Task 9: Playback maths and mod entry (decode orchestration, hook, options)

**Files:**
- Create: `lib/playback.lua`, `main.lua`
- Test: `tests/playback_test.lua`

**Interfaces:**
- Produces (`Playback`, pure): `Playback.TICKS_PER_SECOND = 60`, `Playback.REST_SECONDS = 2`, `Playback.frameAt(timeline, seconds) -> frameIndex`. The timeline plays from 0; after the last step the resting frame `0` holds for `REST_SECONDS`, then the loop restarts. An empty timeline returns 0. Negative time returns 0.
- Consumes: `Cache`, the job contract from Task 8, `mod.imports`, `mod.cache`, `mod.job`, `mod.options`, `mod.hooks`, `mod.log`.

Crystal itself plays the animation once when the mon appears. Looping with a rest is the behaviour the earlier mods had and what the user described as "animated sprites"; both constants are one-line changes if the preference differs.

- [ ] **Step 1: Write `tests/playback_test.lua`**

```lua
package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local P = H.need("playback")

local tl = { { frame = 1, ticks = 30 }, { frame = 2, ticks = 60 } } -- 0.5s, 1s

H.test("playback: steps by elapsed time", function()
  H.eq(P.frameAt(tl, 0), 1)
  H.eq(P.frameAt(tl, 0.49), 1)
  H.eq(P.frameAt(tl, 0.51), 2)
  H.eq(P.frameAt(tl, 1.49), 2)
end)

H.test("playback: rests on frame 0 then loops", function()
  H.eq(P.frameAt(tl, 1.6), 0)
  H.eq(P.frameAt(tl, 3.49), 0)
  H.eq(P.frameAt(tl, 3.51), 1) -- 1.5s animation + 2s rest = 3.5s cycle
end)

H.test("playback: empty timeline and bad time are safe", function()
  H.eq(P.frameAt({}, 5), 0)
  H.eq(P.frameAt(tl, -1), 0)
  H.eq(P.frameAt(nil, 1), 0)
end)
```

- [ ] **Step 2: Run to verify failure**, then write `lib/playback.lua`

```lua
local Playback = {}
Playback.TICKS_PER_SECOND = 60
Playback.REST_SECONDS = 2

function Playback.frameAt(timeline, seconds)
  if not timeline or #timeline == 0 or not seconds or seconds < 0 then return 0 end
  local total = 0
  for _, step in ipairs(timeline) do total = total + step.ticks / Playback.TICKS_PER_SECOND end
  local t = seconds % (total + Playback.REST_SECONDS)
  if t >= total then return 0 end
  local acc = 0
  for _, step in ipairs(timeline) do
    acc = acc + step.ticks / Playback.TICKS_PER_SECOND
    if t < acc then return step.frame end
  end
  return 0
end

return Playback
```

- [ ] **Step 3: Run to verify pass**

Run: `luajit tests/run.lua`
Expected: `playback:` tests PASS.

- [ ] **Step 4: Write `main.lua`** (decode orchestration and the sprite hook; the per-frame swap is Task 10)

```lua
-- Crystal's animated front sprites in Red/Blue/Yellow, decoded from the
-- player's own Crystal ROM.  See docs/superpowers/specs/.
return function(mod)
  local MOD_ID = "crystal_animated_sprites"
  local LIBS = { "lz", "rom", "addresses", "pic", "png", "anim", "cache", "playback" }
  local BATCH, LAST = 25, 151

  local function sibling(name)
    local source = mod:read(name)
    if not source then
      mod.log:error("%s missing from %s -- reinstall the mod", name, mod.path)
      return nil
    end
    return source
  end

  -- Library sources, loaded through the same `need` convention the tests and
  -- the job use.
  local sources = {}
  for _, name in ipairs(LIBS) do
    sources[name] = sibling("lib/" .. name .. ".lua")
    if not sources[name] then return end
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

  local Rom, Cache, Playback = need("rom"), need("cache"), need("playback")

  local romBytes, err = mod.imports:read("crystal_rom", 0, 2097152)
  if not romBytes then
    mod.log:error("could not read the Crystal import: %s", tostring(err))
    return
  end
  local rom = Rom.new(romBytes)
  local cache = Cache.new(mod.cache, Cache.stamp(rom), MOD_ID)

  ---------------------------------------------------------------------------
  -- Decode, once per cache stamp, in batches.  Species that are not cached yet
  -- simply keep the vanilla sprite.
  ---------------------------------------------------------------------------
  local state = { next = 1, job = nil, failed = {}, writeFailed = false }

  local function startBatch()
    if state.job or state.next > LAST then return end
    local last = math.min(state.next + BATCH - 1, LAST)
    local libSources = {}
    for _, name in ipairs({ "lz", "rom", "addresses", "pic", "png", "anim" }) do
      libSources[name] = sources[name]
    end
    local handle, reason = mod.job:run("jobs/decode.lua",
      { rom = romBytes, libs = libSources, first = state.next, last = last },
      { maxSeconds = 30 })
    if not handle then
      mod.log:warn("decode job not started: %s", tostring(reason))
      return
    end
    state.job, state.jobFirst, state.jobLast = handle, state.next, last
  end

  local function pollJob()
    if not state.job then return end
    local r = mod.job:poll(state.job)
    if r.status == "pending" then return end
    local first, last = state.jobFirst, state.jobLast
    mod.job:release(state.job)
    state.job = nil
    if r.status ~= "ok" then
      mod.log:error("decode job for species %d-%d failed: %s", first, last, tostring(r.err))
      for dex = first, last do state.failed[dex] = true end
    else
      for dex, message in pairs(r.result.errors) do
        state.failed[dex] = true
        mod.log:warn("species %d not decoded: %s", dex, message)
      end
      for dex, result in pairs(r.result.species) do
        local ok, werr = cache:put(dex, result)
        if not ok then
          state.failed[dex] = true
          if not state.writeFailed then
            state.writeFailed = true
            mod.log:error("cache write failed (species %d): %s", dex, tostring(werr))
          end
        end
      end
    end
    state.next = last + 1
    startBatch()
  end

  if cache:valid() then
    -- Anything not yet written (an interrupted first boot) is re-decoded.
    while state.next <= LAST and cache:meta(state.next) do state.next = state.next + 1 end
  else
    cache:begin()
  end
  startBatch()

  ---------------------------------------------------------------------------
  -- Options, hook
  ---------------------------------------------------------------------------
  local rows = sibling("options.lua")
  if rows then
    local chunk = load(rows, "@" .. mod.path .. "/options.lua")
    if chunk then mod.options:define(chunk()) end
  end

  local function ready(dex)
    return cache:meta(dex) ~= nil and not state.failed[dex]
  end

  local seconds = 0
  local function now() return seconds end

  -- Species ids are the engine's own names; map them to national dex numbers
  -- (Gen 1 species 1..151 share Crystal's numbering once the engine's internal
  -- index order is translated).  Resolved in Task 10.
  local function dexOf(speciesName)
    return mod.dexNumber and mod.dexNumber(speciesName) or nil
  end

  mod.hooks:wrap("pokemon.sprite", function(next, originalPath, ctx)
    local dex = ctx and dexOf(ctx.species)
    if not dex or not ready(dex) then return next(originalPath, ctx) end
    if ctx.side == "back" then
      if mod.options:get("back_sprites") == "front" then
        return cache:framePath(dex, Playback.frameAt(cache:meta(dex).timeline, now()))
      end
      return cache:backPath(dex)
    end
    return cache:framePath(dex, Playback.frameAt(cache:meta(dex).timeline, now()))
  end, 930)

  mod.__cas = { cache = cache, pollJob = pollJob, now = now,
    advance = function(dt) seconds = seconds + dt end, ready = ready }
end
```

`mod.dexNumber` and the `seconds` clock are placeholders for engine facts Task 10 establishes (how a species name maps to a national dex number, and where a per-frame tick comes from). `main.lua` is not complete until Task 10 replaces them; do not commit Task 9 alone as a finished feature.

- [ ] **Step 5: Commit**

```bash
git add lib/playback.lua main.lua tests/playback_test.lua
git commit -m "Add playback timing and mod entry with decode orchestration"
```

---

### Task 10: Gen 1 engine seam (investigation, then integration)

This task resolves the three facts `main.lua` still assumes. It starts with read-only investigation in `C:/g2dev`, because `game/` is stale and the answers differ there.

**Files:**
- Modify: `main.lua`
- Create: `tests/engine_load_test.lua` (run from `C:/g2dev`)

- [ ] **Step 1: Species name to dex number.** Find how Gen 1 species ids relate to national dex numbers.

Run (from `C:/g2dev`): `grep -rn "dexNumber\|dexNo\|\.dex\b" src/pokemon/*.lua | head -20` and read how `data.pokemon[species]` records carry a dex number (`sed -n 1,60p src/pokemon/Pokedex.lua` if present). Write the mapping into `main.lua` `dexOf`, reading `ctx.data.pokemon[ctx.species].dex` (or the field you find). Species outside 1..151 return `nil` so they keep the engine's path.

- [ ] **Step 2: A per-frame tick.** Find a hook or event that runs every frame during a battle.

Run: `grep -rn "battle.overlay" src --include=*.lua | head` and read the call site. The earlier sprite mods used `mod.hooks:wrap("battle.overlay", function(next, screen) ... end)`, which receives the live battle screen each draw. Use it as the clock (`seconds = love.timer.getTime()`) and as the place to call `pollJob()`.

- [ ] **Step 3: Frame swap seam.** In Gen 1, `BattleState` resolves `battler.sprite` once through the local `getImage(path, palette, trueColor)` (`src/battle/BattleState.lua:266`), so returning a new path from the hook changes nothing after send-out. Read `BattleState:picImage` (`:511`), `imageMeta` (`:266-300`) and `BattleState:drawPicsLayer` (`:6665`), then choose:

| Finding | Approach |
|---|---|
| `battle.overlay` runs before pics are drawn and `self.enemy.sprite` can be reassigned safely | Wrap `battle.overlay`: compute the frame path, build the image with the engine's own `Assets.imageData(path)` plus the same palette `mapPixel` the engine applies, cache it per path, assign `screen.enemy.sprite = image` |
| The overlay runs after pics are drawn | Wrap `BattleState.drawPicsLayer` through `require("src.battle.BattleState")` (permission `engine_internals`) and swap before calling `next` |
| No safe seam exists | Stop. Propose a small upstream change exporting `BattleState.getImage` so a mod can request a palette-correct image for a path. Do not patch `game/` or `g2dev` sources locally |

- [ ] **Step 4: Yield to engine effects** (Review Focus 4). Before swapping, skip the swap when any of these hold for the battler: `battler.substituteHP`, `battler.fainted`, `screen:fxFaintActive(battler)`, `screen:fxHidden(battler)`, `screen.enemyHidden`, `screen.enemySendingOut`, or `battler.transformed`. Write a test that feeds a stub battler in each state and asserts the sprite is untouched.

- [ ] **Step 5: Write `tests/engine_load_test.lua`** and run it from `C:/g2dev`

Follow the suite convention used by the other mods (`local T = require("tests.modkit")`, `T.sdk.loadMod(path, { data = Data })`; see `mods/pokebag_plus/tests/pokebag_plus_test.lua`). Assert `run.mod.state == "loaded"` (not just zero errors), that `pokemon.sprite` returns the vanilla path for a species not yet cached (Review Focus 2), and returns a `mod_cache/crystal_animated_sprites/` path once the cache holds that species.

Run (from `C:/g2dev`): `luajit mods/crystal_animated_sprites/tests/engine_load_test.lua`
Expected: PASS. A `state ~= "loaded"` failure is the real signal; read `run.errors`.

- [ ] **Step 6: Commit**

```bash
git add main.lua tests/engine_load_test.lua
git commit -m "Wire sprite hook, per-frame tick and frame swap into Gen 1 battles"
```

---

### Task 11: See it running

The suite cannot see pixels and the engine's own sprite code has bitten other mods here. This task is the real-engine check.

- [ ] **Step 1: Import the ROM and boot.** Launch `C:/g2dev/Play-Windows.bat`, enable the mod, and supply the Crystal ROM when the launcher asks. Wait for the first-boot decode (watch `mod.log` for warnings about species that failed).
- [ ] **Step 2: Fight a wild battle** against Pikachu, then a 5-tile, a 6-tile and a 7-tile species (for example Pidgey, Charmander, Onix). Confirm the enemy animates, sits bottom-aligned like vanilla, and keeps the Gen 1 palette.
- [ ] **Step 3: Check the four engine-owned states:** use Substitute, faint the foe, and Transform into a foe (Ditto). The sprite must not flicker back, resurrect a fainted mon, or ignore the substitute doll.
- [ ] **Step 4: Toggle `BACK SPRITES`** between `CRYSTAL` and `ANIMATED FRONT` and confirm the player's mon changes accordingly (mirrored front when animated).
- [ ] **Step 5: Capture evidence** (screenshot of a mid-animation frame for two species) and save it outside the repo. Record any visual defect as a follow-up task instead of patching ad hoc.
- [ ] **Step 6: Write `README.md`** (what it does, that it needs your own Crystal ROM and ships no art, the `BACK SPRITES` option, the conflicts list) and commit.

```bash
git add README.md
git commit -m "Add README"
```

---

## Self-Review

**Spec coverage.** Manifest and required import (Task 1); LZ, ROM reader, tile decode, PNG, animation decode (Tasks 2-6); visual gate for the tile-order risk the spec flags (Task 7); cache, stamp and the job (Task 8); timing, decode orchestration, hook and option (Tasks 1, 9); Gen 1 hook surface risk (Task 10); visual verification (Task 11); no Gold/Silver/Crystal boot, no shiny (global constraints). The spec's "Pikachu spike" is Task 7, pulled to follow the decoder so the decoder is what is being tested. Spec sections on error handling map to Review Focus 1, 3 and 5.

**Placeholders.** Task 9's `dexOf` and clock are deliberately provisional and Task 10 resolves them with stated investigation steps and a decision table; this is called out in both tasks. No other TBDs.

**Type consistency.** `need` convention, `Rom` methods, `Cache` API (`new`, `valid`, `begin`, `put`, `meta`, `framePath`, `backPath`), the job argument and return shape, and `Playback.frameAt` are named identically wherever used. `main.lua`'s `LIBS` includes `cache` and `playback`, which the job does not need and does not receive.

**Open risks the plan cannot close on paper:** the exact Gen 1 frame-swap seam (Task 10 decision table), whether `mod.imports:read` can return the full 2 MiB string in one call under the mod sandbox (Task 10 Step 5 exercises it), and the crystal 251 cross-check of frame counts, which is not automated because that mod ships no plain data file to diff against.
