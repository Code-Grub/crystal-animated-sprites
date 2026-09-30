local Rom = {}
Rom.__index = Rom

function Rom.offset(bank, addr)
  if bank == 0 then return addr end
  assert(addr >= 0x4000 and addr < 0x8000,
    ("banked address 0x%04X is outside 0x4000-0x7FFF"):format(addr))
  return bank * 0x4000 + (addr - 0x4000)
end

function Rom.new(raw)
  return setmetatable({ raw = raw }, Rom)
end

function Rom:u8(offset)
  local v = self.raw:byte(offset + 1)
  assert(v ~= nil, ("read past end of ROM at 0x%X"):format(offset))
  return v
end

function Rom:u16(offset)
  return self:u8(offset) + self:u8(offset + 1) * 256
end

function Rom:banked(bank, addr)
  return Rom.offset(bank, addr)
end

return Rom
