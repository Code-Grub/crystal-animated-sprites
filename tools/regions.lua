-- Dev tool: every walled-in white (colour 0) region in each species' resting
-- front pic, classified by what touches it.  Prints one line per region:
--   dex size cx cy class        class = black (only outline around it) | body (touches shaded body colour)
package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local Rom, Anim, Pic = H.need("rom"), H.need("anim"), H.need("pic")
local rom = Rom.new(assert(H.rom(), "no ROM: set CRYSTAL_ROM"))

for dex = 1, 151 do
  local r = Anim.decode(rom, dex)
  local px, w = r.frames[0], r.width
  local alpha = Pic.matte(px, w)             -- edge-connected background already cleared
  local seen = {}
  for s = 1, #px do
    if px[s] == 0 and alpha[s] == 1 and not seen[s] then
      local comp, qi, ring = { s }, 1, {}
      seen[s] = true
      local minx, maxx, miny, maxy = w, 0, w, 0
      while qi <= #comp do
        local i = comp[qi]; qi = qi + 1
        local x, y = (i - 1) % w, math.floor((i - 1) / w)
        minx, maxx, miny, maxy = math.min(minx, x), math.max(maxx, x), math.min(miny, y), math.max(maxy, y)
        for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
          local nx, ny = x + d[1], y + d[2]
          if nx >= 0 and nx < w and ny >= 0 and ny < w then
            local j = ny * w + nx + 1
            if px[j] == 0 and alpha[j] == 1 then
              if not seen[j] then seen[j] = true; comp[#comp + 1] = j end
            else ring[px[j]] = true end
          end
        end
      end
      local class = (ring[1] or ring[2]) and "body" or "black"
      print(("%d %d %d %d %s"):format(dex, #comp, math.floor((minx + maxx) / 2), math.floor((miny + maxy) / 2), class))
      if arg[1] == "dump" and class == "black" and #comp >= 4 then
        local cells = {}
        for _, i in ipairs(comp) do cells[#cells + 1] = i - 1 end
        local digits = {}
        for i = 1, #px do digits[i] = tostring(px[i]) end
        print(("DUMP %d %d %s %s"):format(dex, w, table.concat(digits), table.concat(cells, ",")))
      end
    end
  end
end
