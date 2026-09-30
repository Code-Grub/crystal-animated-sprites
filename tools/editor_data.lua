-- Dev tool: writes out/editor_data.js for tools/editor.html.
--
--   luajit tools/editor_data.lua
--
-- For every Pokemon: each front animation frame and the back sprite, as the
-- 2-bit pixels plus the AUTOMATIC alpha (the edge matte and the reviewed holes,
-- from the same Pic.matte call the decode job makes, before any hand edits).
-- The hand edits already in lib/edits.lua are included separately, so the
-- editor can show the current result and export a complete edit list.
--
-- The output is derived from the ROM: it stays in out/ (git-ignored).
package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local Rom, Anim, Pic = H.need("rom"), H.need("anim"), H.need("pic")
local Specks, SpecksBack, Edits = H.need("specks"), H.need("specks_back"), H.need("edits")
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

local function digits(px)
  local t = {}
  for i = 1, #px do t[i] = tostring(px[i]) end
  return table.concat(t)
end

local function bits(alpha)
  local t = {}
  for i = 1, #alpha do t[i] = alpha[i] == 0 and "0" or "1" end
  return table.concat(t)
end

local function runsJson(runs)
  local out = {}
  for _, r in ipairs(runs or {}) do out[#out + 1] = ("[%d,%d,%d,\"%s\"]"):format(r[1], r[2], r[3], r[4]) end
  return "[" .. table.concat(out, ",") .. "]"
end

local function editsJson()
  local front, back = {}, {}
  local keys = {}
  for dex in pairs(Edits.front) do keys[#keys + 1] = dex end
  table.sort(keys)
  for _, dex in ipairs(keys) do
    local parts = {}
    for scope, runs in pairs(Edits.front[dex]) do
      parts[#parts + 1] = ("\"%s\":%s"):format(tostring(scope), runsJson(runs))
    end
    front[#front + 1] = ("\"%d\":{%s}"):format(dex, table.concat(parts, ","))
  end
  keys = {}
  for dex in pairs(Edits.back) do keys[#keys + 1] = dex end
  table.sort(keys)
  for _, dex in ipairs(keys) do back[#back + 1] = ("\"%d\":%s"):format(dex, runsJson(Edits.back[dex])) end
  return ("{\"front\":{%s},\"back\":{%s}}"):format(table.concat(front, ","), table.concat(back, ","))
end

os.execute("mkdir out 2>nul")
local f = assert(io.open("out/editor_data.js", "wb"))
local names = {}
for i, n in ipairs(NAMES) do names[i] = ("\"%s\""):format(n:gsub("\"", "\\\"")) end
f:write("window.EDITOR = {\n\"names\":[", table.concat(names, ","), "],\n\"edits\":", editsJson(), ",\n\"sprites\":{\n")
for dex = 1, 151 do
  local r = Anim.decode(rom, dex)
  local frames = {}
  local order = {}
  for index in pairs(r.frames) do order[#order + 1] = index end
  table.sort(order)
  for _, index in ipairs(order) do
    local px = r.frames[index]
    frames[#frames + 1] = ("{\"f\":%d,\"px\":\"%s\",\"a\":\"%s\"}"):format(
      index, digits(px), bits(Pic.matte(px, r.width, Specks[dex])))
  end
  f:write(("\"%d\":{\"w\":%d,\"front\":[%s],\"back\":{\"px\":\"%s\",\"a\":\"%s\"}}%s\n"):format(
    dex, r.width, table.concat(frames, ","), digits(r.back),
    bits(Pic.matte(r.back, 48, SpecksBack[dex])), dex < 151 and "," or ""))
end
f:write("}};\n")
f:close()
print("wrote out/editor_data.js")
