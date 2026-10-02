package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local Attack = H.need("attack")

local function screen(over)
  local s = { player = { name = "p" }, enemy = { name = "e" }, queue = {} }
  for k, v in pairs(over or {}) do s[k] = v end
  return s
end

H.test("attack: a move row waiting at the front of the queue is its user attacking", function()
  local s, st = screen(), {}
  s.queue[1] = { anim = "SWIFT", attackerIsPlayer = false, animDelayed = true }
  H.eq(Attack.update(s, st, 1), s.enemy)
end)

H.test("attack: the player's own move is the player's", function()
  local s, st = screen(), {}
  s.queue[1] = { anim = "FLAMETHROWER", attackerIsPlayer = true, animDelayed = true }
  H.eq(Attack.update(s, st, 1), s.player)
end)

H.test("attack: it works with battle animations off, where only the off delay is set", function()
  local s, st = screen(), {}
  s.queue[1] = { anim = "SWIFT", attackerIsPlayer = false, animOffDelayed = true }
  H.eq(Attack.update(s, st, 1), s.enemy)
end)

H.test("attack: the same row seen again, or after its second delay, counts once", function()
  local s, st = screen(), {}
  local row = { anim = "SWIFT", attackerIsPlayer = false, animDelayed = true }
  s.queue[1] = row
  H.eq(Attack.update(s, st, 1), s.enemy)
  H.eq(Attack.update(s, st, 1.02), nil)
  row.animOffDelayed = true
  H.eq(Attack.update(s, st, 1.05), nil)
end)

H.test("attack: a row not yet started, and an empty queue, are nothing", function()
  local s, st = screen(), {}
  H.eq(Attack.update(s, st, 1), nil)
  s.queue[1] = { anim = "SWIFT", attackerIsPlayer = false }
  H.eq(Attack.update(s, st, 1), nil)
end)

H.test("attack: ball tosses and send-out poofs are not attacks", function()
  local s, st = screen(), {}
  for _, name in ipairs({ "POOF_ANIM", "TOSS_ANIM", "SHAKE_ANIM", "HIDEPIC_ANIM" }) do
    s.queue[1] = { anim = name, attackerIsPlayer = false, animDelayed = true }
    H.eq(Attack.update(s, st, 1), nil, name)
  end
  s.queue[1] = nil
  s.animPlaying, s.animName, s.animAttackerIsPlayer = true, "POOF_ANIM", false
  H.eq(Attack.update(s, st, 2), nil, "the animation starting is no different")
end)

H.test("attack: a dropped frame is covered by the animation starting", function()
  local s, st = screen(), {}
  Attack.update(s, st, 1)              -- the row was never seen at the front
  s.animPlaying, s.animName, s.animAttackerIsPlayer = true, "SWIFT", false
  H.eq(Attack.update(s, st, 1.1), s.enemy)
  H.eq(Attack.update(s, st, 1.2), nil, "and only on the frame it starts")
end)

H.test("attack: a move seen at the queue and again as it starts counts once", function()
  local s, st = screen(), {}
  s.queue[1] = { anim = "SWIFT", attackerIsPlayer = false, animDelayed = true }
  H.eq(Attack.update(s, st, 1), s.enemy)
  s.queue[1] = nil
  s.animPlaying, s.animName, s.animAttackerIsPlayer = true, "SWIFT", false
  H.eq(Attack.update(s, st, 1.05), nil)
end)

H.test("attack: a second move later is a new attack", function()
  local s, st = screen(), {}
  s.queue[1] = { anim = "SWIFT", attackerIsPlayer = false, animDelayed = true }
  Attack.update(s, st, 1)
  s.queue[1] = { anim = "SWIFT", attackerIsPlayer = false, animDelayed = true }
  H.eq(Attack.update(s, st, 4), s.enemy)
end)
