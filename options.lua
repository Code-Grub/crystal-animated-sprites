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
