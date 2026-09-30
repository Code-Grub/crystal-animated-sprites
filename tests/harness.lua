local H = { passed = 0, failed = 0, skipped = 0 }

function H.test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    H.passed = H.passed + 1
    print("PASS  " .. name)
  else
    H.failed = H.failed + 1
    print("FAIL  " .. name .. "\n      " .. tostring(err))
  end
end

function H.skip(name, why)
  H.skipped = H.skipped + 1
  print("SKIP  " .. name .. " (" .. why .. ")")
end

function H.eq(actual, expected, msg)
  if actual ~= expected then
    error((msg or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual), 2)
  end
end

function H.arrayEq(actual, expected, msg)
  H.eq(#actual, #expected, (msg or "array") .. " length")
  for i = 1, #expected do
    if actual[i] ~= expected[i] then
      error((msg or "array") .. " differs at " .. i .. ": expected "
        .. tostring(expected[i]) .. ", got " .. tostring(actual[i]), 2)
    end
  end
end

local cache = {}
local function need(name)
  if not cache[name] then
    local chunk = assert(loadfile("lib/" .. name .. ".lua"))
    cache[name] = chunk(need)
  end
  return cache[name]
end
H.need = need

local DEFAULT_ROM = "C:/Users/camwr/Desktop/Gen1Recomp/game/"
  .. "Pokemon - Crystal Version (USA, Europe) (Rev 1).gbc"

function H.rom()
  local path = os.getenv("CRYSTAL_ROM") or DEFAULT_ROM
  local f = io.open(path, "rb")
  if not f then return nil end
  local raw = f:read("*a")
  f:close()
  return raw
end

function H.finish()
  print(("\n%d passed, %d failed, %d skipped"):format(H.passed, H.failed, H.skipped))
  local strict = os.getenv("REQUIRE_ROM") == "1" and H.skipped > 0
  os.exit((H.failed > 0 or strict) and 1 or 0)
end

return H
