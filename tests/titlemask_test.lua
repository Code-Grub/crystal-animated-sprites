package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local TitleMask = H.need("titlemask")

-- '#' is opaque.  Returns the per-row opaque runs for the picture.
local function runsOf(rows)
  return TitleMask.rowRuns(function(x, y) return rows[y + 1]:sub(x + 1, x + 1) == "#" end, #rows[1], #rows)
end

-- every free rect as "x,y,w,h", sorted, so a test reads at a glance
local function show(rects)
  local out = {}
  for _, r in ipairs(rects) do out[#out + 1] = r[1] .. "," .. r[2] .. "," .. r[3] .. "," .. r[4] end
  table.sort(out)
  return table.concat(out, " ")
end

H.test("titlemask: rowRuns finds the opaque stretches of each row", function()
  local runs = runsOf({ "..##.#", "......", "######" })
  H.eq(#runs[0], 2)
  H.eq(runs[0][1][1] .. "-" .. runs[0][1][2], "2-3")
  H.eq(runs[0][2][1] .. "-" .. runs[0][2][2], "5-5")
  H.eq(#runs[1], 0)
  H.eq(runs[2][1][1] .. "-" .. runs[2][1][2], "0-5")
end)

H.test("titlemask: with nothing drawn over it the whole rect is free", function()
  H.eq(show(TitleMask.freeRects({ 10, 20, 8, 4 }, {})), "10,20,8,4")
end)

H.test("titlemask: art that does not reach the rect leaves it whole", function()
  local runs = runsOf({ "####", "####" })
  local free = TitleMask.freeRects({ 10, 20, 8, 4 },
    { { runs = runs, qx = 0, qy = 0, qw = 4, qh = 2, x = 100, y = 100 } })
  H.eq(show(free), "10,20,8,4")
end)

H.test("titlemask: solid art over part of the rect frees only the rest", function()
  -- a 4x2 block drawn at (12, 21): covers x 12..15 on rows 21 and 22
  local runs = runsOf({ "####", "####" })
  local free = TitleMask.freeRects({ 10, 20, 8, 4 },
    { { runs = runs, qx = 0, qy = 0, qw = 4, qh = 2, x = 12, y = 21 } })
  H.eq(show(free), "10,20,8,1 10,21,2,2 10,23,8,1 16,21,2,2")
end)

H.test("titlemask: a transparent gap inside the art stays free", function()
  -- the middle column of a 3x3 picture is empty, so it is free all the way down
  local runs = runsOf({ "#.#", "#.#", "#.#" })
  local free = TitleMask.freeRects({ 0, 0, 3, 3 },
    { { runs = runs, qx = 0, qy = 0, qw = 3, qh = 3, x = 0, y = 0 } })
  H.eq(show(free), "1,0,1,3")
end)

H.test("titlemask: rows with the same free span merge into one tall rect", function()
  local free = TitleMask.freeRects({ 0, 0, 5, 6 }, {})
  H.eq(#free, 1)
  H.eq(show(free), "0,0,5,6")
end)

H.test("titlemask: a quad draws its viewport at the placement, not the whole picture", function()
  -- source 4 wide, 3 tall; only rows 1..2 (the viewport) are drawn, at (0, 5)
  local runs = runsOf({ "####", "####", "####" })
  local free = TitleMask.freeRects({ 0, 5, 4, 3 },
    { { runs = runs, qx = 0, qy = 1, qw = 4, qh = 2, x = 0, y = 5 } })
  -- source rows 1 and 2 land on screen rows 5 and 6; row 7 is untouched
  H.eq(show(free), "0,7,4,1")
end)

H.test("titlemask: a quad's x offset is honoured", function()
  local runs = runsOf({ ".##." })
  local free = TitleMask.freeRects({ 0, 0, 6, 1 },
    { { runs = runs, qx = 1, qy = 0, qw = 2, qh = 1, x = 3, y = 0 } })
  -- viewport x 1..2 (both opaque) is drawn at screen x 3..4
  H.eq(show(free), "0,0,3,1 5,0,1,1")
end)

H.test("titlemask: several placements all hide the mon", function()
  local runs = runsOf({ "##" })
  local free = TitleMask.freeRects({ 0, 0, 6, 1 }, {
    { runs = runs, qx = 0, qy = 0, qw = 2, qh = 1, x = 0, y = 0 },
    { runs = runs, qx = 0, qy = 0, qw = 2, qh = 1, x = 4, y = 0 },
  })
  H.eq(show(free), "2,0,2,1")
end)
