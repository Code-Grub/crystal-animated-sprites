package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local IconShim = H.need("iconshim")

local function fakeGame()
  return {
    save = { party = {} },
    data = {
      pokemon = { PIDGEY = { dex = 16 } },
      icons = {
        icons = { BIRD = "assets/bird.png" },
        byDex = { [16] = "BIRD" },
        bySpecies = { RATTATA = "FOX" },
      },
    },
  }
end

H.test("iconshim: the shim's icon table has the species entry and everything else as before", function()
  local game = fakeGame()
  local shim = IconShim.new()
  local view = shim:view(game, "PIDGEY", { image = "mod_cache/m/s/icons/07.png", trueColor = false })
  local entry = view.data.icons.bySpecies.PIDGEY
  H.eq(entry.image, "mod_cache/m/s/icons/07.png")
  H.eq(entry.trueColor, false)
  H.eq(view.data.icons.bySpecies.RATTATA, "FOX", "other species keep their entry")
  H.eq(view.data.icons.icons.BIRD, "assets/bird.png", "icon names still resolve")
  H.eq(view.data.icons.byDex[16], "BIRD")
  H.eq(view.data.pokemon.PIDGEY.dex, 16, "the rest of the data is reachable")
  H.eq(view.save, game.save, "the rest of the game is reachable")
end)

H.test("iconshim: the real game data is not touched", function()
  local game = fakeGame()
  IconShim.new():view(game, "PIDGEY", { image = "x.png" })
  H.eq(game.data.icons.bySpecies.PIDGEY, nil)
  H.eq(game.data.icons.bySpecies.RATTATA, "FOX")
end)

H.test("iconshim: the same species and entry reuse one view, a changed entry builds a new one", function()
  local game = fakeGame()
  local shim = IconShim.new()
  local a = shim:view(game, "PIDGEY", { image = "a.png", trueColor = false })
  local b = shim:view(game, "PIDGEY", { image = "a.png", trueColor = false })
  H.eq(a, b, "same entry, same view")
  local c = shim:view(game, "PIDGEY", { image = "a.png", trueColor = true })
  H.eq(a ~= c, true, "true colour changed")
  local d = shim:view(game, "PIDGEY", { image = "b.png", trueColor = true })
  H.eq(c ~= d, true, "image changed")
  H.eq(d.data.icons.bySpecies.PIDGEY.image, "b.png")
end)

H.test("iconshim: another game object gets its own view", function()
  local shim = IconShim.new()
  local g1, g2 = fakeGame(), fakeGame()
  local a = shim:view(g1, "PIDGEY", { image = "a.png" })
  local b = shim:view(g2, "PIDGEY", { image = "a.png" })
  H.eq(a ~= b, true)
  H.eq(b.save, g2.save)
end)

H.test("iconshim: a game without icon data gives no view", function()
  local shim = IconShim.new()
  H.eq(shim:view({ data = {} }, "PIDGEY", { image = "a.png" }), nil)
  H.eq(shim:view({}, "PIDGEY", { image = "a.png" }), nil)
end)
