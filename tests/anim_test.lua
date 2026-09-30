package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local Anim = H.need("anim")
local Rom = H.need("rom")

H.test("anim: timeline with no repeats", function()
  local t = Anim.timeline({ { 1, 5 }, { 2, 8 }, { 0, 3 } })
  H.eq(#t, 3)
  H.eq(t[1].frame, 1); H.eq(t[1].ticks, 5)
  H.eq(t[3].frame, 0); H.eq(t[3].ticks, 3)
end)

H.test("anim: zero duration means 256 ticks", function()
  H.eq(Anim.timeline({ { 1, 0 } })[1].ticks, 256)
end)

H.test("anim: setrepeat/dorepeat plays the body n times in total", function()
  -- setrepeat 3; frame 1; frame 2; dorepeat back to row index 1
  local rows = { { 0xFE, 3 }, { 1, 4 }, { 2, 4 }, { 0xFD, 1 } }
  local t = Anim.timeline(rows)
  local seq = {}
  for _, e in ipairs(t) do seq[#seq + 1] = e.frame end
  H.arrayEq(seq, { 1, 2, 1, 2, 1, 2 })
end)

H.test("anim: dorepeat with no counter falls through", function()
  local t = Anim.timeline({ { 1, 4 }, { 0xFD, 0 }, { 2, 4 } })
  H.eq(#t, 2)
end)

local raw = H.rom()
if not raw then
  H.skip("anim: real ROM checks", "no ROM found (set CRYSTAL_ROM)")
else
  local rom = Rom.new(raw)

  H.test("anim: every Kanto species has a 5, 6 or 7 tile pic", function()
    for dex = 1, 151 do
      local size = Anim.dimensions(rom, dex)
      H.eq(size >= 5 and size <= 7, true, "dex " .. dex)
    end
  end)

  H.test("anim: every back pic is 6x6 tiles", function()
    for dex = 1, 151 do
      H.eq(#Anim.readBack(rom, dex), 36 * 16, "dex " .. dex)
    end
  end)

  H.test("anim: front sheet holds the resting pic plus extra tiles", function()
    for dex = 1, 151 do
      local size = Anim.dimensions(rom, dex)
      local data = Anim.readFront(rom, dex)
      H.eq(#data % 16, 0, "dex " .. dex .. " whole tiles")
      H.eq(#data >= size * size * 16, true, "dex " .. dex .. " has resting pic")
    end
  end)

  H.test("anim: every tile id a frame names exists in the sheet", function()
    for dex = 1, 151 do
      local size = Anim.dimensions(rom, dex)
      local tiles = #Anim.readFront(rom, dex) / 16
      local seen = {}
      for _, e in ipairs(Anim.timeline(Anim.script(rom, dex))) do
        if not seen[e.frame] then
          seen[e.frame] = true
          for _, id in ipairs(Anim.frameMap(rom, dex, size, e.frame)) do
            H.eq(id < tiles, true, ("dex %d frame %d tile %d"):format(dex, e.frame, id))
          end
        end
      end
    end
  end)

  H.test("anim: Pikachu decodes to a non-trivial timeline", function()
    local r = Anim.decode(rom, 25)
    H.eq(#r.timeline > 1, true, "more than one step")
    H.eq(r.width, r.size * 8)
    H.eq(#r.frames[0], r.width * r.width)
    H.eq(#r.back, 48 * 48)
  end)

  H.test("anim: all 151 species decode", function()
    for dex = 1, 151 do
      local ok, err = pcall(Anim.decode, rom, dex)
      H.eq(ok, true, "dex " .. dex .. ": " .. tostring(err))
    end
  end)
end
