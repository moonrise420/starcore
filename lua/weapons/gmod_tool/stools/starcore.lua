-- StarCore tool: place a core (welded to the ship), pick the pilot seat, add loose parts, show the ship
TOOL.Category = "Construction"
TOOL.Name = "#tool.starcore.name"
TOOL.ClientConVar = { design = "reactor_core" }
TOOL.Information = {
	{ name = "left" },
	{ name = "right" },
	{ name = "reload" },
}

if CLIENT then
	local glowUntil, glowEnts = 0, {}
	net.Receive("starcore_showparts", function()
		glowEnts = {}
		for i = 1, net.ReadUInt(13) do glowEnts[i] = net.ReadEntity() end
		glowUntil = CurTime() + 6
	end)
	hook.Add("PreDrawHalos", "StarCore.ShowParts", function()
		if CurTime() > glowUntil then return end
		halo.Add(glowEnts, Color(80, 200, 255), 2, 2, 1, true, false)
	end)
end

if SERVER then util.AddNetworkString("starcore_showparts") end

local function selectedCore(ply)
	local c = ply.StarCoreSelected
	if IsValid(c) and StarCore.CanControl(c, ply) then return c end
end

-- left click: a core on the clicked spot (welded to the clicked prop), or select an existing core
function TOOL:LeftClick(tr)
	if not tr.Hit then return false end
	if CLIENT then return true end
	local ply = self:GetOwner()
	local ent = tr.Entity
	if IsValid(ent) and ent:GetClass() == "starcore" then
		if not StarCore.CanControl(ent, ply) then return false end
		ply.StarCoreSelected = ent
		StarCore.Notify(ply, "core_selected", NOTIFY_GENERIC)
		return true
	end
	if IsValid(ent) and ent:IsPlayer() then return false end
	if not ply:CheckLimit("starcores") then return false end
	if IsValid(ent) and ent.CPPICanTool and not ent:CPPICanTool(ply, "starcore") then return false end

	local core = ents.Create("starcore")
	if not IsValid(core) then return false end
	core.Design = self:GetClientInfo("design")
	core:SetPos(tr.HitPos)
	core:SetAngles(tr.HitNormal:Angle() + Angle(90, 0, 0))
	core:Spawn()
	core:Activate()
	-- sit on the surface, not inside it
	core:SetPos(tr.HitPos - tr.HitNormal * core:OBBMins().z)
	core:SetNWEntity("starcore_owner", ply)
	if core.CPPISetOwner then core:CPPISetOwner(ply) end
	core:SetCreator(ply)
	local weld
	if IsValid(ent) and not ent:IsWorld() then
		weld = constraint.Weld(core, ent, 0, tr.PhysicsBone or 0, 0, true, false)
	else
		local p = core:GetPhysicsObject()
		if IsValid(p) then p:EnableMotion(false) end
	end
	undo.Create("starcore")
	undo.AddEntity(core)
	if IsValid(weld) then undo.AddEntity(weld) end
	undo.SetPlayer(ply)
	undo.Finish()
	ply:AddCount("starcores", core)
	ply:AddCleanup("starcores", core)
	ply.StarCoreSelected = core
	StarCore.Scan(core)
	StarCore.Notify(ply, "core_placed", NOTIFY_GENERIC, core:GetNWInt("starcore_parts"))
	return true
end

-- right click (with a selected core): a seat becomes the pilot seat; a loose prop is added to / removed from the ship
function TOOL:RightClick(tr)
	local ent = tr.Entity
	if not IsValid(ent) or ent:IsPlayer() then return false end
	if CLIENT then return true end
	local ply = self:GetOwner()
	if ent:GetClass() == "starcore_screen" then
		if ent.CPPICanTool and not ent:CPPICanTool(ply, "starcore") then return false end
		ent:SetPage(ent:GetPage() % ent.Pages + 1)
		StarCore.Notify(ply, "screen_page", NOTIFY_GENERIC, ent:GetPage())
		return true
	end
	local core = selectedCore(ply)
	if not core then StarCore.Notify(ply, "select_core_first", NOTIFY_ERROR) return false end
	if ent.CPPICanTool and not ent:CPPICanTool(ply, "starcore") then return false end
	StarCore.Scan(core)
	if ent:IsVehicle() then
		if not table.HasValue(core.Parts, ent) then StarCore.Notify(ply, "seat_not_on_ship", NOTIFY_ERROR) return false end
		local role = StarCore.CycleSeatRole(core, ent)
		StarCore.Notify(ply, "seat_role_" .. role, NOTIFY_GENERIC)
		return true
	end
	if ent == core then return false end
	core.ExtraParts = core.ExtraParts or {}
	if core.ExtraParts[ent] then
		core.ExtraParts[ent] = nil
		StarCore.Notify(ply, "part_removed", NOTIFY_GENERIC)
	elseif table.HasValue(core.Parts, ent) then
		StarCore.Notify(ply, "part_is_welded", NOTIFY_HINT)
		return false
	else
		core.ExtraParts[ent] = true
		StarCore.Notify(ply, "part_added", NOTIFY_GENERIC)
	end
	StarCore.Scan(core)
	return true
end

-- reload: outline every part of the ship (the core you look at, or the selected one)
function TOOL:Reload(tr)
	if CLIENT then return true end
	local ply = self:GetOwner()
	local core = IsValid(tr.Entity) and tr.Entity:GetClass() == "starcore" and tr.Entity or selectedCore(ply)
	if not IsValid(core) or not StarCore.CanControl(core, ply) then return false end
	StarCore.Scan(core)
	local list = core.Parts or {}
	net.Start("starcore_showparts")
	net.WriteUInt(math.min(#list, 8000), 13)
	for i = 1, math.min(#list, 8000) do net.WriteEntity(list[i]) end
	net.Send(ply)
	StarCore.Notify(ply, "parts_shown", NOTIFY_GENERIC, #list)
	return true
end

function TOOL.BuildCPanel(panel)
	panel:Help("#tool.starcore.help")
	local box = panel:ComboBox("#tool.starcore.design", "starcore_design")
	for _, d in ipairs(StarCore.Designs) do box:AddChoice("#starcore.design." .. d.id, d.id) end
	if StarCore.StyleCombo then StarCore.StyleCombo(box) end   -- (2026-11-17: readable with every menu skin)
	panel:Help("#tool.starcore.help2")
end
