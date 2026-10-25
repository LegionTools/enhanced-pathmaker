"""Lua 5.1 regression tests for movement samples and update error containment.

Requires lupa (also searches the temporary runtime used by test_native_minimap).
"""
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(os.environ['TEMP']) / 'pathmaker-lua-test'))
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime()
for path in root.rglob('*.lua'):
    lua.execute('assert(loadstring(...))', path.read_text(encoding='utf-8-sig'))

lua.execute('''
addon = {}
GetBuildInfo = function() return "1.60.1", "test", "", 16001 end
SlashCmdList = {}
notices, reports = {}, {}
print = function(message) notices[#notices + 1] = message end
geterrorhandler = function() return function(message) reports[#reports + 1] = message end end
debugstack = function() return "test traceback" end
''')
lua.execute(root.joinpath('Core/Compat.lua').read_text(encoding='utf-8-sig'), 'PathMaker', lua.globals().addon)
lua.execute('''
local compat = addon.Compat
local frame = {SetScript = function(self, name, callback) self[name] = callback end}
local calls, total = 0, 0
compat:SetGuardedUpdate(frame, "Test route", function(owner, elapsed)
    assert(owner == frame)
    calls = calls + 1
    total = total + elapsed
    if calls == 3 then error("movement failure") end
end)
for i = 1, 1000 do frame.OnUpdate(frame, 0.02) end
assert(calls == 3 and math.abs(total - 0.06) < 0.00001)
assert(#notices == 1 and #reports == 1)
assert(compat.updateErrors["Test route"]:find("movement failure"))
assert(compat.updateErrors["Test route"]:find("test traceback"))
-- Toggling the broken feature must not restart the flood before /reload.
compat:SetGuardedUpdate(frame, "Test route", function() error("should not run") end)
frame.OnUpdate(frame, 0.02)
assert(#reports == 1)
local healthy = 0
compat:SetGuardedUpdate(frame, "Healthy feature", function() healthy = healthy + 1 end)
frame.OnUpdate(frame, 0.02)
assert(healthy == 1)
-- An error collector that itself fails cannot cause a new per-frame error.
geterrorhandler = function() return function() error("collector failed") end end
compat:SetGuardedUpdate(frame, "Collector test", function() error("original failure") end)
assert(pcall(frame.OnUpdate, frame, 0.02))
assert(pcall(frame.OnUpdate, frame, 0.02))

local position = {x = 0.4, y = 0.5}
local worldX, worldY = 10, 20
local time = 1
C_Map = {
    GetBestMapForUnit = function() return 1 end,
    GetPlayerMapPosition = function() return position end,
}
GetTime = function() return time end
GetSubZoneText = function() return "Test zone" end
UnitPosition = function() return worldY, worldX, 0, 1 end
assert(compat:GetUnitMapPosition(1).x == 0.4)
for _, bad in ipairs({0/0, math.huge, -math.huge, "0.4", false}) do
    position = {x = bad, y = 0.5}
    assert(compat:GetUnitMapPosition(1) == nil)
end
position = {x = 0, y = 0}
assert(compat:GetUnitMapPosition(1) == nil)
local secret = {}
issecretvalue = function(value) return rawequal(value, secret) end
position = {x = secret, y = 0.5}
assert(compat:GetUnitMapPosition(1) == nil)
position = secret
assert(compat:GetUnitMapPosition(1) == nil)
position = {x = 0.4, y = 0.5}
local state = {}
local pos, moving = compat:GetStableUnitMapPosition(1, "player", state)
assert(pos.x == 0.4 and not moving)
time = 2
position.x = 0.41
pos, moving = compat:GetStableUnitMapPosition(1, "player", state)
assert(pos.x == 0.4 and not moving) -- reject stationary map drift
time = 3
worldX = 11
pos, moving = compat:GetStableUnitMapPosition(1, "player", state)
assert(pos.x == 0.41 and moving)
time = 4
worldX = math.huge
position.x = 0.42
pos = compat:GetStableUnitMapPosition(1, "player", state)
assert(pos.x == 0.42 and state.worldX == nil)
time = 5
worldX = 12
position.x = 0.43
pos = compat:GetStableUnitMapPosition(1, "player", state)
assert(pos.x == 0.43 and state.worldX == 12)
''')
lua.execute(root.joinpath('Modules/Debug.lua').read_text(encoding='utf-8-sig'), 'PathMaker', lua.globals().addon)
lua.execute('''
addon.Navigation = {GetDebugState = function() error("broken navigation state") end}
local summary = table.concat(addon.Debug:BuildSummary(), "\\n")
assert(summary:find("Paused updates"))
assert(summary:find("movement failure"))
assert(summary:find("test traceback"))
''')
print('PASS: Lua syntax, once-only errors, isolated updates, traceback retention, resilient diagnostics, finite/secret samples, movement and recovery.')
