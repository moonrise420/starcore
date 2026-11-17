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

-- keys of the pilot seat (2026-11-16, a Workshop player: "make look around on mouse steering toggleable or to the same
-- effect keybinds for things like mouse steering and hover"). Picked in the menu's Settings tab, 0 = no key.
-- Look around = Alt by default, held or tapped on/off (starcore_look_toggle): the view is free and the helm ignores the
-- mouse (starcore_looking tells the server, sv_helm.lua). Also console commands for binds: starcore_toggle_look/_mouse/_hover/_freeze.
local cvKeyLook, cvKeyMouse, cvKeyHover = GetConVar("starcore_key_look"), GetConVar("starcore_key_mouse"), GetConVar("starcore_key_hover")
local cvKeyFreeze = GetConVar("starcore_key_freeze")   -- (same comment, edited: "un-/freeze the whole ship with a keybind")
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
end)
concommand.Add("starcore_toggle_look", function() if pilotCore() then setLooking(not StarCore.Looking) end end)
concommand.Add("starcore_toggle_mouse", function() toggleMouse() end)
concommand.Add("starcore_toggle_hover", function() local c = pilotCore() if c then toggleHover(c) end end)
concommand.Add("starcore_toggle_freeze", function() local c = pilotCore() if c then toggleFreeze(c) end end)

hook.Add("InputMouseApply", "StarCore.MouseSteer", function(cmd, x, y, ang)
	if not cvMouse:GetBool() or StarCore.Looking then return end
	local core = shipCore()
	local ply = LocalPlayer()
	if not IsValid(core) or not ply:InVehicle() or core:GetNWEntity("starcore_pilotseat") ~= ply:GetVehicle() then return end
	if not core:GetNWBool("starcore_hover") then return end
	return true -- mouse moves still reach the server (cmd mouse x/y), only the view does not turn
end)

surface.CreateFont("StarCoreHUD", { font = "Roboto", size = 18, weight = 600 })
surface.CreateFont("StarCoreHUDSmall", { font = "Roboto", size = 14, weight = 400 })

hook.Add("HUDPaint", "StarCore.HUD", function()
	if not GetConVar("starcore_hud"):GetBool() then return end
	local core = shipCore()
	if not IsValid(core) or not LocalPlayer():InVehicle() then return end

	local hover = core:GetNWBool("starcore_hover")
	local ftl, frac = StarCore.FTLText(core)
	local parts = {
		"StarCore",
		hover and T("hover_on") or T("hover_off"),
		T("hud_speed", U.Speed(core:GetNWFloat("starcore_speed"))),
		T("hud_alt", U.Alt(core:GetNWFloat("starcore_alt"))),
		ftl,
	}
	if core:GetNWBool("starcore_frozen") then parts[2] = parts[2] .. " · " .. T("frozen") end
	if core:GetNWBool("starcore_autopilot") then parts[2] = parts[2] .. " · " .. T("autopilot") end
	if core:GetNWBool("starcore_cloaked") then parts[2] = parts[2] .. " · " .. T("cloaked") end
	if cvMouse:GetBool() and core:GetNWEntity("starcore_pilotseat") == LocalPlayer():GetVehicle() then parts[2] = parts[2] .. " · " .. T(StarCore.Looking and "hud_look" or "hud_mouse") end
	local role = LocalPlayer():GetVehicle():GetNWString("starcore_role", "pilot")
	if role ~= "pilot" then parts[1] = "StarCore · " .. T("role_" .. role) end
	local hmax = core:GetNWInt("starcore_hull_max")
	if hmax > 0 then parts[#parts + 1] = T("hud_hull", math.floor(core:GetNWInt("starcore_hull") / hmax * 100)) end
	local destruct = core:GetNWFloat("starcore_destruct")
	if destruct > CurTime() then parts[#parts + 1] = T("hud_destruct", math.ceil(destruct - CurTime())) end
	local pct = core:GetNWFloat("starcore_power_pct", -1)
	if pct >= 0 then parts[#parts + 1] = T("hud_power", math.floor(pct)) end
	if core:GetNWInt("starcore_shields") > 0 then
		parts[#parts + 1] = core:GetNWBool("starcore_shield_up") and T("hud_shield", math.floor(core:GetNWFloat("starcore_shield_strength"))) or T("hud_shield_off")
	end
	local text = table.concat(parts, "   ")
	surface.SetFont("StarCoreHUD")
	local w, h = surface.GetTextSize(text)
	local x, y = ScrW() / 2, ScrH() - 90
	draw.RoundedBox(6, x - w / 2 - 12, y - 6, w + 24, h + 30, Color(10, 20, 30, 200))
	draw.SimpleText(text, "StarCoreHUD", x, y, Color(140, 220, 255), TEXT_ALIGN_CENTER)
	if frac > 0 then
		surface.SetDrawColor(80, 180, 255, 220)
		surface.DrawRect(x - w / 2, y + h + 2, w * math.Clamp(frac, 0, 1), 3)
	end
	draw.SimpleText(T("hud_hint"), "StarCoreHUDSmall", x, y + h + 8, Color(180, 190, 200), TEXT_ALIGN_CENTER)

	-- target line above the bar
	local target = core:GetNWEntity("starcore_target")
	if IsValid(target) then
		local data = StarCore.Radar and StarCore.Radar[core]
		local c
		for _, k in ipairs(data and data.list or {}) do if k.ent == target then c = k end end
		local name = c and StarCore.ContactName(c) or target:GetClass()
		local dist = U.Dist(target:GetPos():Distance(core:GetPos()))
		local iff = c and T(StarCore.IFFKEY[c.iff]) or ""
		local col = c and StarCore.IFFCOL[c.iff] or color_white
		local txt = T("hud_target", name, dist, iff)
		if core:GetNWBool("starcore_engaging") then txt = txt .. "   " .. T("hud_firing") end
		draw.SimpleText(txt, "StarCoreHUD", x, y - 26, col, TEXT_ALIGN_CENTER)
	end
end)
