-- Hand edits made in tools/editor.html, applied on top of the automatic matte.
--
--   front[dex] = { all = runs, [frame] = runs }   runs for every animation frame,
--                                                 and for one frame on top of those
--   back[dex]  = runs
--
-- A run is { y, x1, x2, "clear" | "keep" } on the pic's pixel grid: "clear" makes
-- white pixels transparent, "keep" makes them opaque (see Pic.applyEdits).
return {
  front = {},
  back = {},
}
