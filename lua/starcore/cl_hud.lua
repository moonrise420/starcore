-- StarCore client: small pilot HUD (only while sitting in a StarCore ship's seat)
local T = StarCore.T
local U = StarCore.Units
local myCore, nextFind = nil, 0

local function findCore()
	local ply = LocalPlayer()
	if not ply:InVehicle() then return nil end
	local veh = ply:GetVehicle()
	local c = veh:GetNWEntity("starcore")
	if IsValid(c) then return c end
	for _, k in ipairs(ents.FindByClass("starcore")) do
		if k:GetNWEntity("starcore_pilotseat") == veh then return k end
	end
end

local function shipCore()
	if CurTime() > nextFind then myCore = findCore(); nextFind = CurTime() + 0.5 end
	return myCore
end

-- mouse steering: in the pilot seat the mouse flies the ship, so the view stays still (the look-around key frees it)
local cvMouse = GetConVar("starcore_mouse_steer")

-- keys of the pilot seat (a Workshop player: "make look around on mouse steering toggleable or to the same effect
-- keybinds for things like mouse steering and hover"). Picked in the menu's Settings tab, 0 = no key. Look
-- around = Alt by default, held or tapped on/off (starcore_look_toggle): the view is free and the helm ignores the
-- mouse (starcore_looking tells the server, sv_helm.lua). Also console commands for binds: starcore_toggle_look/_mouse/_hover/_freeze.
local cvKeyLook, cvKeyMouse, cvKeyHover = GetConVar("starcore_key_look"), GetConVar("starcore_key_mouse"), GetConVar("starcore_key_hover")
local cvKeyFreeze = GetConVar("starcore_key_freeze")   -- (same comment, edited: "un-/freeze the whole ship with a keybind")
local cvKeyTractor, cvKeyCloak = GetConVar("starcore_key_tractor"), GetConVar("starcore_key_cloak")   --
local cvKeyDock = GetConVar("starcore_key_dock")   -- (carriers, sv_dock.lua)
local cvKeyPull, cvKeyPush = GetConVar("starcore_key_tractor_pull"), GetConVar("starcore_key_tractor_push")   --
local cvLookToggle = GetConVar("starcore_look_toggle")
StarCore.Looking = false
local function setLooking(on)
	if StarCore.Looking == on then return end
	StarCore.Looking = on
	RunConsoleCommand("starcore_looking", on and "1" or "0")
end
local function pilotCore()
	local ply = LocalPlayer()
	if not IsValid(ply) or not ply:InVehicle() then return nil end
	local core = shipCore()
	if IsValid(core) and core:GetNWEntity("starcore_pilotseat") == ply:GetVehicle() then return core end
end
local function toggleMouse()
	RunConsoleCommand("starcore_mouse_steer", cvMouse:GetBool() and "0" or "1")
	setLooking(false)
	surface.PlaySound("buttons/lightswitch2.wav")
end
local function sendToggle(core, cmd, nw)
	net.Start("starcore_cmd")
	net.WriteEntity(core)
	net.WriteString(cmd)
	net.WriteTable({ on = not core:GetNWBool(nw), quiet = true })
	net.SendToServer()
	surface.PlaySound("buttons/lightswitch2.wav")
end
local function toggleHover(core) sendToggle(core, "hover", "starcore_hover") end
local function toggleFreeze(core) sendToggle(core, "freeze", "starcore_frozen") end   -- (only while hovering, like the menu button)
local function toggleCloak(core) sendToggle(core, "cloak", "starcore_cloaked") end
local function toggleDock(core) sendToggle(core, "dock", "starcore_docked") end   -- (the server decides: dock or let go)

-- the camera the pilot sees right now (also third person, look-around, menu open): the tractor beam aims with it, the
-- thing nearest the middle of the screen (sv_systems.lua TractorPick, sv_net.lua viewOf)
local viewO, viewD
hook.Add("RenderScene", "StarCore.View", function(origin, ang) viewO, viewD = origin, ang:Forward() end)
function StarCore.ViewNow()
	if viewO then return viewO, viewD end
	return EyePos(), EyeVector()
end
-- tractor key: grab what you look at, or let go when the beam holds something
-- pull / push keys: the held thing is pulled in / pushed away; nothing held: grab what you look at and pull / push it;
-- the same key again: it is just held (sv_net.lua handlers.tractor)
local function toggleTractor(core, mode)
	local o, d = StarCore.ViewNow()
	net.Start("starcore_cmd")
	net.WriteEntity(core)
	net.WriteString("tractor")
	if mode then net.WriteTable({ mode = mode, key = true, vo = o, vd = d })
	else net.WriteTable({ mode = "hold", toggle = true, vo = o, vd = d }) end
	net.SendToServer()
	surface.PlaySound("buttons/lightswitch2.wav")
end
local held = {}
local function keyEdge(cv)   -- pressed now, released now, held
	local k = cv:GetInt()
	local down = k > 0 and input.IsButtonDown(k) or false
	local was = held[cv] or false
	held[cv] = down
	return down and not was, was and not down, down
end
hook.Add("Think", "StarCore.Keys", function()
	local lookPress, lookRelease = keyEdge(cvKeyLook)
	local mousePress = keyEdge(cvKeyMouse)
	local hoverPress = keyEdge(cvKeyHover)
	local freezePress = keyEdge(cvKeyFreeze)
	local tractorPress = keyEdge(cvKeyTractor)
	local cloakPress = keyEdge(cvKeyCloak)
	local dockPress = keyEdge(cvKeyDock)
	local pullPress, pushPress = keyEdge(cvKeyPull), keyEdge(cvKeyPush)
	local core = pilotCore()
	if not core then setLooking(false) return end   -- (left the seat: mouse steering is back next time)
	local ply = LocalPlayer()
	-- typing in chat, a text box, the console, a menu, or picking a key in the settings: keys do nothing
	if vgui.GetKeyboardFocus() or gui.IsGameUIVisible() or gui.IsConsoleVisible() or input.IsKeyTrapping() or ply:IsTyping() then return end
	if cvLookToggle:GetBool() then
		if lookPress then setLooking(not StarCore.Looking) end
	elseif lookPress then setLooking(true)
	elseif lookRelease then setLooking(false) end
	if mousePress then toggleMouse() end
	if hoverPress then toggleHover(core) end
	if freezePress then toggleFreeze(core) end
	if tractorPress then toggleTractor(core) end
	if cloakPress then toggleCloak(core) end
	if dockPress then toggleDock(core) end
	if pullPress then toggleTractor(core, "pull") end
	if pushPress then toggleTractor(core, "push") end
end)
-- Aim: auto = the weapons go for the radar target; crosshair = they go for the point under the crosshair
-- (sv_combat.lua, fireAtPoint). Gunners start on the crosshair, the pilot on auto; starcore_key_aim (middle
-- mouse) switches. While on the crosshair the point is sent to the server 10 times a second.
local cvKeyAim = GetConVar("starcore_key_aim")
StarCore.AimManual = false
local aimSeat, nextAim = nil, 0
-- the line under the crosshair says how the weapons aim only for a few seconds: after sitting down and after a switch
-- On sitting down only the first time in a game; after a switch for 3 seconds
-- (it says which aim is on).
--
local AIM_HINT, AIM_HINT_SWITCH = 6, 3
local aimHintUntil, aimHintShown = 0, false
local function crewSeat()
	local ply = LocalPlayer()
	if not ply:InVehicle() then return end
	local veh = ply:GetVehicle()
	local c = veh:GetNWEntity("starcore")
	if not IsValid(c) then return end
	local role = veh:GetNWString("starcore_role", "passenger")
	if role ~= "gunner" and role ~= "pilot" then return end
	return c, veh, role
end
local function toggleAim()
	if not crewSeat() then return end
	StarCore.AimManual = not StarCore.AimManual
	aimHintUntil = CurTime() + AIM_HINT_SWITCH
	surface.PlaySound("buttons/lightswitch2.wav")
end
hook.Add("Think", "StarCore.AimKey", function()
	local press = keyEdge(cvKeyAim)
	local core, veh, role = crewSeat()
	if not core then aimSeat = nil StarCore.AimManual = false return end
	if veh ~= aimSeat then
		aimSeat = veh
		StarCore.AimManual = role == "gunner"
		if not aimHintShown then aimHintShown = true aimHintUntil = CurTime() + AIM_HINT end
	end
	local ply = LocalPlayer()
	if vgui.GetKeyboardFocus() or gui.IsGameUIVisible() or gui.IsConsoleVisible() or input.IsKeyTrapping() or ply:IsTyping() then return end
	if press then toggleAim() end
end)
concommand.Add("starcore_toggle_aim", toggleAim)
-- (in a drawing hook: EyePos / EyeAngles are the view as drawn - also SpaceGrid's view from behind the ship)
hook.Add("HUDPaint", "StarCore.Aim", function()
	local core = crewSeat()
	if not core then return end
	local cx, cy = ScrW() / 2, ScrH() / 2
	local keyName = (cvKeyAim:GetInt() > 0 and input.GetKeyName(cvKeyAim:GetInt()) or "-")
	if StarCore.AimManual then
		if CurTime() >= nextAim then
			nextAim = CurTime() + 0.1
			-- (where the view is and where it looks: the server traces the line past every part of the own ship,
			-- sv_combat.lua - this game does not know all of them)
			net.Start("starcore_aim") net.WriteVector(EyePos()) net.WriteNormal(EyeAngles():Forward()) net.SendToServer()
		end
		surface.SetDrawColor(120, 220, 255, 230)
		surface.DrawLine(cx - 12, cy, cx - 4, cy) surface.DrawLine(cx + 4, cy, cx + 12, cy)
		surface.DrawLine(cx, cy - 12, cx, cy - 4) surface.DrawLine(cx, cy + 4, cx, cy + 12)
		if CurTime() < aimHintUntil then
			draw.SimpleTextOutlined(T("aim_manual", string.upper(keyName)), "DermaDefaultBold", cx, cy + 40, Color(120, 220, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
		end
	elseif CurTime() < aimHintUntil then
		draw.SimpleTextOutlined(T("aim_auto", string.upper(keyName)), "DermaDefault", cx, cy + 40, Color(220, 220, 220, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
	end
end)
concommand.Add("starcore_toggle_look", function() if pilotCore() then setLooking(not StarCore.Looking) end end)
concommand.Add("starcore_toggle_mouse", function() toggleMouse() end)
concommand.Add("starcore_toggle_hover", function() local c = pilotCore() if c then toggleHover(c) end end)
concommand.Add("starcore_toggle_freeze", function() local c = pilotCore() if c then toggleFreeze(c) end end)
concommand.Add("starcore_toggle_tractor", function() local c = pilotCore() if c then toggleTractor(c) end end)
concommand.Add("starcore_toggle_cloak", function() local c = pilotCore() if c then toggleCloak(c) end end)
concommand.Add("starcore_toggle_dock", function() local c = pilotCore() if c then toggleDock(c) end end)
concommand.Add("starcore_tractor_pull", function() local c = pilotCore() if c then toggleTractor(c, "pull") end end)
concommand.Add("starcore_tractor_push", function() local c = pilotCore() if c then toggleTractor(c, "push") end end)

-- the tractor beam can be seen (it was not clear what it held): a soft light beam from the ship to the held thing for
-- everyone; for the crew of the ship also an outline around it
local beamMat = Material("sprites/physbeama")
local glowMat = Material("sprites/light_glow02_add")
local BEAM = Color(120, 200, 255)
local holding = {}   -- core -> held entity (refreshed twice a second)
local nextScan = 0
local function tractors()
	if CurTime() > nextScan then
		nextScan = CurTime() + 0.5
		holding = {}
		for _, c in ipairs(ents.FindByClass("starcore")) do
			local e = c:GetNWEntity("starcore_tractor")
			if IsValid(e) then holding[c] = e end
		end
	end
	return holding
end
local function shipMiddle(core)
	local mn, mx = core:GetNWVector("starcore_lmins"), core:GetNWVector("starcore_lmaxs")
	return core:LocalToWorld((mn + mx) * 0.5)
end
hook.Add("PostDrawTranslucentRenderables", "StarCore.TractorBeam", function(depth, sky)
	if sky then return end
	for core, e in pairs(tractors()) do
		if IsValid(core) and IsValid(e) and not core:GetNWBool("starcore_cloaked") then
			local a, b = shipMiddle(core), e:WorldSpaceCenter()
			local wob = 1 + math.sin(CurTime() * 6) * 0.15
			render.SetMaterial(beamMat)
			render.DrawBeam(a, b, 26 * wob, CurTime() * 2, CurTime() * 2 + a:Distance(b) / 256, Color(BEAM.r, BEAM.g, BEAM.b, 90))
			render.DrawBeam(a, b, 9, -CurTime() * 3, -CurTime() * 3 + a:Distance(b) / 128, Color(220, 240, 255, 140))
			render.SetMaterial(glowMat)
			local r = math.max((e:OBBMaxs() - e:OBBMins()):Length() * 0.7, 48)
			render.DrawSprite(b, r * wob, r * wob, Color(BEAM.r, BEAM.g, BEAM.b, 70))
		end
	end
end)
hook.Add("PreDrawHalos", "StarCore.TractorHalo", function()
	local core = shipCore()
	local e = IsValid(core) and core:GetNWEntity("starcore_tractor")
	if IsValid(e) then halo.Add({ e }, BEAM, 2, 2, 1, true, true) end
end)

local cvFree, cvDirect = GetConVar("starcore_free_flight"), GetConVar("starcore_direct_flight")
hook.Add("InputMouseApply", "StarCore.MouseSteer", function(cmd, x, y, ang)
	if not (cvMouse:GetBool() or (cvFree and cvFree:GetBool()) or (cvDirect and cvDirect:GetBool())) or StarCore.Looking then return end
	local core = shipCore()
	local ply = LocalPlayer()
	if not IsValid(core) or not ply:InVehicle() or core:GetNWEntity("starcore_pilotseat") ~= ply:GetVehicle() then return end
	if not core:GetNWBool("starcore_hover") then return end
	return true -- mouse moves still reach the server (cmd mouse x/y), only the view does not turn
end)

-- pilot HUD. It sits in the band of the game's health box: the game lays its HUD out on a 640x480 base that grows with
-- the screen height (health box 16..118 wide, 432..468 high; armour box up to 248). Ours stands centred in that band,
-- two rows. starcore_hud_look picks the look: 1 slim, no box (the default), 2 the ship's theme, 3 panels with gauges
-- (picked the slim one and left the Stargate ships' plate out again). Second round: every
-- style is as wide as its texts need (need2..need4 below; the slim look 1 uses need4), centred, at most up to the
-- health / armour box (and as far on the right). Only past that limit the least
-- important text ends in "…". starcore_hud_measure prints the widths.
--
--
--
local cvHud, cvStyle = GetConVar("starcore_hud"), GetConVar("starcore_hud_look")
local F_TITLE, F_TEXT, F_SMALL = "StarCoreHUD", "StarCoreHUDText", "StarCoreHUDSmall"
local F4_TITLE, F4_TEXT, F4_SMALL = "StarCoreHUD4", "StarCoreHUD4Text", "StarCoreHUD4Small"   -- the slim style: a bit bigger
local LEFT, CENTER, RIGHT = TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, TEXT_ALIGN_RIGHT
local round, floor, ceil, max, min = math.Round, math.floor, math.ceil, math.max, math.min
local FTL = StarCore.FTL

local clip = {}   -- slot -> the last text fitted into a width (see fit)
local shownW = 0  -- the width the HUD has right now (see calmWidth)
-- fonts grow with the screen height like the game's HUD (720p: 18 / 15 / 14 px, the slim style 20 / 16 / 15 px; no
-- text under 14 px at 720p); made again when the screen size changes
local function makeFonts()
	local s = ScrH() / 480
	surface.CreateFont(F_TITLE, { font = "Roboto", size = max(round(12 * s), 14), weight = 700, extended = true })
	surface.CreateFont(F_TEXT, { font = "Roboto", size = max(round(10 * s), 12), weight = 500, extended = true })
	surface.CreateFont(F_SMALL, { font = "Roboto", size = max(round(9.4 * s), 11), weight = 500, extended = true })
	surface.CreateFont(F4_TITLE, { font = "Roboto", size = max(round(13.4 * s), 15), weight = 700, extended = true })
	surface.CreateFont(F4_TEXT, { font = "Roboto", size = max(round(10.7 * s), 13), weight = 500, extended = true })
	surface.CreateFont(F4_SMALL, { font = "Roboto", size = max(round(10 * s), 12), weight = 500, extended = true })
	for k in pairs(clip) do clip[k] = nil end
	shownW = 0
end
makeFonts()
hook.Add("OnScreenSizeChanged", "StarCore.HUDFonts", makeFonts)

local SHADOW = Color(0, 0, 0, 200)
local WARN = Color(255, 90, 70)
-- one line of text, centred on y; returns its width
local function text(str, font, x, y, col, ax, shadow)
	if shadow then draw.SimpleText(str, font, x + 1, y + 1, SHADOW, ax, CENTER) end
	return (draw.SimpleText(str, font, x, y, col, ax, CENTER))
end
local function width(str, font)
	surface.SetFont(font)
	return (surface.GetTextSize(str))
end
-- makes a text fit into maxw: first the smaller font (when given), then cut with "…". Returns text, font, width.
-- The result is kept per slot, so the cutting only runs when the text or the room changes.
local function fit(slot, str, font, small, maxw)
	local c = clip[slot]
	if not c then c = {} clip[slot] = c end
	if c.src ~= str or c.font ~= font or c.maxw ~= maxw then
		c.src, c.font, c.maxw = str, font, maxw
		local f, out = font, str
		local w = width(out, f)
		if w > maxw and small then f = small w = width(out, f) end
		if w > maxw then
			local n = utf8.len(str) or #str
			while n > 1 and w > maxw do
				n = n - 1
				out = string.sub(str, 1, (utf8.offset(str, n + 1) or (n + 1)) - 1) .. "…"
				w = surface.GetTextSize(out)
			end
		end
		c.out, c.f, c.w = out, f, w
	end
	return c.out, c.f, c.w
end
-- a thin bar: the track, and the filled part on it
local function bar(x, y, w, h, frac, track, fill)
	surface.SetDrawColor(track)
	surface.DrawRect(x, y, w, h)
	if frac > 0 then
		surface.SetDrawColor(fill)
		surface.DrawRect(x, y, max(round(w * frac), 1), h)
	end
end

-- what the HUD shows, read once per frame into one table that is used again (no new tables per frame).
-- gauge = hull, power, shield (kind 1, 2, 3), only the ones the ship has: text, 0..1 and "low" each.
-- hint = the small "R = menu" hint, or the self-destruct countdown in its place (alert = true: red, bigger).
-- frac = the charge of the jump drive: rises while charging, stays 1 when charged and during the jump, 0 after it.
local H = { gauge = {}, gfrac = {}, gwarn = {}, gkind = {}, n = 0 }
local function gauge(kind, str, frac, warn)
	local n = H.n + 1
	H.n = n
	H.gauge[n], H.gfrac[n], H.gwarn[n], H.gkind[n] = str, math.Clamp(frac, 0, 1), warn, kind
end
-- the name of the ship we are docked in, at most StarCore.NameShow letters like every name on the HUD
local dockSrc, dockOut
local function dockName(name)
	if name ~= dockSrc then
		dockSrc, dockOut = name, name
		local n = utf8.len(name)
		if n and n > StarCore.NameShow then
			dockOut = string.sub(name, 1, (utf8.offset(name, StarCore.NameShow) or StarCore.NameShow) - 1) .. "…"
		end
	end
	return dockOut
end
local function gather(core, ply)
	local veh = ply:GetVehicle()
	-- the ship's name instead of "StarCore" (ship names and classes)
	local title = StarCore.ShipTitle and StarCore.ShipTitle(core) or ""
	if title == "" then title = "StarCore" end
	local role = veh:GetNWString("starcore_role", "pilot")
	if role ~= "pilot" then title = title .. " · " .. T("role_" .. role) end
	H.title = title

	local state = core:GetNWBool("starcore_hover") and T("hover_on") or T("hover_off")
	if core:GetNWBool("starcore_frozen") then state = state .. " · " .. T("frozen") end
	if core:GetNWBool("starcore_autopilot") then state = state .. " · " .. T("autopilot") end
	if core:GetNWBool("starcore_cloaked") then state = state .. " · " .. T("cloaked") end
	if IsValid(core:GetNWEntity("starcore_docked")) then state = T("hud_docked", dockName(core:GetNWString("starcore_docked_name", "?"))) end
	if (cvMouse:GetBool() or (cvFree and cvFree:GetBool()) or (cvDirect and cvDirect:GetBool())) and core:GetNWEntity("starcore_pilotseat") == veh then state = state .. " · " .. T(StarCore.Looking and "hud_look" or "hud_mouse") end
	H.state = state

	H.speed = T("hud_speed", U.Speed(core:GetNWFloat("starcore_speed")))
	H.alt = T("hud_alt", U.Alt(core:GetNWFloat("starcore_alt")))
	-- the charge line: StarCore.FTLText gives a rising part while charging, 1 while jumping, 0 in the cooldown and
	-- when ready; the state is read here too, so the line is full for the whole jump and gone right after it,
	-- whatever arrives first from the server
	local ftl, frac = StarCore.FTLText(core)
	local st = core:GetNWInt("starcore_ftl")
	if st == FTL.JUMPING then frac = 1 elseif st ~= FTL.CHARGING then frac = 0 end
	H.ftl, H.frac = ftl, math.Clamp(frac or 0, 0, 1)

	H.n = 0
	local hmax = core:GetNWInt("starcore_hull_max")
	if hmax > 0 then
		local hp = core:GetNWInt("starcore_hull") / hmax * 100
		gauge(1, T("hud_hull", floor(hp)), hp / 100, hp < 30)
	end
	local pct = core:GetNWFloat("starcore_power_pct", -1)
	if pct >= 0 then gauge(2, T("hud_power", floor(pct)), pct / 100, pct < 15) end
	if core:GetNWInt("starcore_shields") > 0 then
		if core:GetNWBool("starcore_shield_up") then
			local str = core:GetNWFloat("starcore_shield_strength")
			gauge(3, T("hud_shield", floor(str)), str / 100, false)
		else
			gauge(3, T("hud_shield_off"), 0, false)
		end
	end
	-- the self-destruct countdown takes the place of the small "R = menu" hint while it runs
	local destruct = core:GetNWFloat("starcore_destruct")
	H.alert = destruct > CurTime()
	H.hint = H.alert and T("hud_destruct", ceil(destruct - CurTime())) or T("hud_hint")
end

-- the small hint (or the countdown in red), right-aligned at x; returns its width
local function hintRight(x, y, col, shadow)
	if H.alert then return text(H.hint, F_TEXT, x, y, WARN, RIGHT, shadow) end
	return text(H.hint, F_SMALL, x, y, col, RIGHT, shadow)
end
local function hintWidth() return width(H.hint, H.alert and F_TEXT or F_SMALL) end
-- speed, height and the gauges as texts one after another from x (first = 1 with speed and height, 2 without);
-- returns the x after the last one (a gap included)
local function flow(first, x, y, font, gap, col, shadow)
	if first == 1 then
		x = x + text(H.speed, font, x, y, col, LEFT, shadow) + gap
		x = x + text(H.alt, font, x, y, col, LEFT, shadow) + gap
	end
	for i = 1, H.n do
		x = x + text(H.gauge[i], font, x, y, H.gwarn[i] and WARN or col, LEFT, shadow) + gap
	end
	return x
end
local function flowWidth(first, font, gap)
	surface.SetFont(font)
	local w = 0
	if first == 1 then w = surface.GetTextSize(H.speed) + surface.GetTextSize(H.alt) + gap * 2 end
	for i = 1, H.n do w = w + surface.GetTextSize(H.gauge[i]) + gap end
	return w
end
local function themeOf(core)
	return StarCore.Themes[core:GetNWInt("starcore_theme", 1)] or StarCore.Themes[1]
end

-- Every style has two parts that belong together: needN(s) = the width its texts need right now (what H holds, the
-- paddings and gaps of the style included), and styleN(...) that draws it into the width it got. HUDPaint asks needN
-- for the width, starcore_hud_measure asks the same needN with the longest texts. When the width is the needed one
-- nothing is cut; when the limit made it narrower, styleN shortens the state line first, then the name.
local M = {}   -- what needN worked out for styleN of the same frame

-- style 2: the ship's theme (StarCore.Themes) - the name and state on a tab in the accent colour, the numbers on the
-- theme's dark panel right of it. Charge: the accent colour runs along the bottom of the panel.
local themeCols = {}   -- theme -> the extra colours made from it (once)
local function need2(s)
	local pad, gap = round(7 * s), round(8 * s)
	local tab = max(width(H.title, F_TITLE), width(H.state, F_SMALL)) + pad * 2
	local r1 = width(H.speed, F_TEXT) + gap + width(H.alt, F_TEXT) + gap * 2 + width(H.ftl, F_TEXT)
	local r2 = flowWidth(2, F_TEXT, gap) + gap + hintWidth()
	M.right = max(r1, r2) + pad * 2
	return tab + M.right
end
local function styleTheme(core, x, y, w, h, s)
	local th = themeOf(core)
	local tc = themeCols[th]
	if not tc then
		tc = {
			bg = Color(th.bg.r, th.bg.g, th.bg.b, 220), dim = Color(th.fg.r, th.fg.g, th.fg.b, 150),
			sub = Color(th.title.r, th.title.g, th.title.b, 215), track = Color(th.fg.r, th.fg.g, th.fg.b, 40),
		}
		themeCols[th] = tc
	end
	local pad, gap = round(7 * s), round(8 * s)
	local y1, y2 = y + round(h * 0.3), y + round(h * 0.7)

	-- the tab is as wide as its text; it gets what the numbers leave, at least 30 % of the HUD
	local room = max(w - M.right, floor(w * 0.3)) - pad * 2
	local tx, tf, tw = fit("title", H.title, F_TITLE, F_TEXT, room)
	local sx, sf, sw = fit("state", H.state, F_SMALL, nil, room)
	local cw = max(tw, sw) + pad * 2
	draw.RoundedBoxEx(8, x, y, cw, h, th.accent, true, false, true, false)
	draw.RoundedBoxEx(8, x + cw, y, w - cw, h, tc.bg, false, true, false, true)
	text(tx, tf, x + pad, y1, th.title, LEFT)
	text(sx, sf, x + pad, y2, tc.sub, LEFT)

	local x0, x1 = x + cw + pad, x + w - pad
	local ex = x0 + text(H.speed, F_TEXT, x0, y1, th.fg, LEFT) + gap
	ex = ex + text(H.alt, F_TEXT, ex, y1, th.fg, LEFT) + gap
	local fx, ff = fit("ftl", H.ftl, F_TEXT, F_SMALL, x1 - ex)
	text(fx, ff, x1, y1, th.fg, RIGHT)

	local hw = hintRight(x1, y2, tc.dim)
	local f2 = (flowWidth(2, F_TEXT, gap) > x1 - hw - x0) and F_SMALL or F_TEXT
	flow(2, x0, y2, f2, gap, th.fg)
	if H.frac > 0 then bar(x + cw, y + h - round(2 * s), w - cw - 8, round(2 * s), H.frac, tc.track, th.accent) end
	return tc.bg, 4
end

-- style 3: three small dark panels - ship and state | speed and height | gauges: the jump drive with its charge bar,
-- below it hull, power and shield, each with a small coloured bar.
local BG3 = Color(12, 16, 22, 205)
local FG3, DIM3, TRACK3 = Color(235, 240, 245), Color(165, 175, 188), Color(255, 255, 255, 32)
local FTL3 = Color(140, 220, 255)
local GAUGE3 = { Color(110, 220, 130), Color(255, 200, 80), Color(90, 200, 255) }   -- hull, power, shield
local function need3(s)
	local pad, g, gg = round(6 * s), round(3 * s), round(6 * s)
	M.a = max(width(H.title, F_TITLE), width(H.state, F_SMALL)) + pad * 2
	-- (the middle panel in steps, so it does not twitch with every digit of the speed)
	local step = round(12 * s)
	M.b = ceil((max(width(H.speed, F_TEXT), width(H.alt, F_TEXT)) + pad * 2) / step) * step
	local n, cell = H.n, 0
	surface.SetFont(F_SMALL)
	for i = 1, n do
		local gw = surface.GetTextSize(H.gauge[i])
		cell = max(cell, gw)
	end
	local r1 = width(H.ftl, F_SMALL) + pad + hintWidth()
	M.c = max(r1, cell * n + gg * (n - 1)) + pad * 2
	return M.a + M.b + M.c + g * 2
end
local function styleGauges(x, y, w, h, s)
	local pad, g = round(6 * s), round(3 * s)
	-- the left panel is as wide as its texts (shorter only when the HUD may not be as wide as it needs), the right
	-- panel takes the rest
	local wb = M.b
	local wa = min(M.a, max(w - wb - M.c - g * 2, floor(w * 0.28)))
	local xb, xc = x + wa + g, x + wa + wb + g * 2
	local wc = x + w - xc
	local y1, y2 = y + round(h * 0.3), y + round(h * 0.7)
	draw.RoundedBox(4, x, y, wa, h, BG3)
	draw.RoundedBox(4, xb, y, wb, h, BG3)
	draw.RoundedBox(4, xc, y, wc, h, BG3)

	local tx, tf = fit("title", H.title, F_TITLE, F_TEXT, wa - pad * 2)
	text(tx, tf, x + pad, y1, FG3, LEFT)
	local sx, sf = fit("state", H.state, F_SMALL, nil, wa - pad * 2)
	text(sx, sf, x + pad, y2, DIM3, LEFT)

	text(H.speed, F_TEXT, xb + pad, y1, FG3, LEFT)
	text(H.alt, F_TEXT, xb + pad, y2, FG3, LEFT)

	-- gauges; without hull, power and shield the jump drive stands in the middle of the panel
	local n = H.n
	local x0, x1 = xc + pad, xc + wc - pad
	local bh = max(round(1.5 * s), 2)
	local ty = y + round(h * (n > 0 and 0.23 or 0.38))
	local hw = hintRight(x1, ty, DIM3)
	local fx, ff = fit("ftl", H.ftl, F_SMALL, nil, x1 - x0 - hw - pad)
	text(fx, ff, x0, ty, FG3, LEFT)
	bar(x0, y + round(h * (n > 0 and 0.42 or 0.62)), x1 - x0, bh, H.frac, TRACK3, FTL3)
	if n > 0 then
		local gg = round(6 * s)
		local cell = (x1 - x0 - gg * (n - 1)) / n
		for i = 1, n do
			local gx = floor(x0 + (i - 1) * (cell + gg))
			local gt, gf = fit(i, H.gauge[i], F_SMALL, nil, floor(cell))
			text(gt, gf, gx, y + round(h * 0.67), H.gwarn[i] and WARN or FG3, LEFT)
			bar(gx, y + round(h * 0.87), floor(cell), bh, H.gfrac[i], TRACK3, H.gwarn[i] and WARN or GAUGE3[H.gkind[i]])
		end
	end
	return BG3, 4
end

-- style 4 (the default): slim, no box - two centred rows of white / light blue text with a shadow on a soft dark
-- fade, a hair line between the rows. Charge: the hair line fills up in light blue and stays so until the jump is over.
local fadeMat = Material("gui/center_gradient")
local FG4, ACC4, DIM4 = Color(255, 255, 255), Color(140, 220, 255), Color(205, 215, 225, 210)
local function fade(x, y, w, h)
	surface.SetMaterial(fadeMat)
	surface.SetDrawColor(0, 0, 0, 215)
	surface.DrawTexturedRect(x, y, w, h)
	surface.DrawTexturedRect(x, y, w, h)   -- (twice: one layer is too thin on a bright sky)
end
local function need4(s)
	local pad, gap = round(16 * s), round(9 * s)
	local r1 = width(H.title, F4_TITLE) + gap + width(H.state, F4_TEXT) + gap * 2 + width(H.hint, H.alert and F4_TEXT or F4_SMALL)
	local r2 = flowWidth(1, F4_TEXT, gap) + width(H.ftl, F4_TEXT)
	return max(r1, r2) + pad * 2
end
local function styleSlim(x, y, w, h, s)
	local pad, gap = round(16 * s), round(9 * s)
	local room = w - pad * 2
	local x0, mid = x + pad, x + w / 2
	local y1, y2 = y + round(h * 0.26), y + round(h * 0.76)
	fade(x, y, w, h)

	-- row 1: ship, state, hint - centred as one piece
	local hf = H.alert and F4_TEXT or F4_SMALL
	local hw = width(H.hint, hf)
	local sx, sf, sw = fit("state", H.state, F4_TEXT, F4_SMALL, max(room - width(H.title, F4_TITLE) - hw - gap * 3, round(40 * s)))
	local tx, tf, tw = fit("title", H.title, F4_TITLE, F4_TEXT, room - sw - hw - gap * 3)
	local px = floor(mid - (tw + sw + hw + gap * 3) / 2)
	text(tx, tf, px, y1, FG4, LEFT, true)
	text(sx, sf, px + tw + gap, y1, ACC4, LEFT, true)
	text(H.hint, hf, px + tw + sw + gap * 3, y1, H.alert and WARN or DIM4, LEFT, true)

	surface.SetDrawColor(255, 255, 255, 50)
	surface.DrawRect(x0, y + floor(h * 0.5), room, 1)
	if H.frac > 0 then
		surface.SetDrawColor(ACC4)
		surface.DrawRect(x0, y + floor(h * 0.5) - 1, max(round(room * H.frac), 1), max(round(1.5 * s), 3))
	end

	-- row 2: speed, height, hull, power, shield, jump drive - centred as one piece
	local f2 = (flowWidth(1, F4_TEXT, gap) + width(H.ftl, F4_TEXT) > room) and F4_SMALL or F4_TEXT
	local lw = flowWidth(1, f2, gap)
	local fx, ff, fw = fit("ftl", H.ftl, f2, F4_SMALL, room - lw)
	px = floor(mid - (lw + fw) / 2)
	flow(1, px, y2, f2, gap, FG4, true)
	text(fx, ff, px + lw, y2, ACC4, LEFT, true)
end
local NEED = { need4, need2, need3 }   -- (look 1 = the slim style, drawn by need4 / styleSlim)

-- the widest the HUD may be: centred, it must not reach the health box (the armour box when the player has armour),
-- and it goes as far on the right
local function limitWidth(scrw, s, armour)
	return 2 * (floor(scrw / 2) - floor(((armour and 248 or 118) + 8) * s))
end
-- the width to draw with: the needed one in steps (so a digit more or less does not move the edges), at most the
-- limit; it grows at once, and gets narrower only after the texts have been shorter for a moment, then gliding
local shownStyle, shrinkAt, lastPaint = 0, 0, 0
local function calmWidth(need, limit, s, style)
	local now = RealTime()
	if style ~= shownStyle or now - lastPaint > 1 then shownW = 0 end   -- (another look, or just sat down: no gliding)
	shownStyle, lastPaint = style, now
	local step = round(12 * s)
	local target = min(ceil(need / step) * step, limit)
	if target >= shownW or shownW > limit then
		shownW, shrinkAt = target, now + 0.6
	elseif now > shrinkAt then
		shownW = max(shownW - max((shownW - target) * 5, 60 * s) * RealFrameTime(), target)
	end
	return floor(shownW)
end

-- target line: a small tag just above the HUD (far below the crosshair), text in the IFF colour.
-- bg = the colour of the style's box and how round its corners are, nil = the soft fade of the slim style.
local function drawTarget(core, mid, bottom, maxw, s, bg, corner)
	local target = core:GetNWEntity("starcore_target")
	if not IsValid(target) then return end
	local data = StarCore.Radar and StarCore.Radar[core]
	local c
	if data and data.list then
		for _, k in ipairs(data.list) do if k.ent == target then c = k break end end
	end
	local name = c and StarCore.ContactName(c) or target:GetClass()
	local dist = U.Dist(target:GetPos():Distance(core:GetPos()))
	local iff = c and T(StarCore.IFFKEY[c.iff]) or ""
	local col = c and StarCore.IFFCOL[c.iff] or color_white
	local txt = T("hud_target", name, dist, iff)
	if core:GetNWBool("starcore_engaging") then txt = txt .. "   " .. T("hud_firing") end

	local pad, th = round(6 * s), round(13 * s)
	local tx, tf, tw = fit("target", txt, F_TEXT, F_SMALL, maxw - pad * 2)
	local bx, by = floor(mid - tw / 2) - pad, bottom - th
	if bg then
		draw.RoundedBox(corner, bx, by, tw + pad * 2, th, bg)
	else
		fade(bx - pad * 2, by, tw + pad * 6, th)
	end
	text(tx, tf, bx + pad, by + floor(th / 2), col, LEFT, true)
end

hook.Add("HUDPaint", "StarCore.HUD", function()
	if not cvHud:GetBool() then return end
	local core = shipCore()
	local ply = LocalPlayer()
	if not IsValid(core) or not ply:InVehicle() then return end
	gather(core, ply)

	-- the band of the health box, centred, as wide as the texts of the style need
	local scrw, s = ScrW(), ScrH() / 480
	local y, h = floor(432 * s), floor(36 * s)
	local style = math.Clamp(cvStyle:GetInt(), 1, 3)
	local limit = limitWidth(scrw, s, ply:Armor() > 0)
	local w = calmWidth(NEED[style](s), limit, s, style)
	local x = floor(scrw / 2 - w / 2)

	local bg, corner
	if style == 2 then bg, corner = styleTheme(core, x, y, w, h, s)
	elseif style == 3 then bg, corner = styleGauges(x, y, w, h, s)
	else styleSlim(x, y, w, h, s) end
	drawTarget(core, scrw / 2, y - round(3 * s), limit, s, bg, corner)
end)

-- starcore_hud_measure: the width every style needs for the longest texts the HUD can show in the language set
-- right now, and for a usual ship. It fills H like gather does and asks need2..need4, the same code HUDPaint takes
-- its width from. Longest: a name of StarCore.NameShow "W", a 12 character hull number, every class; every state
-- line (hover on / off with frozen, autopilot and cloaked, or docked in a ship with such a name; the pilot also with
-- mouse steering / looking around, the other seats with their role behind the name); 2500 per second, 99999 high
-- (in the player's unit); hull, power and shield 100 % or the shield off; every jump drive text (cooldown 600
-- s); the hint or the self-destruct countdown. One line per style: AGP_RESULT INFO hudmeasure <language> style
-- <n> worst <px> <% of the screen width> limit
-- <px> fits <yes/no> realistic <px> <%> limit_armour <px, the limit while the player has armour>
--
local SEAT_ROLES = { "gunner", "engineer", "passenger" }   -- (StarCore.ROLES is known to the server only)
local function testTitle(name, no, class, role)
	local t = name .. " " .. no .. " · " .. T("class_" .. class)
	if role then t = t .. " · " .. T("role_" .. role) end
	return t
end
local function testGauges(shieldOff)
	H.n = 0
	gauge(1, T("hud_hull", 100), 1, false)
	gauge(2, T("hud_power", 100), 1, false)
	if shieldOff then gauge(3, T("hud_shield_off"), 0, false) else gauge(3, T("hud_shield", 100), 1, false) end
end
concommand.Add("starcore_hud_measure", function()
	local scrw, s = ScrW(), ScrH() / 480
	local name, no = string.rep("W", StarCore.NameShow), "SC-" .. string.rep("0", StarCore.RegNoMax - 3)
	-- title and state belong together: the pilot has the mouse text, the other seats the role
	local cases = {}
	local function add(title, state) cases[#cases + 1] = { title, state } end
	local docked = T("hud_docked", name)
	for _, class in ipairs(StarCore.ShipClasses) do
		local title = testTitle(name, no, class)
		for _, hover in ipairs({ "hover_on", "hover_off" }) do
			local state = T(hover) .. " · " .. T("frozen") .. " · " .. T("autopilot") .. " · " .. T("cloaked")
			add(title, state .. " · " .. T("hud_mouse"))
			add(title, state .. " · " .. T("hud_look"))
			for _, role in ipairs(SEAT_ROLES) do add(testTitle(name, no, class, role), state) end
		end
		add(title, docked .. " · " .. T("hud_mouse"))
		add(title, docked .. " · " .. T("hud_look"))
		for _, role in ipairs(SEAT_ROLES) do add(testTitle(name, no, class, role), docked) end
	end
	local ftls = { T("ftl_charging"), T("ftl_jumping"), T("ftl_cooldown", 600), T("ftl_ready") }
	local hints = { { false, T("hud_hint") }, { true, T("hud_destruct", 60) } }

	local worst = { 0, 0, 0, 0 }
	H.speed, H.alt, H.frac = T("hud_speed", U.Speed(2500 * U.Per())), T("hud_alt", U.Alt(99999 * U.Per())), 1
	for shield = 1, 2 do
		testGauges(shield == 2)
		for _, hint in ipairs(hints) do
			H.alert, H.hint = hint[1], hint[2]
			for _, ftl in ipairs(ftls) do
				H.ftl = ftl
				for _, ts in ipairs(cases) do
					H.title, H.state = ts[1], ts[2]
					for style = 1, 3 do worst[style] = max(worst[style], NEED[style](s)) end
				end
			end
		end
	end

	-- a usual ship: a frigate in hover with mouse steering, the jump drive ready
	H.title, H.state = testTitle("Nightingale", "SC-1042", "frigate"), T("hover_on") .. " · " .. T("hud_mouse")
	H.speed, H.alt, H.frac = T("hud_speed", U.Speed(120 * U.Per())), T("hud_alt", U.Alt(250 * U.Per())), 0
	H.ftl, H.alert, H.hint = T("ftl_ready"), false, T("hud_hint")
	testGauges(false)

	local lang = GetConVar("gmod_language"):GetString()
	local limit, limitArmour = limitWidth(scrw, s, false), limitWidth(scrw, s, true)
	for style = 1, 3 do
		local real = NEED[style](s)
		print("AGP_RESULT", "INFO", "hudmeasure", lang, "style", style, "worst", worst[style], round(worst[style] / scrw * 100, 1),
			"limit", limit, "fits", worst[style] <= limit and "yes" or "no", "realistic", real, round(real / scrw * 100, 1),
			"limit_armour", limitArmour)
	end
end)
