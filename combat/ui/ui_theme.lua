-- Shared theme + drawing primitives for every GalarGmaxDex custom screen
-- (battle scene, party/bag/pokedex/etc presenters). Extracted verbatim
-- from custom_battle_scene.lua's Phase B helpers -- same colors, same
-- panel/text/cursor/HP-bar behavior -- so every screen this mod takes
-- over reads as one coherent UI instead of a pile of one-off looks.
-- Pure love.graphics helpers, no battle-specific state (battle.shown
-- glyph-code rendering stays local to custom_battle_scene.lua, since
-- that's a battle-only concept).
local Theme = {}

Theme.COLOR_PANEL = { 0.97, 0.97, 0.97, 1 }
Theme.COLOR_PANEL_LIGHT = { 1, 1, 1, 1 }
Theme.COLOR_BORDER = { 0.10, 0.10, 0.10, 1 }
Theme.COLOR_TEXT = { 0.06, 0.06, 0.06, 1 }
Theme.COLOR_TEXT_ON_LIGHT = { 0.06, 0.06, 0.06, 1 }
Theme.COLOR_MUTED = { 0.45, 0.45, 0.45, 1 }
Theme.RADIUS = 0

function Theme.setColor(c)
  love.graphics.setColor(c[1], c[2], c[3], c[4] or 1)
end

function Theme.panel(x, y, w, h, light)
  Theme.setColor(light and Theme.COLOR_PANEL_LIGHT or Theme.COLOR_PANEL)
  love.graphics.rectangle("fill", x, y, w, h)
  Theme.setColor(Theme.COLOR_BORDER)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x, y, w, h)
  love.graphics.rectangle("line", x + 1, y + 1, math.max(0, w - 2), math.max(0, h - 2))
end

local fontCache = {}
function Theme.fontOf(size)
  local f = fontCache[size]
  if not f then
    local ok, made = pcall(love.graphics.newFont, size)
    f = ok and made or love.graphics.getFont()
    fontCache[size] = f
  end
  return f
end

function Theme.printText(text, x, y, size, color)
  local prevFont = love.graphics.getFont()
  love.graphics.setFont(Theme.fontOf(size or 20))
  Theme.setColor(color or Theme.COLOR_TEXT)
  love.graphics.print(text or "", x, y)
  love.graphics.setFont(prevFont)
end

function Theme.fitName(text, pixels, size)
  text = text or ""
  local f = Theme.fontOf(size or 20)
  if f:getWidth(text) <= pixels then return text end
  local s = text
  while #s > 1 and f:getWidth(s .. ".") > pixels do
    s = s:sub(1, #s - 1)
  end
  return s .. "."
end

function Theme.drawCursor(x, y, color)
  Theme.setColor(color or Theme.COLOR_BORDER)
  love.graphics.print(">", x, y)
end

function Theme.drawHPBar(x, y, w, h, hp, maxHp)
  Theme.setColor({ 0.12, 0.13, 0.18, 1 })
  love.graphics.rectangle("fill", x, y, w, h, 4, 4)
  local frac = (maxHp and maxHp > 0) and math.max(0, math.min(1, hp / maxHp)) or 0
  local fillColor = frac > 0.5 and { 0.30, 0.82, 0.40, 1 }
    or (frac > 0.2 and { 0.95, 0.80, 0.20, 1 } or { 0.92, 0.25, 0.25, 1 })
  Theme.setColor(fillColor)
  love.graphics.rectangle("fill", x + 3, y + 3, math.max(0, (w - 6) * frac), h - 6, 3, 3)
  Theme.setColor(Theme.COLOR_BORDER)
  love.graphics.setLineWidth(1.5)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 4, 4)
end

------------------------------------------------------------------
-- Responsive scaling: every screen this mod owns was built and laid out
-- against whatever desktop window size happened to be open at the time
-- (hardcoded pixel positions/sizes/font points throughout) -- confirmed
-- live to overflow small screens (phone/Android) and look disproportionate
-- on very large ones, since none of that ever adapted to actual window
-- size. Rather than hand-multiply every one of the hundreds of literal
-- offsets/font-sizes across every screen file (error-prone, and this
-- mod's own layout math is already fine as-is), this uses the same
-- technique the ENGINE's own native UI already relies on for this exact
-- problem: draw against one fixed VIRTUAL canvas size, then scale+
-- letterbox that whole canvas to fit the real window with one transform.
-- Native screens get this for free from the 160x144 GB-canvas letterbox;
-- this is the same idea one layer up, for window-pixel-space content.
--
-- Reference size: distinct from a single min(w/refW,h/refH) scale (which
-- collapses to a tiny fraction on a narrow phone in PORTRAIT, since it's
-- constrained by the SMALL width against a desktop-sized reference) --
-- landscape (desktop/tablet) and portrait (phone) get their own
-- reference WIDTH, mirroring gen1_modern_ui's own autoScalePercent
-- (that mod's real, working solution to this same problem in this same
-- engine, confirmed via source read): a phone at ~380-420px portrait
-- width lands near scale 1.0 (the size everything was actually tuned
-- at), a desktop window lands near 1.0-1.6 depending on width, instead
-- of either overflowing or shrinking to unreadable.
Theme.REF_LANDSCAPE_W = 1000
Theme.REF_PORTRAIT_W = 380
Theme.SCALE_MIN = 0.55
Theme.SCALE_MAX = 2.5

Theme._scale = 1
Theme._offX = 0
Theme._offY = 0

local function computeScale(w, h)
  local refW = (w >= h) and Theme.REF_LANDSCAPE_W or Theme.REF_PORTRAIT_W
  local s = w / refW
  if s < Theme.SCALE_MIN then s = Theme.SCALE_MIN end
  if s > Theme.SCALE_MAX then s = Theme.SCALE_MAX end
  return s
end

-- Pure (no graphics.push/side effects): the current virtual canvas size
-- and scale, computed the same way beginScaledDraw does. For code OUTSIDE
-- a scaled-draw block that still needs to know the current bounds -- e.g.
-- clamping a dragged panel's position against the screen from an
-- input.pointer hook, which fires independently of render.hud's own draw
-- pass.
function Theme.virtualSize()
  local realW, realH = love.graphics.getDimensions()
  local s = computeScale(realW, realH)
  return realW / s, realH / s, s
end

-- Call once at the top of a render.hud hook, before any drawing. Returns
-- a virtual (w, h) to lay out against EXACTLY like a real
-- love.graphics.getDimensions() result -- every existing draw call
-- written against real window pixels keeps working unchanged, since the
-- graphics transform (not the layout math) is what adapts to the real
-- window size. Must be paired with Theme.endScaledDraw() once drawing is
-- done (love.graphics.push()/pop() underneath -- unbalanced calls leak
-- transform state into whatever draws next).
function Theme.beginScaledDraw()
  local virtualW, virtualH, s = Theme.virtualSize()
  Theme._scale = s
  Theme._offX = 0
  Theme._offY = 0
  love.graphics.push()
  love.graphics.scale(s, s)
  return virtualW, virtualH
end

function Theme.endScaledDraw()
  love.graphics.pop()
end

-- Converts a REAL window-pixel point (e.g. straight off an input.pointer
-- event) into the same virtual space Theme.beginScaledDraw()'s (w, h)
-- and every draw call inside that block are expressed in -- the input-
-- side half of the same transform, needed anywhere a screen hit-tests a
-- pointer against rects it recorded while drawing (dragging panels/
-- sprites). Safe to call outside a scaled-draw block too (uses
-- whatever scale beginScaledDraw last computed).
function Theme.windowToVirtual(px, py)
  local s = Theme._scale
  if not s or s == 0 then return px, py end
  return (px - Theme._offX) / s, (py - Theme._offY) / s
end

return Theme
