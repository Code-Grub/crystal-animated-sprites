-- Known holes, by national dex number: pixels { x, y } (from the top left of
-- the front pic) that each name a walled-in white region which is really a gap
-- in the sprite, so it should be transparent instead of white.  The matte
-- clears the whole region, but only while it is still bounded by black outline
-- alone in that frame (see Pic.matte), so a coordinate that lands on something
-- else in another animation frame is left alone.
--
-- Entries come from looking at the picture: a white eye or tongue walled in by
-- black looks the same to the code, so there is no general rule.  Each hole
-- that was removed on review has the first pixel of its region in the resting
-- pose, plus one entry for each other animation frame where the same hole has
-- a different shape (tools/review_data.lua finds those).  Decisions are in
-- tools/review_decisions.json.  The pixel is the first one of the region,
-- reading left to right, top to bottom.
return {
  [5] = { { 13, 32 } }, -- Charmeleon
  [17] = { { 24, 38 } }, -- Pidgeotto
  [24] = { { 15, 42 } }, -- Arbok
  [25] = { { 28, 26 } }, -- Pikachu
  [26] = { { 34, 20 } }, -- Raichu
  [49] = { { 14, 15 } }, -- Venomoth
  [56] = { { 10, 8 }, { 31, 23 } }, -- Mankey
  [57] = { { 13, 14 } }, -- Primeape
  [64] = { { 9, 30 } }, -- Kadabra
  [68] = { { 16, 31 } }, -- Machamp
  [71] = { { 38, 6 } }, -- Victreebel
  [73] = { { 34, 38 } }, -- Tentacruel
  [82] = { { 25, 17 } }, -- Magneton
  [83] = { { 15, 11 } }, -- Farfetch'd
  [85] = { { 26, 17 } }, -- Dodrio
  [86] = { { 24, 13 } }, -- Seel
  [99] = { { 32, 16 } }, -- Kingler
  [107] = { { 26, 31 }, { 24, 32 } }, -- Hitmonchan
  [116] = { { 25, 17 }, { 24, 18 } }, -- Horsea
  [125] = { { 36, 15 }, { 11, 16 }, { 27, 38 }, { 33, 17 }, { 36, 19 } }, -- Electabuzz
  [127] = { { 29, 49 } }, -- Pinsir
  [141] = { { 40, 21 } }, -- Kabutops
  [145] = { { 27, 15 } }, -- Zapdos
  [148] = { { 34, 30 } }, -- Dragonair
  [149] = { { 19, 3 }, { 26, 3 }, { 15, 11 } }, -- Dragonite
  [150] = { { 35, 17 }, { 24, 30 } }, -- Mewtwo
}
