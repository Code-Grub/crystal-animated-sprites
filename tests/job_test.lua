package.path = "./?.lua;" .. package.path
local H = require("tests.harness")

local function readFile(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

local function runJob(arg)
  local chunk = assert(loadstring(readFile("jobs/decode.lua"), "@jobs/decode.lua"))
  -- a sandbox-like environment: no require, no io, no os
  local env = { assert = assert, pcall = pcall, tostring = tostring, type = type,
    pairs = pairs, ipairs = ipairs, load = load, loadstring = loadstring,
    setfenv = setfenv, string = string, table = table, math = math, bit = bit,
    select = select, error = error, unpack = unpack, setmetatable = setmetatable }
  setfenv(chunk, env)
  return chunk(arg)
end

local function libs()
  local out = {}
  for _, n in ipairs({ "lz", "rom", "addresses", "pic", "png", "anim", "palette", "specks", "specks_back", "edits" }) do
    out[n] = readFile("lib/" .. n .. ".lua")
  end
  return out
end

local raw = H.rom()
if not raw then
  H.skip("job: decode batches", "no ROM found (set CRYSTAL_ROM)")
else
  H.test("job: decodes a batch and returns PNG strings", function()
    local r = runJob({ rom = raw, libs = libs(), first = 24, last = 26 })
    H.eq(next(r.errors), nil, "no errors")
    for dex = 24, 26 do
      local s = assert(r.species[dex], "species " .. dex)
      H.eq(s.back:sub(2, 4), "PNG")
      H.eq(s.frames[0]:sub(2, 4), "PNG")
      H.eq(s.flipped[0]:sub(2, 4), "PNG")
      H.eq(s.flipped[0] ~= s.frames[0], true, "mirrored differs from original")
      H.eq(#s.timeline > 0, true)
    end
  end)

  H.test("job: one bad species does not stop the batch", function()
    -- Corrupt species 25's pic pointer row so decode raises for it alone.
    local bad = raw
    local off = 0x48 * 0x4000 + (25 - 1) * 6
    bad = bad:sub(1, off) .. string.rep("\255", 6) .. bad:sub(off + 7)
    local r = runJob({ rom = bad, libs = libs(), first = 24, last = 26 })
    H.eq(type(r.errors[25]), "string", "species 25 reports an error")
    H.eq(r.species[25], nil)
    H.eq(r.species[24] ~= nil and r.species[26] ~= nil, true, "neighbours decode")
  end)
end

-- End to end: the job's PNGs carry an alpha channel with a transparent
-- background, so the sprite can sit on any backdrop.
local function rawScanlines(png)
  local pos, idat = 9, {}
  while pos <= #png do
    local a, b, c, d = png:byte(pos, pos + 3)
    local len = ((a * 256 + b) * 256 + c) * 256 + d
    if png:sub(pos + 4, pos + 7) == "IDAT" then idat[#idat + 1] = png:sub(pos + 8, pos + 7 + len) end
    pos = pos + 12 + len
  end
  local z, out, p = table.concat(idat), {}, 3
  while true do
    local final = z:byte(p)
    local len = z:byte(p + 1) + z:byte(p + 2) * 256
    out[#out + 1] = z:sub(p + 5, p + 4 + len)
    p = p + 5 + len
    if final == 1 then break end
  end
  return table.concat(out)
end

if H.rom() then
  H.test("job: pics are grayscale+alpha with a transparent corner", function()
    local r = runJob({ rom = H.rom(), libs = libs(), first = 25, last = 25 })
    local s = assert(r.species[25], "species 25")
    for label, png in pairs({ front = s.frames[0], mirrored = s.flipped[0], back = s.back }) do
      H.eq(png:byte(26), 4, label .. " colour type")
      local raw = rawScanlines(png)
      H.eq(raw:byte(3), 0, label .. " top-left pixel is transparent")
    end
    -- and something is opaque: the sprite itself
    local raw, opaque = rawScanlines(s.frames[0]), 0
    for i = 3, #raw, 2 do if raw:byte(i) == 255 then opaque = opaque + 1 end end
    H.eq(opaque > 200, true, "the sprite has opaque pixels")
  end)
end

if H.rom() then
  -- alpha byte of pixel (x, y) in a width-w grayscale+alpha PNG
  local function rawAlphaAt(png, w, x, y)
    return rawScanlines(png):byte(y * (1 + 2 * w) + 1 + 2 * x + 2)
  end
  -- what a viewer sees: a deliberate gap is written as 1/255, which reads as
  -- transparent here
  local function alphaAt(png, w, x, y)
    local a = rawAlphaAt(png, w, x, y)
    return a <= 1 and 0 or a
  end

  -- The Crystal-colour copies: the same picture and the same alpha as the grey
  -- ones, in the species' own colours.
  H.test("job: colour copies keep the grey alpha and use only the species' palette", function()
    local r = runJob({ rom = H.rom(), libs = libs(), first = 25, last = 25 })
    local s = assert(r.species[25], "species 25")
    local Rom, Palette = H.need("rom"), H.need("palette")
    local colors = Palette.colors(Rom.new(H.rom()), 25)
    local allowed = {}
    for _, c in ipairs(colors) do allowed[c[1] .. "," .. c[2] .. "," .. c[3]] = true end
    local pairs_ = {
      { "front", s.frames[0], s.colorFrames[0], s.size * 8 },
      { "mirrored", s.flipped[0], s.colorFlipped[0], s.size * 8 },
      { "back", s.back, s.colorBack, 48 },
    }
    for _, p in ipairs(pairs_) do
      local label, grey, color, w = p[1], p[2], p[3], p[4]
      H.eq(color:byte(26), 6, label .. " is colour type 6")
      local g, c = rawScanlines(grey), rawScanlines(color)
      local distinct, n = {}, 0
      for y = 0, w - 1 do
        for x = 0, w - 1 do
          local ga = g:byte(y * (1 + 2 * w) + 1 + 2 * x + 2)
          local at = y * (1 + 4 * w) + 1 + 4 * x
          local cr, cg, cb, ca = c:byte(at + 1, at + 4)
          H.eq(ca, ga, label .. " alpha at " .. x .. "," .. y)
          if ca == 255 then
            local key = cr .. "," .. cg .. "," .. cb
            H.eq(allowed[key], true, label .. " colour " .. key .. " is not in the palette")
            if not distinct[key] then distinct[key] = true; n = n + 1 end
          end
        end
      end
      H.eq(n >= 3, true, label .. " uses at least three palette colours")
    end
  end)

  -- Pidgey's feet leave a gap open only at the bottom edge.  A 3D battle mod
  -- would repaint it as white, so it has to carry the gap tag.
  H.test("job: a gap between Pidgey's feet is tagged, the background is not", function()
    local r = runJob({ rom = H.rom(), libs = libs(), first = 16, last = 16 })
    local png = r.species[16].frames[0]
    H.eq(rawAlphaAt(png, 40, 22, 34), 1, "between the feet")
    H.eq(rawAlphaAt(png, 40, 0, 0), 0, "plain background")
    H.eq(rawAlphaAt(png, 40, 17, 34), 255, "the leg itself")
  end)

  -- Hand edits (lib/edits.lua) are the final word: they override the automatic
  -- review decisions the tests below pin, so those checks skip any pixel a hand
  -- edit covers.  Everything else still has to match.
  local handEdits = dofile("lib/edits.lua")
  local function inRuns(runs, x, y)
    for _, r in ipairs(runs or {}) do
      if r[1] == y and x >= r[2] and x <= r[3] then return true end
    end
    return false
  end
  local function handFront(dex, frame, x, y)
    local sc = handEdits.front[dex]
    return sc ~= nil and (inRuns(sc.all, x, y) or inRuns(sc[frame], x, y))
  end
  local function handBack(dex, x, y) return inRuns(handEdits.back[dex], x, y) end

  H.test("job: every region reviewed by hand is cleared or kept as decided", function()
    local decisions = dofile("tests/review_decisions.lua")
    local r = runJob({ rom = H.rom(), libs = libs(), first = 1, last = 151 })
    H.eq(next(r.errors), nil, "no species failed")
    local function alpha(d)
      local sp = r.species[d[1]]
      return alphaAt(sp.frames[d[2]], sp.size * 8, d[3], d[4])
    end
    for _, d in ipairs(decisions.remove) do
      if not handFront(d[1], d[2], d[3], d[4]) then
        H.eq(alpha(d), 0, ("dex %d frame %d (%d,%d) is a hole and must be transparent"):format(d[1], d[2], d[3], d[4]))
      end
    end
    for _, d in ipairs(decisions.keep) do
      if not handFront(d[1], d[2], d[3], d[4]) then
        H.eq(alpha(d), 255, ("dex %d frame %d (%d,%d) is meant to be white and must stay"):format(d[1], d[2], d[3], d[4]))
      end
    end
  end)

  H.test("job: a reviewed hole is cleared in every animation frame, a kept region in none", function()
    local expect = dofile("tests/review_expectations.lua")
    local r = runJob({ rom = H.rom(), libs = libs(), first = 1, last = 151 })
    local function alpha(dex, frame, x, y)
      local sp = r.species[dex]
      return alphaAt(sp.frames[frame], sp.size * 8, x, y)
    end
    for _, e in ipairs(expect.remove) do
      if not handFront(e[1], e[2], e[3], e[4]) then
        H.eq(alpha(e[1], e[2], e[3], e[4]), 0,
          ("dex %d frame %d (%d,%d) is the same hole in another pose"):format(e[1], e[2], e[3], e[4]))
      end
    end
    for _, e in ipairs(expect.keep) do
      if not handFront(e[1], e[2], e[3], e[4]) then
        H.eq(alpha(e[1], e[2], e[3], e[4]), 255,
          ("dex %d frame %d (%d,%d) is a kept region and must stay"):format(e[1], e[2], e[3], e[4]))
      end
    end
  end)

  H.test("job: every back-sprite region reviewed by hand is cleared or kept as decided", function()
    local decisions = dofile("tests/review_back_decisions.lua")
    local r = runJob({ rom = H.rom(), libs = libs(), first = 1, last = 151 })
    H.eq(next(r.errors), nil, "no species failed")
    for _, d in ipairs(decisions.remove) do
      if not handBack(d[1], d[3], d[4]) then
        H.eq(alphaAt(r.species[d[1]].back, 48, d[3], d[4]), 0,
          ("dex %d back (%d,%d) is a hole and must be transparent"):format(d[1], d[3], d[4]))
      end
    end
    for _, d in ipairs(decisions.keep) do
      if not handBack(d[1], d[3], d[4]) then
        H.eq(alphaAt(r.species[d[1]].back, 48, d[3], d[4]), 255,
          ("dex %d back (%d,%d) is meant to be white and must stay"):format(d[1], d[3], d[4]))
      end
    end
  end)

  H.test("job: hand edits apply to all frames, to one frame, and to the back sprite", function()
    local l = libs()
    -- injected edits: keep the top row in every front frame, keep row 1 in frame 1 only,
    -- clear Pikachu's near eye glint, and keep the back sprite's top row
    l.edits = [[return {
      front = { [25] = { all = { { 0, 0, 39, "keep" }, { 13, 15, 15, "clear" } }, [1] = { { 1, 0, 39, "keep" } } } },
      back = { [25] = { { 0, 0, 47, "keep" } } },
    }]]
    local r = runJob({ rom = H.rom(), libs = l, first = 25, last = 25 })
    local s = assert(r.species[25], "species 25")
    local w = s.size * 8
    H.eq(alphaAt(s.frames[0], w, 0, 0), 255, "all-frames keep, frame 0")
    H.eq(alphaAt(s.frames[2], w, 0, 0), 255, "all-frames keep, frame 2")
    H.eq(alphaAt(s.frames[1], w, 0, 1), 255, "frame-1 keep applies in frame 1")
    H.eq(alphaAt(s.frames[0], w, 0, 1), 0, "frame-1 keep does not leak into frame 0")
    H.eq(alphaAt(s.frames[0], w, 15, 13), 0, "the eye glint cleared by hand")
    H.eq(alphaAt(s.flipped[0], w, w - 1, 0), 255, "mirrored copies follow the edits")
    H.eq(alphaAt(s.back, 48, 0, 0), 255, "back sprite edit")
  end)

  H.test("job: every hand edit in lib/edits.lua shows up in the decoded pics", function()
    local edits = dofile("lib/edits.lua")
    local Rom, Anim = H.need("rom"), H.need("anim")
    local rom = Rom.new(H.rom())
    local r = runJob({ rom = H.rom(), libs = libs(), first = 1, last = 151 })

    -- check one pic: `sets` are run lists applied in order (later ones win)
    local function check(label, px, w, png, sets)
      local want, hit = {}, {}
      for _, runs in ipairs(sets) do
        for n, run in ipairs(runs) do
          local y = run[1]
          for x = run[2], run[3] do
            local i = y * w + x + 1
            if px[i] == 0 then want[i] = run[4]; hit[runs] = (hit[runs] or 0) + 1 end
          end
        end
      end
      for i, action in pairs(want) do
        local x, y = (i - 1) % w, math.floor((i - 1) / w)
        H.eq(alphaAt(png, w, x, y), action == "keep" and 255 or 0,
          ("%s (%d,%d) should be %s"):format(label, x, y, action == "keep" and "opaque" or "transparent"))
      end
      for _, runs in ipairs(sets) do
        H.eq((hit[runs] or 0) > 0, true, label .. ": a run list names no white pixel at all")
      end
    end

    for dex, scopes in pairs(edits.front) do
      local d, sp = Anim.decode(rom, dex), r.species[dex]
      for scope, runs in pairs(scopes) do
        if scope ~= "all" then
          H.eq(d.frames[scope] ~= nil, true, ("dex %d has no animation frame %d"):format(dex, scope))
          local sets = {}
          if scopes.all then sets[#sets + 1] = scopes.all end
          sets[#sets + 1] = runs
          check(("dex %d frame %d"):format(dex, scope), d.frames[scope], d.width, sp.frames[scope], sets)
        end
      end
      if scopes.all then
        for index, px in pairs(d.frames) do
          if not scopes[index] then
            check(("dex %d frame %d"):format(dex, index), px, d.width, sp.frames[index], { scopes.all })
          end
        end
      end
    end
    for dex, runs in pairs(edits.back) do
      local d = Anim.decode(rom, dex)
      check(("dex %d back"):format(dex), d.back, 48, r.species[dex].back, { runs })
    end
  end)

  H.test("job: Pikachu's tail-base gap is cleared and his eye glints are not", function()
    local r = runJob({ rom = H.rom(), libs = libs(), first = 25, last = 25 })
    local s = assert(r.species[25], "species 25")
    local w = s.size * 8
    -- frames 0, 1 and 4 have the walled-in pixel at (28, 26)
    for _, index in ipairs({ 0, 1, 4 }) do
      H.eq(alphaAt(s.frames[index], w, 28, 26), 0, "frame " .. index .. " tail-base gap")
      H.eq(alphaAt(s.flipped[index], w, w - 1 - 28, 26), 0, "frame " .. index .. " mirrored")
    end
    -- frames 2 and 3 have plain outline there; it must stay
    for _, index in ipairs({ 2, 3 }) do
      H.eq(alphaAt(s.frames[index], w, 28, 26), 255, "frame " .. index .. " outline stays")
    end
    -- the far eye's glint sits close to the edge of the face but is real detail
    H.eq(alphaAt(s.frames[0], w, 5, 13), 255, "far eye glint stays")
    H.eq(alphaAt(s.frames[0], w, 15, 13), 255, "near eye glint stays")
  end)
end
