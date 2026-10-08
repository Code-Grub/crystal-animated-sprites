-- Crystal UE v1.0 / v1.1 (identical layout), from pret/pokecrystal.
-- Each entry is { bank, address }.  Tables are indexed by national dex
-- number minus one.
return {
  baseData        = { bank = 0x14, addr = 0x5424 }, -- 32-byte records
  picPointers     = { bank = 0x48, addr = 0x4000 }, -- 6 bytes: front, back
  animPointers    = { bank = 0x34, addr = 0x4695 }, -- dw per species
  bitmaskPointers = { bank = 0x34, addr = 0x64EF }, -- dw per species
  framesPointers  = { bank = 0x35, addr = 0x4000 }, -- dw per species
  -- 8 bytes per species: two normal colours then two shiny.  Entry 0 is a
  -- placeholder, so species N is at addr + 8 * N.  A sprite is drawn with
  -- white, colour one, colour two, black.
  pokemonPalettes = { bank = 0x02, addr = 0x68CE },
  -- Party menu icons.  menuIcons is one icon id per species (251 bytes) and the
  -- pointer table, one dw per icon id, follows it directly; each icon is eight
  -- 2bpp tiles (two 16x16 frames) in the same bank.  There are 38 shared shapes.
  menuIcons       = { bank = 0x23, addr = 0x6AC4 },
  menuIconSpecies = 251,
  iconCount       = 38,
  -- The shiny entrance's art: AnimObjGFX entry $11 (BATTLE_ANIM_GFX_SPEED), nine
  -- LZ-compressed 2bpp tiles.  Tiles 0 and 1 are the small sparkles and tile 6 is
  -- one quadrant of the big star; the rest are speed lines.
  sparkleGfx      = { bank = 0x21, addr = 0x542E },
  picBankBias     = 0x36, -- pic bank bytes are stored minus this
  kantoFramesBank = 0x35, -- frame records for species 1-151
  baseDataDimensionsOffset = 0x11,
}
