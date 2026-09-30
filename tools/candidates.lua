-- Dev tool: every walled-in speck (1-3 pixels of colour 0, all-black around it)
-- in every species, frame and back pic, with its distance to the outside.
-- Prints "dex kind frame x y size dist".  Used to decide the matte rule.
package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local Rom, Anim = H.need("rom"), H.need("anim")
local rom = Rom.new(assert(H.rom(), "no ROM: set CRYSTAL_ROM"))

local function analyse(px, w, emit)
  local h = #px / w
  local bg, q = {}, {}
  local function v(x, y) local i = y*w+x+1; if not bg[i] and px[i] == 0 then bg[i] = true; q[#q+1] = i end end
  for x = 0, w-1 do v(x, 0); v(x, h-1) end
  for y = 0, h-1 do v(0, y); v(w-1, y) end
  local head = 1
  while head <= #q do
    local i = q[head]; head = head + 1
    local x, y = (i-1) % w, math.floor((i-1) / w)
    if x > 0 then v(x-1, y) end if x < w-1 then v(x+1, y) end
    if y > 0 then v(x, y-1) end if y < h-1 then v(x, y+1) end
  end
  -- Manhattan distance from every cell to the nearest outside pixel
  local dist, dq = {}, {}
  for i in pairs(bg) do dist[i] = 0; dq[#dq+1] = i end
  head = 1
  while head <= #dq do
    local i = dq[head]; head = head + 1
    local x, y = (i-1) % w, math.floor((i-1) / w)
    for _, d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
      local nx, ny = x+d[1], y+d[2]
      if nx >= 0 and nx < w and ny >= 0 and ny < h then
        local j = ny*w+nx+1
        if not dist[j] then dist[j] = dist[i] + 1; dq[#dq+1] = j end
      end
    end
  end
  local seen = {}
  for s = 1, #px do
    if px[s] == 0 and not bg[s] and not seen[s] then
      local comp, members, qi, ok = { s }, { [s] = true }, 1, true
      seen[s] = true
      local ring = {}
      while qi <= #comp do
        local i = comp[qi]; qi = qi + 1
        local x, y = (i-1) % w, math.floor((i-1) / w)
        for _, d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
          local nx, ny = x+d[1], y+d[2]
          if nx < 0 or nx >= w or ny < 0 or ny >= h then ok = false
          else
            local j = ny*w+nx+1
            if px[j] == 0 and not bg[j] then
              if not members[j] then members[j] = true; seen[j] = true; comp[#comp+1] = j end
            else ring[j] = true end
          end
        end
      end
      if ok and #comp <= 3 then
        local allBlack, near = true, math.huge
        for j in pairs(ring) do
          if px[j] ~= 3 then allBlack = false end
        end
        for _, i in ipairs(comp) do near = math.min(near, dist[i] or 99) end
        if allBlack then
          local x, y = (s-1) % w, math.floor((s-1) / w)
          emit(x, y, #comp, near)
        end
      end
    end
  end
end

for dex = 1, 151 do
  local r = Anim.decode(rom, dex)
  for index, px in pairs(r.frames) do
    analyse(px, r.width, function(x, y, size, dist)
      print(("%d front %d %d %d %d %d"):format(dex, index, x, y, size, dist))
    end)
  end
  analyse(r.back, 48, function(x, y, size, dist)
    print(("%d back 0 %d %d %d %d"):format(dex, x, y, size, dist))
  end)
end
