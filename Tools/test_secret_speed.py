"""Exercise actual Farm Mode/navigation functions with an opaque speed value.

Stock Lua has no WoW secrets. A sentinel reports type 'number' and throws on
comparison to model the reported failure; this is not an in-client test.
Requires lupa, as in test_update_errors.py.
"""
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(os.environ['TEMP']) / 'pathmaker-lua-test'))
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime()
lua.execute('''
addon = {MapFrame = {}}
GetBuildInfo = function() return "1.60.1", "test", "", 16001 end
secret = setmetatable({}, {
    __lt = function() error("secret speed comparison") end,
    __le = function() error("secret speed comparison") end,
})
local normalType = type
type = function(value) if rawequal(value, secret) then return "number" end return normalType(value) end
issecretvalue = function(value) return rawequal(value, secret) end
speed = secret
GetUnitSpeed = function() return speed end
GetPlayerFacing = function() return 0 end
IsIndoors = function() return false end
EnsurePathmakerSettings = function() return {farmCircleSize=800} end
GetFarmVisibleRadiusYards = function() return 233.333328 end
GetMapCoordinateScales = function() return 3470.833252, 2314.583008 end
SmoothFarmValue = function(current, target) return current + (target-current)*0.5 end
SmoothFarmAngle = function(current, target) return target end
GetSegmentPoints = function() return {x=0,y=0}, {x=1,y=0} end
''')
lua.execute(root.joinpath('Core/Compat.lua').read_text(encoding='utf-8-sig'), 'PathMaker', lua.globals().addon)
farm_source = root.joinpath('UI/MapFrame.lua').read_text(encoding='utf-8-sig')
farm = farm_source[farm_source.index('local function GetFarmRenderPlayerPosition('):farm_source.index('local stableFarmPositionState =')]
nav_source = root.joinpath('Modules/Navigation.lua').read_text(encoding='utf-8-sig')
nav = nav_source[nav_source.index('local function UpdateDirectionFromMovement('):nav_source.index('-- REVERSE ROUTE')]

def check(farm_code, nav_code, expect_success):
    lua.execute('''
    addon.MapFrame.farmFrame = {
        pmSmoothMapID=1429, pmSmoothContext="outdoor",
        pmSmoothPlayerX=0.381683, pmSmoothPlayerY=0.624768, pmSmoothFacing=0,
    }
    navigationState = {direction=1, movementPosition={x=0.4,y=0.5}, oppositeMovementTime=0.5}
    DIRECTION_CHANGE_DELAY=2
    DIRECTION_MOVEMENT_THRESHOLD_YARDS=0.05
    DIRECTION_OPPOSITE_DOT_THRESHOLD=-0.35
    ''')
    lua.globals().farmUpdate = lua.execute(farm_code + '\nreturn GetFarmRenderPlayerPosition')
    lua.globals().navUpdate = lua.execute(nav_code + '\nreturn UpdateDirectionFromMovement')
    farm_ok = lua.eval('function() return pcall(farmUpdate,1429,{x=0.381589,y=0.624684},true,0.008) end')()[0]
    nav_ok = lua.eval('function() return pcall(navUpdate,{},1,{x=0.4,y=0.5},3470,2314,0.008) end')()[0]
    assert farm_ok == expect_success and nav_ok == expect_success

# Prove the harness catches both original type-only predicates.
check(farm.replace('not addon.Compat:IsFiniteNumber(unitSpeed)', 'type(unitSpeed) ~= "number"'),
      nav.replace('addon.Compat:IsFiniteNumber(unitSpeed)', 'type(unitSpeed) == "number"'), False)
check(farm, nav, True)
lua.execute('''
assert(addon.MapFrame.farmFrame.pmSmoothPlayerX < 0.381683)
assert(navigationState.oppositeMovementTime > 0.5)
''')
for value in (0, 7, None, float('nan'), float('inf')):
    lua.globals().speed = value
    check(farm, nav, True)
    if value == 0:
        lua.execute('assert(navigationState.oppositeMovementTime == nil)')
lua.execute('issecretvalue=nil; speed=7')
check(farm, nav, True)
print('PASS: original secret-speed failures reproduced; corrected Farm Mode and navigation pass secret, normal, missing, non-finite, and legacy-client cases.')
