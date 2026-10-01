# Changelog

## 0.2.2

### Added
- The DIAGNOSTICS readout now also shows what the Pokedex entry animation last saw (`DEX ON SHOWN` when it is running) and the ids of the last screens the game stacked (`SCR DexEntryMenu`). Visit a Pokedex entry, then start a battle with DIAGNOSTICS on, to read them. This is for finding out why an entry does not animate on a particular setup.

## 0.2.1

### Fixed
- The Pokedex entry animation now starts for any Pokedex entry screen the engine builds, including one that another mod wraps or replaces, instead of only the engine's own screen class. If an entry screen cannot be animated, the reason shows in the DIAGNOSTICS readout during the next battle.

## 0.2.0

### Added
- Crystal's picture now replaces the front sprite outside battle too: the status screen, the Pokedex, the evolution screen, the Hall of Fame and League PC, the title screen, Prof. Oak's intro, trades and the credits. These screens show the resting frame, except the Pokedex entry, which plays the animation.
- `tools/screen_shots.lua`, a developer tool that opens each of those screens in the real engine and screenshots it.

### Notes
- Back pictures on other screens, trainer pictures and party icons are unchanged.

## 0.1.4

### Fixed
- Gaps in the sprites, such as the space between Pidgey's feet or between a limb and the body, were painted white again by the 3D battle mods (Potato Voxel and Battle Art Voxel), which refill any see-through area they cannot trace back to the outside. Gaps that were meant to be see-through are now tagged with an alpha of 1/255, which is invisible when drawn. A voxel mod that understands the tag leaves them clear. Until those mods update, nothing changes for you: they keep filling the gaps exactly as before, and the 2D battle screen is unaffected.

## 0.1.3

### Added
- A DIAGNOSTICS option. When on, the top of the battle screen shows the mod version, the cache it is using, how many species are ready or failed, whether the background decode is running, and whether each battler's sprite comes from this mod or the game, plus the latest error. It is meant for bug reports on devices where the save folder cannot be opened, such as Android. It is off by default.

## 0.1.2

### Fixed

- White patches that were really gaps in the sprite, such as between limbs or inside a hood or tail, are now transparent instead of white. This includes poses that only appear during the animation. About 34 Pokemon are affected, among them Victreebel, Dratini, Pinsir, Dodrio and Electabuzz. The same was done for the back sprites, such as Mew, Alakazam and Victreebel. Many sprites were also touched up by hand, 74 front sprites and 91 back sprites in all, so white areas that are really gaps are see-through and white details that belong stay solid.
- The sprites are rebuilt once from your ROM the first time you run this version.

## 0.1.1

### Fixed

- Sprites no longer have a white rectangle around them. The background is now transparent, so they sit cleanly on mods that replace the battle background. The sprites are rebuilt once from your ROM the first time you run this version.
- A stray white pixel in the gap at the base of Pikachu's tail is cleared.

## 0.1.0

### Added

- Enemy Pokemon play Crystal's own battle animation in Red, Blue and Yellow, for all 151 Kanto species.
- A BACK SPRITES option. CRYSTAL (the default) shows Crystal's back sprite, and ANIMATED FRONT shows the animated front sprite, mirrored.
- The sprites are built from your own Pokemon Crystal ROM the first time the mod runs. No artwork is included.
