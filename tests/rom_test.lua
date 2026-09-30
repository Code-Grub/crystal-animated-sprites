package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local Rom = H.need("rom")
local A = H.need("addresses")

H.test("rom: bank 0 is a flat address", function()
  H.eq(Rom.offset(0, 0x0150), 0x150)
end)

H.test("rom: switchable banks map 0x4000-0x7FFF", function()
  H.eq(Rom.offset(0x14, 0x5424), 0x51424)
  H.eq(Rom.offset(1, 0x4000), 0x4000)
end)

H.test("rom: banked address below 0x4000 is rejected", function()
  H.eq(pcall(Rom.offset, 5, 0x1234), false)
end)

H.test("rom: u8 and u16 read little-endian and bound-check", function()
  local rom = Rom.new(string.char(0x34, 0x12, 0xFF))
  H.eq(rom:u8(0), 0x34)
  H.eq(rom:u16(0), 0x1234)
  H.eq(pcall(rom.u8, rom, 3), false, "read past end must raise")
end)

local raw = H.rom()
if not raw then
  H.skip("rom: real Crystal image checks", "no ROM found (set CRYSTAL_ROM)")
else
  H.test("rom: real image is Crystal and 2 MiB", function()
    H.eq(#raw, 2097152)
    H.eq(raw:sub(0x135, 0x13E), "PM_CRYSTAL")
  end)

  H.test("rom: base data first record is Bulbasaur-shaped", function()
    local rom = Rom.new(raw)
    local off = rom:banked(A.baseData.bank, A.baseData.addr)
    H.eq(rom:u8(off), 1, "dex number of record 1")
    H.eq(rom:u8(off + 32), 2, "dex number of record 2")
    H.eq(rom:u8(off + 24 * 32), 25, "record 25 is Pikachu")
  end)
end
