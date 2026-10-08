# Shiny entrance: design

Mod id: `crystal_animated_sprites`. Status: approved by the user in
conversation on 2026-10-08, after three spikes proved the pieces below.

## Goal

When a shiny Pokemon takes the field, play Crystal's own entrance instead of
the cry and animation straight away: a ring of eight sparkles around the
picture, each with Crystal's chime, and only then the cry and the front
animation. Everything is read from the player's own Crystal ROM; nothing is
shipped.

This replaces the intro that SHINY_POKEMON draws, and does not run beside it.

## What Crystal does

`ShowSetEnemyMonAndSendOutAnimation` (engine/battle/core.asm) plays the send-out
animation, then, if the Pokemon is shiny, plays `ANIM_SEND_OUT_MON` again with
parameter 1 (the shiny animation), and only after that plays the cry and the
front-pic animation. The player's own Pokemon goes the same way.

The shiny animation (`BattleAnim_SendOutMon`, `.Shiny`, in
data/moves/animations.asm) is 60 frames:

- a screen flash and a gray/yellow palette cycle (not in the first version);
- eight sparkle objects, one every 4 frames at frames 0, 4, ... 28, on a circle
  of radius 16 pixels around the picture: sparkle `k` is at
  `(16 cos(2 pi k / 8), 16 sin(2 pi k / 8))`, `y` down, so the first is to the
  right and they go clockwise;
- `SFX_SHINE` with each one;
- a final wait of 32 frames.

Each sparkle lives 15 frames and steps through OAM sets 74, 14, 15, 14, 15
(3 frames each): a 16x16 star (tile 6 of the speed graphics mirrored four ways),
then the 8x8 sparkle (tile 0) and the smaller one (tile 1) twice. Yellow
`(31,31,7)` body, orange `(31,16,1)` tips.

## Where it comes from

All located in the player's Crystal ROM (UE v1.0 and v1.1):

- **Art:** `AnimObjGFX` entry `$11`, bank `0x21` address `0x542E`, nine
  LZ-compressed 2bpp tiles, decoded with the mod's existing `lib/lz.lua`.
- **Chime:** `Sfx_Shine_Ch5`, 27 bytes, found by signature. The engine plays it
  as a Gen 2 chip program: `{ generation = 2, chip = { blob = bytes, channels =
  {{ number = 5, address = 0x4000 }}, engine = 2 } }`, registered at load with
  `mod.content.sfx:register`. About 0.28 s, a chirp from 512 to 4096 Hz.

If the art or the chime cannot be read (a different ROM revision), the entrance
is off and the mod behaves exactly as before.

## Behaviour

- A new `SHINY ENTRANCE` option, `ON` by default. `OFF` leaves a shiny entering
  as it does today (cry and animation straight away).
- The entrance starts when the engine asks for the entrance cry
  (`BattleState:playEntranceCry`), for the enemy and for the player's own
  Pokemon, when the Pokemon is shiny (the flag, or shiny DVs, the same test the
  sprite lookup uses).
- The cry is held back until the sparkle ends: the wrapper queues a wait on a
  gate object (the queue only calls `isPlaying`, `getDuration`, `getPitch` and
  `stop` on what it waits for) and then the original cry.
- The front animation starts when the sparkle ends, because the swap's
  `landed` rule also waits for it.
- With SHINY_POKEMON loaded, the entrance switches off its `SHINY INTRO` option
  through the engine's own runtime route (loader option table plus
  `mod.options_changed`) and puts the previous value back when the entrance is
  turned off. Its colours, rolling and name sparkles are untouched.
- Sparkles are drawn in the battle overlay in game pixels, at the picture
  centres the engine draws (enemy `(124, 28)`, player `(36, 68)`), and the wide
  layout uses the same anchors SHINY_POKEMON uses.

## Not in the first version

The screen flash and the palette cycle under the sparkles; sparkles on other
screens; the Pokedex and Hall of Fame never had one.

## Testing

- `lib/sparkle.lua` is pure: the schedule, positions, frame ids, and the ROM
  decoding are unit tested, including against the real ROM.
- The engine test checks the registered chime, the option, the wrapper and the
  `landed` rule.
- Real-engine captures check the picture, the hold on the cry and animation, and
  that SHINY_POKEMON's own intro is silent while ours is on.
