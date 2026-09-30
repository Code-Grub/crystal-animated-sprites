# Crystal ROM Sprites: design

Mod id: `crystal_rom_sprites`. Status: approved design, pending spec review.

## Goal

Give Gen1Recomp's Red/Blue/Yellow battles Crystal's animated front sprites,
with all art decoded at runtime from the player's own Crystal ROM. The mod
bundles no Nintendo artwork. It replaces the earlier
`crystal_animated_sprites_with_shiny_visuals`, which ships 8,658 ripped PNGs.

## Scope

**v1 (this spec):**
- Animated Crystal front sprites for species 1-151 in Gen 1 battles.
- A `BACK SPRITES` option: `CRYSTAL` (default, Crystal's static back art) or
  `ANIMATED FRONT` (the front animation, mirrored).
- Gen 1 palette handling unchanged.

**v2 (separate spec):** Crystal shiny palettes for virtual shinies
(`Stats.isShiny`), sparkle entrance, delayed enemy cry, sparkle sound.

**Non-goals:** Gold/Silver/Crystal boots, species 152-251, trainer or overworld
sprites, Crystal colour palettes for normal mons, any gameplay change.

## Constraints

- No art, and no code copied from any existing mod. Neither the original mod
  nor `gen1recomp-mod-crystal-251` carries a license. The decoder is written
  from the public pret/pokecrystal disassembly. Crystal 251 is used only to
  cross-check our output.
- Declared via `required_imports`: id `crystal_rom`, file `crystal.gbc`, size
  2097152, MD5 `9f2922b235a5eeb78d65594e82ef5dde` (UE v1.0) or
  `301899b8087289a6436b0a241fbbb474` (UE v1.1). The mod does not load without
  the ROM.
- Manifest: `api` 2, `profile` content, `games` `["gen1"]`, `conflicts` on
  `crystal_animated_sprites_with_shiny_visuals`, `crystal_animated_sprites`,
  `gen2_shiny_visuals`, `shiny_visuals`, `CRYSTAL_251`.
- Decoding must stay inside the mod sandbox: pure Lua, reads through the
  bounded `mod.imports` facade or `mod:read`, writes only under
  `mod_cache/<id>/`.

## Architecture

One unit per file, each testable alone.

| Unit | Purpose | Depends on |
|---|---|---|
| `lib/rom.lua` | Banked ROM reads (`u8`, `u16`, `bytes`, `banked(bank, addr)`); version check | import API |
| `lib/lz.lua` | Crystal LZ decompressor | none |
| `lib/pic.lua` | 2bpp tiles to pixels; front (row-major) vs back (column-first) layout | none |
| `lib/anim.lua` | Read a species' frame table, bitmask and animation script; produce ordered `{image, duration}` frames | `rom`, `lz`, `pic` |
| `lib/cache.lua` | Write and read frame strips plus a timing table; version stamp so a decoder change invalidates the cache | import API |
| `lib/species.lua` | Gen 1 species to Crystal dex index 1-151 (identical numbering) | none |
| `main.lua` | Hook registration, playback, options | all above |
| `options_screen.lua` | The `BACK SPRITES` option | main |

## Data flow

1. First load: the launcher validates the ROM by MD5. `cache` finds no stamped
   cache, so the decode job runs `anim` for species 1-151 and writes
   `mod_cache/crystal_rom_sprites/`.
2. Later loads: `cache` validates the stamp and skips decoding.
3. Battle: the `pokemon.sprite` hook (and the Gen 1 `BattleState` animation
   loop) asks for a species. `main` returns the current frame by elapsed time.
   The back slot returns Crystal's static back pic, or the mirrored front frame
   when the option says so.

Frame construction follows pokecrystal's `pic_animation.asm`: frame 0 is the
resting pic, later frames are built by applying a bitmask of replaced tiles.
The engine's `src/render/MonAnim.lua` documents the same bitmask and timing
rules and is the reference for correctness.

## Error handling

- Wrong or missing ROM: handled by the launcher's required-import gate.
- Truncated or unexpected LZ stream: abort that species, log once, fall back
  to the ROM sprite for it. One bad species never blocks the rest.
- Cache stamp mismatch or corruption: discard and re-decode.
- Decode cost on first load is a one-time cost and runs as a job, not on the
  render thread.

## Testing

- Unit tests with synthetic data: LZ (all command types), 2bpp decode, both
  pic layouts, bitmask application, timing.
- ROM-backed tests, skipped and reported (never silently passed) when no ROM
  is present: frame count, dimensions and duration sum for a fixed sample of
  species, cross-checked against Crystal 251's output.
- Visual check: render decoded frames to PNG and inspect them. The suite cannot
  see pixels.
- Load the mod in `C:/g2dev` through the test seam and assert
  `run.mod.state == "loaded"`, not just zero errors.

## First step: spike (throwaway)

Decode Pikachu (25) from the real ROM: LZ stream, frame set, and animation
script. Success means a correct strip of frames whose count and timings match
Crystal 251. This also confirms the ROM addresses for this engine build and
that the sandbox allows the read. If the sandbox cannot do it, revisit the
design before building further.

## Risks

- Sandbox limits on job runtime or memory for 151 species. Mitigation: decode
  per species lazily if the bulk job is too heavy.
- The exact Gen 1 hook surface for sprites. To be confirmed in the spike
  against `C:/g2dev`, not `game/`, which is stale (see project notes).
- Sprite sizes differ by species (5x5, 6x6, 7x7 tiles). The hook must accept
  non-standard dimensions.
