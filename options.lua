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
  -- CRYSTAL (default) draws each Pokemon in the colours Crystal gave it.
  -- GAME draws the sprites in the colours of the game you are playing.
  {
    key = "sprite_colors",
    type = "choice",
    label = "SPRITE COLORS",
    default = "crystal",
    choices = { { "CRYSTAL", "crystal" }, { "GAME", "game" } },
  },
  -- CRYSTAL (default) uses Crystal's small icons in the party menu and the PC
  -- boxes. GAME keeps the icons of the game you are playing.
  {
    key = "party_icons",
    type = "choice",
    label = "PARTY ICONS",
    default = "crystal",
    choices = { { "CRYSTAL", "crystal" }, { "GAME", "game" } },
  },
  -- ON (default) plays a Pokemon's front animation when it uses a move.
  -- Crystal does not do this; OFF plays it only when the Pokemon appears.
  -- Your own Pokemon only moves with BACK SPRITES set to ANIMATED FRONT,
  -- because Crystal's back sprites have no animation.
  {
    key = "attack_animation",
    type = "choice",
    label = "ATTACK ANIMATION",
    default = "on",
    choices = { { "ON", "on" }, { "OFF", "off" } },
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
