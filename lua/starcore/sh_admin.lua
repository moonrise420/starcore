-- StarCore: the admin settings page (2026-11-16, first Workshop comment: "I'd like to be able to toggle everything in
-- an admin menu to make it fit well to my needs"). Every server setting of StarCore (sh_config.lua StarCore.CV and
-- starcore_walk) as a checkbox / slider / choice in the spawn menu: Utilities > Admin > StarCore.
-- The settings are replicated ConVars, so every player's page shows the server's values; a change goes to the server
-- (net "starcore_admin_set"), which takes it only from an admin, clamps it to the setting's range and logs it.

-- key in StarCore.CV (or a ConVar name), kind, and for sliders the decimals. Grouped as the page shows them.
local GROUPS = {
	{ "admin_g_flight", {
		{ "maxSpeed", "slider", 0 }, { "maxParts", "slider", 0 }, { "starcore_walk", "check" } } },
	{ "admin_g_jumps", {
		{ "allowJump", "check" }, { "jumpRange", "slider", 0 }, { "chargeMin", "slider", 1 }, { "cooldownMin", "slider", 0 },
		{ "jumpEnergy", "slider", 0 }, { "carryPlayers", "check" } } },
	{ "admin_g_combat", {
		{ "hull", "check" }, { "destroyMode", "choice", { "admin_destroy_0", "admin_destroy_1", "admin_destroy_2" } },
		{ "maxWeapons", "slider", 0 }, { "allowAutoDefence", "check" }, { "targetPlayers", "check" },
		{ "radarRange", "slider", 0 }, { "allowSelfDestruct", "check" }, { "selfDestructDamage", "slider", 0 } } },
	{ "admin_g_beams", {
		{ "allowTractor", "check" }, { "tractorRange", "slider", 0 }, { "tractorPlayers", "check" },
		{ "beamRange", "slider", 0 }, { "beamHostile", "check" } } },
	{ "admin_g_ships", {
		{ "allowCloak", "check" }, { "allowFleet", "check" } } },
}

local function cvOf(key)
	return (StarCore.CV and StarCore.CV[key]) or GetConVar(key)
end

if SERVER then
	util.AddNetworkString("starcore_admin_set")
	local allowed = {}
	for _, g in ipairs(GROUPS) do for _, it in ipairs(g[2]) do allowed[it[1]] = true end end

	net.Receive("starcore_admin_set", function(_, ply)
		local key, reset = net.ReadString(), net.ReadBool()
		local value = net.ReadFloat()
		if not (IsValid(ply) and ply:IsAdmin()) then return end   -- only admins (a listen server's host is one)
		if key ~= "*" and not allowed[key] then return end
		local keys = {}
		if key == "*" then for k in pairs(allowed) do keys[#keys + 1] = k end else keys[1] = key end
		for _, k in ipairs(keys) do
			local cv = cvOf(k)
			if cv then
				local v = reset and tonumber(cv:GetDefault()) or value
				local lo, hi = cv:GetMin(), cv:GetMax()
				if lo then v = math.max(v, lo) end
				if hi then v = math.min(v, hi) end
				if v ~= v then v = tonumber(cv:GetDefault()) or 0 end   -- (NaN)
				v = math.Round(v, 2)
				RunConsoleCommand(cv:GetName(), tostring(v))
				if key ~= "*" then value = v end   -- (the log shows what was really set, after the range)
			end
		end
		MsgN("StarCore admin: " .. ply:Nick() .. " (" .. ply:SteamID() .. ") set " .. (key == "*" and "all settings to their defaults" or (key .. (reset and " to its default" or (" = " .. value)))))
	end)
end

if CLIENT then
	local T = StarCore.T

	local function send(key, value, reset)
		net.Start("starcore_admin_set")
		net.WriteString(key)
		net.WriteBool(reset and true or false)
		net.WriteFloat(value or 0)
		net.SendToServer()
	end

	local function build(form)
		form:Help(T("admin_note"))
		local isAdmin = LocalPlayer():IsAdmin()
		if not isAdmin then form:Help(T("admin_not_admin")) end
		local controls = {}
		for _, g in ipairs(GROUPS) do
			local head = form:Help(T(g[1]))
			head:SetFont("DermaDefaultBold")
			for _, it in ipairs(g[2]) do
				local key, kind = it[1], it[2]
				local cv = cvOf(key)
				if cv then
					local text = T("admin_" .. key)
					local c
					if kind == "check" then
						c = form:CheckBox(text)
						c:SetChecked(cv:GetBool())
						c.OnChange = function(_, on) if not c.AGPSet then send(key, on and 1 or 0) end end
						c.AGPRead = function() c.AGPSet = true; c:SetChecked(cv:GetBool()); c.AGPSet = nil end
					elseif kind == "slider" then
						-- the label on its own line above the slider (beside it, long labels were cut off: 12 languages)
						form:Help(text)
						c = form:NumSlider("", nil, cv:GetMin() or 0, cv:GetMax() or 100, it[3] or 0)
						if IsValid(c.Label) then c.Label:SetVisible(false); c.Label:SetWide(0) end
						c:SetValue(cv:GetFloat())
						-- sends when the slider is let go (not on every pixel of the drag)
						c.OnValueChanged = function() if not c.AGPSet then c.AGPDirty = true end end
						local timerName = "StarCoreAdmin_" .. key
						timer.Create(timerName, 0.4, 0, function()
							if not IsValid(c) then timer.Remove(timerName) return end
							if c.AGPDirty and not input.IsMouseDown(MOUSE_LEFT) then c.AGPDirty = nil; send(key, c:GetValue()) end
						end)
						c.AGPRead = function() if not c.AGPDirty then c.AGPSet = true; c:SetValue(cv:GetFloat()); c.AGPSet = nil end end
					elseif kind == "choice" then
						c = form:ComboBox(text)
						for i, k in ipairs(it[3]) do c:AddChoice(T(k), i - 1) end
						c.AGPSet = true; c:ChooseOptionID(math.Clamp(cv:GetInt(), 0, #it[3] - 1) + 1); c.AGPSet = nil   -- (shown; the box was empty)
						c:SetTextColor(Color(25, 25, 25))
						c.OnSelect = function(_, _, _, v) if not c.AGPSet then send(key, v) end end
						c.AGPRead = function()
							local want = math.Clamp(cv:GetInt(), 0, #it[3] - 1) + 1
							if c:GetSelectedID() ~= want then c.AGPSet = true; c:ChooseOptionID(want); c.AGPSet = nil end
						end
					end
					if c then
						c:SetTooltip(cv:GetName())   -- the console name, for admins who type it
						if not isAdmin then c:SetEnabled(false) end
						controls[#controls + 1] = c
					end
				end
			end
		end
		local reset = form:Button(T("admin_reset"))
		reset.DoClick = function()
			Derma_Query(T("admin_reset_q"), "StarCore", T("yes"), function() send("*", 0, true) end, T("no"))
		end
		if not isAdmin then reset:SetEnabled(false) end
		-- the server's values change (this page, another admin, the console): follow them
		local tn = "StarCoreAdminRead_" .. tostring(form)
		timer.Create(tn, 1, 0, function()
			if not IsValid(form) then timer.Remove(tn) return end
			if not form:IsVisible() then return end
			for _, c in ipairs(controls) do if IsValid(c) and c.AGPRead then c.AGPRead() end end
		end)
	end

	StarCore.AdminPanel = build   -- (the test opens the page in a window of its own)

	hook.Add("PopulateToolMenu", "StarCore.Admin", function()
		spawnmenu.AddToolMenuOption("Utilities", "Admin", "starcore_admin", "StarCore", "", "", build)
	end)
end
