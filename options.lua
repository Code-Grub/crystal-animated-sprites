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
  -- GAME draws the sprites in the colours of the game you are playing.
  -- CRYSTAL draws each Pokemon in the colours Crystal gave it.
  {
    key = "sprite_colors",
    type = "choice",
    label = "SPRITE COLORS",
    default = "game",
    choices = { { "GAME", "game" }, { "CRYSTAL", "crystal" } },
  },
  -- Draws the cache and job state over the battle, for bug reports on devices
  -- whose save folder cannot be opened.
  {
    key = "diagnostics",
    type = "choice",
    label = "DIAGNOSTICS",
    default = "off",
    choices = { { "OFF", "off" }, { "ON", "on" } },
  },
}
