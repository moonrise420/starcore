-- StarCore bridge screen: weld it to the ship, pick its page with the StarCore tool (right click), press E on its buttons.
-- Pages: 1 overview, 2 jump, 3 radar, 4 weapons, 5 stargate, 6 power. The look follows the ship's theme.
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "StarCore Screen"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH
ENT.Pages = 6

local SIZES = { { id = "small", model = "models/hunter/plates/plate1x1.mdl" }, { id = "wide", model = "models/hunter/plates/plate1x2.mdl" } }
for _, s in ipairs(SIZES) do
	list.Set("SpawnableEntities", "starcore_screen_" .. s.id, {
		PrintName = "#starcore.screen." .. s.id, ClassName = "starcore_screen", Category = "StarCore", KeyValues = { screenmodel = s.model },
	})
end

function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "Page")
	self:NetworkVar("Entity", 0, "Core")
end

if SERVER then
	-- AGP 2026-11-08: pasteable by everyone (the duplicator pastes a class that is not Spawnable only for admins);
	-- marked on the server once registered, so the spawn menu keeps its two sizes and gets no plain entry (see starcore.lua)
	timer.Simple(0, function()
		local st = scripted_ents.GetStored("starcore_screen")
		if st and st.t then st.t.Spawnable = true end
	end)

	function ENT:KeyValue(k, v)
		if k == "screenmodel" then
			self.ScreenModel = v
			if self.Initialized then self:SetModel(v); self:PhysicsInit(SOLID_VPHYSICS) end
		end
	end

	-- AGP 2026-11-08: one of our two screen models (nil for anything else)
	local function screenModel(m)
		for _, s in ipairs(SIZES) do if s.model == m then return m end end
	end

	function ENT:Initialize()
		-- AGP 2026-11-08: a pasted / loaded wide screen came back as the small one: the duplicator sets the model before
		-- the screen spawns, but ScreenModel only after it - the model it already has is kept
		self:SetModel(self.ScreenModel or screenModel(self:GetModel()) or SIZES[1].model)
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetMaterial("models/debug/debugwhite")
		self:SetColor(Color(20, 24, 30))
		if self:GetPage() == 0 then self:SetPage(1) end
		local p = self:GetPhysicsObject()
		if IsValid(p) then p:Wake() end
		self.Initialized = true
	end

	function ENT:PreEntityCopy()
		-- AGP 2026-11-08: + the core it shows, by index (the paste links the screen to the pasted core, not the original)
		duplicator.ClearEntityModifier(self, "starcore_screen")
		local core = self:GetCore()
		duplicator.StoreEntityModifier(self, "starcore_screen", { page = self:GetPage(), model = self:GetModel(),
			core = IsValid(core) and core:EntIndex() or nil })
	end

	function ENT:PostEntityPaste(ply, ent, created)
		-- AGP 2026-11-08: the duplicator restores the screen's Core (a network var) as the ORIGINAL core: a screen on the
		-- copy that is not welded to it (so the copy's core never claims it) controlled the original ship. Now the core
		-- of this paste, or none (a ship's core claims its screens again when it scans)
		local d = self.EntityMods and self.EntityMods.starcore_screen
		local core = istable(d) and d.core and created and (created[d.core] or created[tonumber(d.core) or -1] or created[tostring(d.core)])
		self:SetCore(IsValid(core) and core:GetClass() == "starcore" and core or NULL)
		if istable(d) then
			if isnumber(d.page) then self:SetPage(math.Clamp(math.floor(d.page), 1, self.Pages)) end
			-- AGP 2026-11-08: the saved size (older dupes / other duplicators that spawned it with the small model)
			local m = isstring(d.model) and screenModel(d.model)
			if m and self:GetModel() ~= m then
				local p = self:GetPhysicsObject()
				local frozen = IsValid(p) and not p:IsMotionEnabled()
				self.ScreenModel = m
				self:SetModel(m)
				self:PhysicsInit(SOLID_VPHYSICS)
				p = self:GetPhysicsObject()
				if IsValid(p) then if frozen then p:EnableMotion(false) else p:Wake() end end
			end
		end
	end
	return
end

-- ===================== client: drawing + buttons =====================
local T = StarCore.T
local U = StarCore.Units
local SCALE = 0.1
surface.CreateFont("StarCoreScreenBig", { font = "Roboto", size = 34, weight = 700 })
surface.CreateFont("StarCoreScreen", { font = "Roboto", size = 24, weight = 500 })
surface.CreateFont("StarCoreScreenSmall", { font = "Roboto", size = 19, weight = 400 })

function ENT:ScreenFrame()
	local mins, maxs = self:OBBMins(), self:OBBMaxs()
	local pos = self:LocalToWorld(Vector(mins.x, maxs.y, maxs.z + 0.3))
	local ang = self:GetAngles()
	return pos, ang, (maxs.x - mins.x) / SCALE, (maxs.y - mins.y) / SCALE
end

local function theme(core)
	local id = IsValid(core) and core:GetNWInt("starcore_theme", 1) or 1
	return StarCore.Themes[id] or StarCore.Themes[1]
end

-- one place that knows what each page shows and which buttons it has
local function pageButtons(page, core, w, h)
	local b = {}
	local function add(x, y, bw, bh, text, cmd, data, on)
		b[#b + 1] = { x = x, y = y, w = bw, h = bh, text = text, cmd = cmd, data = data, on = on }
	end
	local bw, bh = (w - 30) / 2, 44
	local y0 = h - (bh + 10) * 2 - 6
	if page == 1 then
		add(10, y0, bw, bh, T("hover_short"), "hover", { on = not core:GetNWBool("starcore_hover") }, core:GetNWBool("starcore_hover"))
		add(20 + bw, y0, bw, bh, T("park_short"), "freeze", { on = not core:GetNWBool("starcore_frozen") }, core:GetNWBool("starcore_frozen"))
		add(10, y0 + bh + 10, bw, bh, T("shield_short"), "shield", { on = not core:GetNWBool("starcore_shield_up") }, core:GetNWBool("starcore_shield_up"))
		add(20 + bw, y0 + bh + 10, bw, bh, T("btn_cancel"), "cancel", {})
	elseif page == 2 then
		local n = 0
		for i = 1, StarCore.MaxMarks do
			local name = core:GetNWString("starcore_mark" .. i, "")
			if name ~= "" then
				local col, row = n % 2, math.floor(n / 2)
				add(10 + col * (bw + 10), 60 + row * (bh + 8), bw, bh, i .. ". " .. name, "jump", { kind = "mark", index = i })
				n = n + 1
			end
		end
		add(10, h - bh - 10, bw, bh, T("btn_jump_owner_short"), "jump", { kind = "owner" })
		add(20 + bw, h - bh - 10, bw, bh, T("btn_cancel"), "cancel", {})
	elseif page == 3 or page == 4 then
		local tw = (w - 50) / 4
		add(10, h - bh - 10, tw, bh, "<", "target", { step = -1 })
		add(20 + tw, h - bh - 10, tw, bh, ">", "target", { step = 1 })
		local t = core:GetNWEntity("starcore_target")
		if page == 3 then
			add(30 + tw * 2, h - bh - 10, tw, bh, T("beam_short"), "beam_aboard", { id = IsValid(t) and t:EntIndex() or 0 })
			add(40 + tw * 3, h - bh - 10, tw, bh, T("jump_short"), "jump", { kind = "contact", id = IsValid(t) and t:EntIndex() or 0 })
		else
			local firing = core:GetNWBool("starcore_engaging")
			add(30 + tw * 2, h - bh - 10, tw, bh, firing and T("cease_short") or T("fire_short"), "engage", { on = not firing }, firing)
			local auto = core:GetNWBool("starcore_autodef")
			add(40 + tw * 3, h - bh - 10, tw, bh, T("auto_short"), "settings", { values = { autoDefence = not auto } }, auto)
		end
	elseif page == 5 then
		add(10, h - bh - 10, bw, bh, T("btn_close_gate"), "sg_close", {})
		add(20 + bw, h - bh - 10, bw, bh, T("btn_iris"), "sg_iris", {}, core:GetNWBool("starcore_iris_closed"))
	elseif page == 6 then
		local cloaked = core:GetNWBool("starcore_cloaked")
		add(10, y0, bw, bh, T("cloak_short"), "cloak", { on = not cloaked }, cloaked)
		add(20 + bw, y0, bw, bh, T("land_short"), "land", {})
		add(10, y0 + bh + 10, bw, bh, T("shield_short"), "shield", { on = not core:GetNWBool("starcore_shield_up") }, core:GetNWBool("starcore_shield_up"))
		add(20 + bw, y0 + bh + 10, bw, bh, T("auto_shield_short"), "settings", { values = { shieldAuto = not core:GetNWBool("starcore_shieldauto") } }, core:GetNWBool("starcore_shieldauto"))
	end
	return b
end

local function drawRadar(core, cx, cy, r, th)
	surface.DrawCircle(cx, cy, r, th.fg.r, th.fg.g, th.fg.b, 120)
	surface.DrawCircle(cx, cy, r * 0.5, th.fg.r, th.fg.g, th.fg.b, 60)
	local data = StarCore.Radar and StarCore.Radar[core]
	if not data then return end
	-- AGP 2026-11-08: the ship's radar range (menu setting, capped by the server like the sensors); was a fixed 15000
	local range = math.max(math.min(core:GetNWFloat("starcore_radar_range", 15000), GetConVar("starcore_radar_range"):GetFloat()), 1)
	local center = core:GetPos()
	local a = math.rad(-data.yaw)
	local target = core:GetNWEntity("starcore_target")
	for _, c in ipairs(data.list) do
		if IsValid(c.ent) then
			local d = c.ent:GetPos() - center
			local fx = d.x * math.cos(a) - d.y * math.sin(a)
			local fy = d.x * math.sin(a) + d.y * math.cos(a)
			local px, py = cx - fy / range * r, cy - fx / range * r
			local col = StarCore.IFFCOL and StarCore.IFFCOL[c.iff] or color_white
			local s = c.ent == target and 12 or 7
			draw.RoundedBox(s / 2, px - s / 2, py - s / 2, s, s, col)
		end
	end
	draw.SimpleText("▲", "StarCoreScreenSmall", cx, cy, th.fg, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

local function drawPage(ent, core, w, h, th)
	local page = ent:GetPage()
	draw.RoundedBox(12, 0, 0, w, h, th.bg)
	draw.RoundedBox(12, 0, 0, w, 46, th.accent)
	local titles = { "screen_overview", "tab_jump", "tab_radar", "screen_weapons", "tab_gates", "tab_power" }
	draw.SimpleText("StarCore · " .. T(titles[page] or "screen_overview"), "StarCoreScreenBig", 14, 6, th.title)
	if not IsValid(core) then
		draw.SimpleText(T("screen_no_core"), "StarCoreScreen", w / 2, h / 2, th.warn, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		return
	end
	local y = 56
	local rows = {} -- status lines that are switches too (E on the line toggles it, like the buttons)
	local function line(text, col, cmd, data)
		if cmd then
			rows[#rows + 1] = { x = 6, y = y - 2, w = w - 12, h = 30, cmd = cmd, data = data, row = true }
			local hx, hy = ent.HoverX or -1, ent.HoverY or -1
			if hx >= 6 and hx <= w - 6 and hy >= y - 2 and hy <= y + 28 then draw.RoundedBox(6, 6, y - 2, w - 12, 30, th.hover) end
		end
		draw.SimpleText(text, "StarCoreScreen", 14, y, col or th.fg)
		y = y + 30
	end
	local hoverOn, shieldOn = core:GetNWBool("starcore_hover"), core:GetNWBool("starcore_shield_up")
	if page == 1 then
		line(hoverOn and T("hover_on") or T("hover_off"), nil, "hover", { on = not hoverOn })
		line(T("hud_speed", U.Speed(core:GetNWFloat("starcore_speed"))) .. "    " .. T("hud_alt", U.Alt(core:GetNWFloat("starcore_alt"))))
		line((StarCore.FTLText(core)))
		local pct = core:GetNWFloat("starcore_power_pct", -1)
		if pct >= 0 then line(T("hud_power", math.floor(pct)), pct < 15 and th.warn or nil) end
		if core:GetNWInt("starcore_shields") > 0 then
			line(shieldOn and T("hud_shield", math.floor(core:GetNWFloat("starcore_shield_strength"))) or T("hud_shield_off"), nil, "shield", { on = not shieldOn })
		end
		if core:GetNWInt("starcore_hull_max") > 0 then
			local hp = core:GetNWInt("starcore_hull") / core:GetNWInt("starcore_hull_max") * 100
			line(T("hud_hull", math.floor(hp)), hp < 30 and th.warn or nil)
		end
	elseif page == 2 then
		line((StarCore.FTLText(core)))
	elseif page == 3 then
		local r = math.min(w, h - 120) / 2 - 10
		drawRadar(core, w / 2, 56 + r, r, th)
	elseif page == 4 then
		local t = core:GetNWEntity("starcore_target")
		line(IsValid(t) and T("hud_target", (t:IsPlayer() and t:Nick() or language.GetPhrase(t:GetClass())), U.Dist(t:GetPos():Distance(core:GetPos())), "") or T("no_target_short"))
		line(T("weapons_count", core:GetNWInt("starcore_weapons")))
		if core:GetNWBool("starcore_engaging") then line(T("hud_firing"), th.warn) end
	elseif page == 5 then
		local g = core:GetNWEntity("starcore_gate")
		if not IsValid(g) then line(T("sg_no_gate"), th.warn) else
			local st = T("sg_state_idle")
			if core:GetNWBool("starcore_gate_open") then st = core:GetNWBool("starcore_gate_inbound") and T("sg_state_open_in") or T("sg_state_open_out")
			elseif core:GetNWBool("starcore_gate_busy") then st = T("sg_state_busy") end
			line(st, core:GetNWBool("starcore_gate_inbound") and th.warn or nil)
			line(core:GetNWBool("starcore_iris_closed") and T("sg_iris_closed") or T("sg_iris_open"))
		end
	elseif page == 6 then
		local pct = core:GetNWFloat("starcore_power_pct", -1)
		if pct < 0 then line(T("power_none_short"), th.warn) else
			draw.RoundedBox(6, 14, y, w - 28, 28, Color(0, 0, 0, 150))
			draw.RoundedBox(6, 14, y, (w - 28) * math.Clamp(pct / 100, 0, 1), 28, pct < 15 and th.warn or th.accent)
			y = y + 36
			line(T("hud_power", math.floor(pct)))
		end
		if core:GetNWInt("starcore_shields") > 0 then
			line(shieldOn and T("hud_shield", math.floor(core:GetNWFloat("starcore_shield_strength"))) or T("hud_shield_off"), nil, "shield", { on = not shieldOn })
		end
		if core:GetNWBool("starcore_cloaked") then line(T("cloaked"), nil, "cloak", { on = false }) end
	end
	ent.Buttons = pageButtons(page, core, w, h)
	for _, r in ipairs(rows) do ent.Buttons[#ent.Buttons + 1] = r end
	local hx, hy = ent.HoverX or -1, ent.HoverY or -1
	for _, b in ipairs(ent.Buttons) do
		if b.row then continue end
		local over = hx >= b.x and hx <= b.x + b.w and hy >= b.y and hy <= b.y + b.h
		draw.RoundedBox(8, b.x, b.y, b.w, b.h, b.on and th.accent or (over and th.hover or th.button))
		draw.SimpleText(b.text, "StarCoreScreen", b.x + b.w / 2, b.y + b.h / 2, b.on and th.title or th.fg, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end

function ENT:Draw()
	self:DrawModel()
	if LocalPlayer():GetPos():DistToSqr(self:GetPos()) > 1500 * 1500 then return end
	local pos, ang, w, h = self:ScreenFrame()
	-- where the player looks (for hover and E presses)
	self.HoverX, self.HoverY = nil, nil
	local tr = LocalPlayer():GetEyeTrace()
	if tr.Entity == self and tr.HitPos:DistToSqr(LocalPlayer():EyePos()) < 150 * 150 then
		local l = WorldToLocal(tr.HitPos, Angle(), pos, ang)
		self.HoverX, self.HoverY = l.x / SCALE, -l.y / SCALE
	end
	cam.Start3D2D(pos, ang, SCALE)
		drawPage(self, self:GetCore(), w, h, theme(self:GetCore()))
	cam.End3D2D()
end

-- E on a button. PlayerBindPress, not KeyPress: KeyPress is a predicted hook and never runs on the client
-- in singleplayer (so E did nothing there). The bind hook runs on the client everywhere.
hook.Add("PlayerBindPress", "StarCore.ScreenPress", function(ply, bind, pressed)
	if not pressed or not bind:find("+use", 1, true) or ply:InVehicle() then return end
	local ent = ply:GetEyeTrace().Entity
	if not IsValid(ent) or ent:GetClass() ~= "starcore_screen" or not ent.Buttons or not ent.HoverX then return end
	for _, b in ipairs(ent.Buttons) do
		if ent.HoverX >= b.x and ent.HoverX <= b.x + b.w and ent.HoverY >= b.y and ent.HoverY <= b.y + b.h then
			local core = ent:GetCore()
			if not IsValid(core) then return end
			if (ent.NextPress or 0) > CurTime() then return true end
			ent.NextPress = CurTime() + 0.25 -- the server takes one command per 0.1 s; holding E must not flicker
			net.Start("starcore_cmd")
			net.WriteEntity(core)
			net.WriteString(b.cmd)
			net.WriteTable(b.data or {})
			net.SendToServer()
			surface.PlaySound("buttons/button15.wav")
			return true -- the press was for the button (do not also pick the screen up)
		end
	end
end)
