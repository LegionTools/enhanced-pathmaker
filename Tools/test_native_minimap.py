"""Lua 5.1 regression checks for native minimap restoration (requires lupa)."""
import os, sys
from pathlib import Path
sys.path.insert(0, str(Path(os.environ['TEMP'])/'pathmaker-lua-test'))
from lupa.lua51 import LuaRuntime
source=(Path(__file__).resolve().parents[1]/'UI/MapFrame.lua').read_text()
lua=LuaRuntime()
lua.execute('assert(loadstring(...))',source)
mask=source[source.index('local SQUARE_MINIMAP_MASK'):source.index('function addon.MapFrame:ApplyMinimapShape(')]
refresh=source[source.index('local function RefreshRestoredNativeMinimap()'):source.index('local function SetFarmMinimapZoomLocked(')]
lua.execute('''
addon={Compat={},MapFrame={}}
local minimapTextureRefreshGeneration=0
local minimapTextureRefreshBaseZoom
local suppressMinimapZoomSave=false
local function GetMaxMinimapZoom() return 5 end
Minimap={zoom=3,alpha=.8,shown=true,ignore=false,calls=0}
function Minimap:SetMaskTexture(mask) self.mask=mask end
function Minimap:GetZoom() return self.zoom end
function Minimap:SetZoom(zoom) self.zoom=zoom; self.calls=self.calls+1 end
function Minimap:GetAlpha() return self.alpha end
function Minimap:SetAlpha(alpha) self.alpha=alpha end
function Minimap:IsShown() return self.shown end
function Minimap:Show() self.shown=true end
function Minimap:Hide() self.shown=false end
function Minimap:GetIgnoreParentAlpha() return self.ignore end
function Minimap:SetIgnoreParentAlpha(value) self.ignore=value end
C_Timer={After=function(_,f) pending=f end}
'''+mask+refresh+'''
addon.Compat={isForever=true}
ApplyMinimapShapeMask(false)
assert(Minimap.mask==RETAIL_CIRCLE_MINIMAP_MASK)
addon.Compat={isRetail=true}
ApplyMinimapShapeMask(false)
assert(Minimap.mask==RETAIL_CIRCLE_MINIMAP_MASK)
addon.Compat={isClassicEra=true}
ApplyMinimapShapeMask(false)
assert(Minimap.mask==LEGACY_CIRCLE_MINIMAP_MASK)
ApplyMinimapShapeMask(true)
assert(Minimap.mask==SQUARE_MINIMAP_MASK)
RefreshRestoredNativeMinimap()
assert(Minimap.zoom==2)
pending()
assert(Minimap.zoom==3 and Minimap.alpha==.8 and Minimap.shown)
-- A queued refresh must never override a new PathMaker takeover.
RefreshRestoredNativeMinimap()
addon.MapFrame.ownsMinimap=true
Minimap.zoom=5
pending()
assert(Minimap.zoom==5)
''')
disable=source[source.index('function addon.MapFrame:Disable(keepFeatures)'):source.index('-- AUTO-RESTORE STATE ON LOGIN')]
assert 'self:RestoreNativeMinimapState()\n        --' in disable
assert disable.index('self:RestoreNativeMinimapState()') < disable.index('RefreshRestoredNativeMinimap()')
print('PASS: Forever/Retail/Classic masks, terrain refresh, zoom/alpha preservation, stale callback cancellation, restoration order.')
