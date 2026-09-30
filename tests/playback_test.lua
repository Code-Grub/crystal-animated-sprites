package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local P = H.need("playback")

local tl = { { frame = 1, ticks = 30 }, { frame = 2, ticks = 60 } } -- 0.5s, 1s

H.test("playback: steps by elapsed time", function()
  H.eq(P.frameAt(tl, 0), 1)
  H.eq(P.frameAt(tl, 0.49), 1)
  H.eq(P.frameAt(tl, 0.51), 2)
  H.eq(P.frameAt(tl, 1.49), 2)
end)

H.test("playback: rests on frame 0 then loops", function()
  H.eq(P.frameAt(tl, 1.6), 0)
  H.eq(P.frameAt(tl, 3.49), 0)
  H.eq(P.frameAt(tl, 3.51), 1) -- 1.5s animation + 2s rest = 3.5s cycle
end)

H.test("playback: empty timeline and bad time are safe", function()
  H.eq(P.frameAt({}, 5), 0)
  H.eq(P.frameAt(tl, -1), 0)
  H.eq(P.frameAt(nil, 1), 0)
end)
