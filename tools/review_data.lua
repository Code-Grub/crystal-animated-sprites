-- Dev tool: writes out/review_data.js for tools/review.html, and
-- out/propagated.lua.
--
-- Every walled-in white region (colour 0) of 4 or more pixels whose only
-- neighbours are black outline, in each species' resting front pic.  Those are
-- the regions that might be a real hole (background seen through the sprite) or
-- might be a white feature such as an eye or a tongue; the code cannot tell,
-- so a person decides in the review page.
--
--   luajit tools/review_data.lua
--
-- The output is derived from the ROM: it stays in out/ (git-ignored).
package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local Rom, Anim, Pic = H.need("rom"), H.need("anim"), H.need("pic")
local rom = Rom.new(assert(H.rom(), "no ROM: set CRYSTAL_ROM"))

local NAMES = {
  "Bulbasaur", "Ivysaur", "Venusaur", "Charmander", "Charmeleon", "Charizard", "Squirtle",
  "Wartortle", "Blastoise", "Caterpie", "Metapod", "Butterfree", "Weedle", "Kakuna", "Beedrill",
  "Pidgey", "Pidgeotto", "Pidgeot", "Rattata", "Raticate", "Spearow", "Fearow", "Ekans", "Arbok",
  "Pikachu", "Raichu", "Sandshrew", "Sandslash", "Nidoran F", "Nidorina", "Nidoqueen",
  "Nidoran M", "Nidorino", "Nidoking", "Clefairy", "Clefable", "Vulpix", "Ninetales",
  "Jigglypuff", "Wigglytuff", "Zubat", "Golbat", "Oddish", "Gloom", "Vileplume", "Paras",
  "Parasect", "Venonat", "Venomoth", "Diglett", "Dugtrio", "Meowth", "Persian", "Psyduck",
  "Golduck", "Mankey", "Primeape", "Growlithe", "Arcanine", "Poliwag", "Poliwhirl", "Poliwrath",
  "Abra", "Kadabra", "Alakazam", "Machop", "Machoke", "Machamp", "Bellsprout", "Weepinbell",
  "Victreebel", "Tentacool", "Tentacruel", "Geodude", "Graveler", "Golem", "Ponyta", "Rapidash",
  "Slowpoke", "Slowbro", "Magnemite", "Magneton", "Farfetch'd", "Doduo", "Dodrio", "Seel",
  "Dewgong", "Grimer", "Muk", "Shellder", "Cloyster", "Gastly", "Haunter", "Gengar", "Onix",
  "Drowzee", "Hypno", "Krabby", "Kingler", "Voltorb", "Electrode", "Exeggcute", "Exeggutor",
  "Cubone", "Marowak", "Hitmonlee", "Hitmonchan", "Lickitung", "Koffing", "Weezing", "Rhyhorn",
  "Rhydon", "Chansey", "Tangela", "Kangaskhan", "Horsea", "Seadra", "Goldeen", "Seaking",
  "Staryu", "Starmie", "Mr. Mime", "Scyther", "Jynx", "Electabuzz", "Magmar", "Pinsir", "Tauros",
  "Magikarp", "Gyarados", "Lapras", "Ditto", "Eevee", "Vaporeon", "Jolteon", "Flareon",
  "Porygon", "Omanyte", "Omastar", "Kabuto", "Kabutops", "Aerodactyl", "Snorlax", "Articuno",
  "Zapdos", "Moltres", "Dratini", "Dragonair", "Dragonite", "Mewtwo", "Mew",
}

-- Connected colour-0 regions that the edge fill left opaque.
local function regions(px, w)
  local alpha = Pic.matte(px, w)
  local seen, out = {}, {}
  for s = 1, #px do
    if px[s] == 0 and alpha[s] == 1 and not seen[s] then
      local comp, qi, ring = { s }, 1, {}
      seen[s] = true
      while qi <= #comp do
        local i = comp[qi]; qi = qi + 1
        local x, y = (i - 1) % w, math.floor((i - 1) / w)
        for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
          local nx, ny = x + d[1], y + d[2]
          if nx >= 0 and nx < w and ny >= 0 and ny < w then
            local j = ny * w + nx + 1
            if px[j] == 0 and alpha[j] == 1 then
              if not seen[j] then seen[j] = true; comp[#comp + 1] = j end
            else
              ring[px[j]] = true
            end
          end
        end
      end
      table.sort(comp)
      out[#out + 1] = { cells = comp, blackOnly = not (ring[1] or ring[2]) }
    end
  end
  return out
end

local function digits(px)
  local t = {}
  for i = 1, #px do t[i] = tostring(px[i]) end
  return table.concat(t)
end


-- Decisions already made on the resting frame (tests/review_decisions.lua).
-- Round 1 (no decisions file) reviews the resting pics; later rounds look at
-- every animation frame: a region that overlaps a hole you removed is the same
-- hole in a different pose and is cleared automatically (its first pixel is
-- added as a seed), one that overlaps a region you kept is left alone, and
-- anything that overlaps neither is a new candidate for the page.
local MIN = tonumber(os.getenv("MIN_SIZE") or "4")
local decisions = pcall(dofile, "tests/review_decisions.lua") and dofile("tests/review_decisions.lua") or nil

local function regionAt(list, cellIndex0)
  for _, region in ipairs(list) do
    for _, c in ipairs(region.cells) do
      if c - 1 == cellIndex0 then return region end
    end
  end
end

local items, propagated, stats = {}, {}, { propagated = 0, kept = 0, new = 0, seeds = 0 }
local expectRemove, expectKeep = {}, {}
for dex = 1, 151 do
  local r = Anim.decode(rom, dex)
  local w = r.width
  local frames = {}
  for index in pairs(r.frames) do frames[#frames + 1] = index end
  table.sort(frames)

  local perFrame = {}
  for _, index in ipairs(frames) do perFrame[index] = regions(r.frames[index], w) end

  -- cells of regions already decided on the resting frame
  local removeCells, keepCells = {}, {}
  if decisions then
    for _, d in ipairs(decisions.remove) do
      if d[1] == dex then
        local region = regionAt(perFrame[0], d[3] * w + d[2])
        if region then for _, c in ipairs(region.cells) do removeCells[c] = true end end
      end
    end
    for _, d in ipairs(decisions.keep) do
      if d[1] == dex then
        local region = regionAt(perFrame[0], d[3] * w + d[2])
        if region then for _, c in ipairs(region.cells) do keepCells[c] = true end end
      end
    end
  end

  local emitted = {}          -- cells of candidates already listed for this species
  local seedSeen = {}
  for _, index in ipairs(frames) do
    if index ~= 0 or not decisions then
      for _, region in ipairs(perFrame[index]) do
        if region.blackOnly then
          local overRemove, overKeep = false, false
          for _, c in ipairs(region.cells) do
            if removeCells[c] then overRemove = true end
            if keepCells[c] then overKeep = true end
          end
          local seed = region.cells[1] - 1
          if overRemove and not overKeep then
            if not seedSeen[seed] then
              seedSeen[seed] = true
              propagated[dex] = propagated[dex] or {}
              propagated[dex][#propagated[dex] + 1] = { seed % w, math.floor(seed / w) }
              stats.seeds = stats.seeds + 1
            end
            stats.propagated = stats.propagated + 1
            expectRemove[#expectRemove + 1] = ("{ %d, %d, %d, %d }"):format(dex, index, seed % w, math.floor(seed / w))
          elseif overKeep then
            stats.kept = stats.kept + 1
            expectKeep[#expectKeep + 1] = ("{ %d, %d, %d, %d }"):format(dex, index, seed % w, math.floor(seed / w))
          elseif #region.cells >= MIN then
            local dup = false
            for _, c in ipairs(region.cells) do if emitted[c] then dup = true break end end
            if not dup then
              for _, c in ipairs(region.cells) do emitted[c] = true end
              local inFrames = {}
              for _, f2 in ipairs(frames) do
                for _, other in ipairs(perFrame[f2]) do
                  if other.blackOnly and other.cells[1] == region.cells[1] then inFrames[#inFrames + 1] = f2 end
                end
              end
              local cells = {}
              for _, i in ipairs(region.cells) do cells[#cells + 1] = i - 1 end
              items[#items + 1] = string.format(
                '{"dex":%d,"name":"%s","frame":%d,"w":%d,"x":%d,"y":%d,"size":%d,"frames":[%s],"px":"%s","cells":[%s]}',
                dex, NAMES[dex], index, w, seed % w, math.floor(seed / w), #region.cells,
                table.concat(inFrames, ","), digits(r.frames[index]), table.concat(cells, ","))
              stats.new = stats.new + 1
            end
          end
        end
      end
    end
  end
end

os.execute('mkdir out 2>nul')
local f = assert(io.open("out/review_data.js", "wb"))
f:write("window.REVIEW_DATA = [\n", table.concat(items, ",\n"), "\n];\n")
f:close()

local lines = {}
local keys = {}
for dex in pairs(propagated) do keys[#keys + 1] = dex end
table.sort(keys)
for _, dex in ipairs(keys) do
  local seeds = {}
  for _, s2 in ipairs(propagated[dex]) do seeds[#seeds + 1] = ("{ %d, %d }"):format(s2[1], s2[2]) end
  lines[#lines + 1] = ("  [%d] = { %s },"):format(dex, table.concat(seeds, ", "))
end
local g = assert(io.open("out/propagated.lua", "wb"))
g:write("return {\n", table.concat(lines, "\n"), "\n}\n")
g:close()

local h = assert(io.open("out/expectations.lua", "wb"))
h:write("-- { dex, frame, x, y }: the first pixel of a region seen in an animation frame.\n")
h:write("-- remove: overlaps a hole that was removed, so it must be transparent.\n")
h:write("-- keep: overlaps a region that was kept, so it must stay opaque.\n")
h:write("return {\n  remove = {\n    ", table.concat(expectRemove, ",\n    "), ",\n  },\n")
h:write("  keep = {\n    ", table.concat(expectKeep, ",\n    "), ",\n  },\n}\n")
h:close()

print(("candidates for review: %d | already-removed holes seen in other frames: %d (seeds to add: %d) | kept regions seen again: %d")
  :format(stats.new, stats.propagated, stats.seeds, stats.kept))
