-- Known blemishes, by national dex number: pixels { x, y } (from the top left
-- of the front pic) that are walled-in specks of background rather than part of
-- the sprite.  The matte clears one only if, in that frame, it is still a
-- white pixel with black on all four sides (see Pic.matte), so a coordinate
-- that is plain outline in another animation frame is left alone.
--
-- Add an entry only after looking at the pic: a glint in an eye looks the same
-- to the code, so there is no general rule.  tools/candidates.lua lists every
-- walled-in speck in the ROM with its position.
return {
  -- Pikachu: the gap between the body and the tail outline, frames 0, 1 and 4.
  [25] = { { 28, 26 } },
}
