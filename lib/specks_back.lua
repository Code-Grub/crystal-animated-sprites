-- Known holes in the BACK sprites, by national dex number: pixels { x, y } (from
-- the top left of the 48x48 back pic) that each name a walled-in white region
-- which is really a gap in the sprite, so it should be transparent instead of
-- white.  Same idea and same safety check as lib/specks.lua (see Pic.matte),
-- but a back sprite is a single static pic, so there are no other frames to
-- follow.  Decisions are in tools/review_back_decisions.json; the pixel is the
-- first one of the region, reading left to right, top to bottom.
return {
  [3] = { { 35, 27 } }, -- Venusaur
  [5] = { { 25, 40 } }, -- Charmeleon
  [41] = { { 15, 10 } }, -- Zubat
  [44] = { { 5, 32 }, { 37, 33 } }, -- Gloom
  [65] = { { 17, 23 } }, -- Alakazam
  [71] = { { 18, 21 }, { 11, 38 } }, -- Victreebel
  [80] = { { 14, 20 } }, -- Slowbro
  [116] = { { 18, 22 } }, -- Horsea
  [150] = { { 15, 27 } }, -- Mewtwo
  [151] = { { 36, 20 } }, -- Mew
}
