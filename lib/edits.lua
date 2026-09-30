-- Hand edits made in tools/editor.html, applied on top of the automatic matte.
--
--   front[dex] = { all = runs, [frame] = runs }   runs for every animation frame,
--                                                 and for one frame on top of those
--   back[dex]  = runs
--
-- A run is { y, x1, x2, "clear" | "keep" } on the pic's pixel grid: "clear" makes
-- white pixels transparent, "keep" makes them opaque (see Pic.applyEdits).
return {
  front = {
    [3] = { [0] = { { 23, 42, 42, "clear" } }, [1] = { { 23, 42, 42, "clear" } }, [2] = { { 23, 42, 42, "clear" } }, [3] = { { 23, 42, 42, "clear" } }, [4] = { { 23, 42, 42, "clear" } }, [5] = { { 23, 42, 42, "clear" } } },
    [4] = { [4] = { { 10, 33, 33, "keep" } } },
    [5] = { [0] = { { 19, 37, 37, "clear" }, { 20, 37, 37, "clear" }, { 21, 37, 38, "clear" }, { 22, 37, 39, "clear" }, { 23, 36, 40, "clear" }, { 24, 36, 40, "clear" }, { 25, 35, 39, "clear" }, { 26, 30, 32, "clear" }, { 26, 34, 39, "clear" }, { 27, 30, 38, "clear" }, { 28, 31, 37, "clear" }, { 29, 31, 36, "clear" }, { 30, 32, 34, "clear" } }, [1] = { { 19, 37, 37, "clear" }, { 20, 37, 37, "clear" }, { 21, 37, 38, "clear" }, { 22, 37, 39, "clear" }, { 23, 36, 40, "clear" }, { 24, 36, 40, "clear" }, { 25, 35, 39, "clear" }, { 26, 30, 32, "clear" }, { 26, 34, 39, "clear" }, { 27, 30, 38, "clear" }, { 28, 31, 37, "clear" }, { 29, 31, 36, "clear" }, { 30, 32, 34, "clear" }, { 32, 13, 13, "clear" }, { 33, 12, 13, "clear" }, { 34, 13, 14, "clear" }, { 35, 14, 14, "clear" } }, [2] = { { 19, 37, 37, "clear" }, { 20, 37, 37, "clear" }, { 21, 37, 38, "clear" }, { 22, 37, 39, "clear" }, { 23, 36, 40, "clear" }, { 24, 36, 40, "clear" }, { 25, 35, 39, "clear" }, { 26, 30, 32, "clear" }, { 26, 34, 39, "clear" }, { 27, 30, 38, "clear" }, { 28, 31, 37, "clear" }, { 29, 31, 36, "clear" }, { 30, 32, 34, "clear" } } },
  },
  back = {
    [2] = { { 32, 42, 42, "clear" } },
    [3] = { { 30, 40, 40, "clear" }, { 45, 4, 4, "keep" }, { 46, 3, 5, "keep" }, { 47, 3, 5, "keep" } },
    [4] = { { 17, 9, 9, "keep" }, { 17, 12, 12, "keep" }, { 27, 3, 3, "keep" }, { 42, 35, 35, "keep" }, { 43, 5, 5, "keep" }, { 43, 33, 35, "keep" }, { 44, 5, 5, "keep" }, { 44, 33, 35, "keep" }, { 45, 5, 5, "keep" }, { 45, 32, 35, "keep" }, { 46, 5, 6, "keep" }, { 46, 32, 35, "keep" }, { 47, 6, 7, "keep" }, { 47, 31, 34, "keep" } },
    [5] = { { 26, 35, 35, "clear" }, { 27, 25, 26, "clear" }, { 27, 33, 35, "clear" }, { 28, 25, 27, "clear" }, { 28, 32, 34, "clear" }, { 29, 27, 34, "clear" }, { 30, 28, 34, "clear" }, { 31, 29, 34, "clear" }, { 32, 29, 35, "clear" }, { 33, 30, 35, "clear" }, { 34, 30, 36, "clear" }, { 35, 31, 38, "clear" }, { 36, 31, 38, "clear" }, { 37, 32, 37, "clear" }, { 38, 33, 37, "clear" }, { 39, 34, 36, "clear" }, { 40, 34, 35, "clear" } },
  },
}
