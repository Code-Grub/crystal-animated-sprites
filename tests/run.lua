package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local files = {
  "lz_test", "rom_test", "pic_test", "png_test",
  "anim_test", "cache_test", "playback_test", "job_test", "swap_test", "ingest_test", "status_test",
}
for _, name in ipairs(files) do
  local path = "tests/" .. name .. ".lua"
  local f = io.open(path, "rb")
  if f then
    f:close()
    print("== " .. name)
    dofile(path)
  end
end
H.finish()
