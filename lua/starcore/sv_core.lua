-- StarCore server: finds the ship that belongs to a core (everything welded/constrained or parented to it)
util.AddNetworkString("starcore_notify")

StarCore.Cores = StarCore.Cores or {}

function StarCore.Notify(ply, key, kind, ...)
	if not IsValid(ply) then return end
	net.Start("starcore_notify")
	net.WriteString(key)
	net.WriteUInt(kind or NOTIFY_GENERIC, 3)
	local args = { ... }
	net.WriteUInt(#args, 4)
	for _, a in ipairs(args) do net.WriteString(tostring(a)) end
	net.Send(ply)
end

-- tell everyone who controls this ship (owner, pilot)
function StarCore.NotifyShip(core, key, kind, ...)
	local seen = {}
	local owner = core:GetNWEntity("starcore_owner")
	if IsValid(owner) then StarCore.Notify(owner, key, kind, ...); seen[owner] = true end
	local pilot = IsValid(core.PilotSeat) and core.PilotSeat:GetDriver()
	if IsValid(pilot) and not seen[pilot] then StarCore.Notify(pilot, key, kind, ...) end
end

-- small things screens/HUD read: marks, switches, theme
function StarCore.SyncNW(core)
	local s = core.Settings or {}
	for i = 1, StarCore.MaxMarks do
		local m = core.Marks and core.Marks[i]
		local name = m and m.name or ""
		if core:GetNWString("starcore_mark" .. i, "") ~= name then core:SetNWString("starcore_mark" .. i, name) end
	end
	core:SetNWBool("starcore_autodef", s.autoDefence == true)
	core:SetNWBool("starcore_shieldauto", s.shieldAuto == true)
	core:SetNWInt("starcore_theme", s.theme or 1)
	-- AGP: the ship's radar range for the screens (they drew a fixed 15000)
	core:SetNWFloat("starcore_radar_range", s.radarRange or StarCore.Defaults.radarRange)
	-- name, hull number and class for radar, HUD, screens and other ships' menus (sv_dock.lua)
	core:SetNWString("starcore_name", isstring(s.name) and s.name or "")
	core:SetNWString("starcore_regno", isstring(s.regno) and s.regno or "")
	if StarCore.ShipClassOf then core:SetNWString("starcore_class", StarCore.ShipClassOf(core)) end
end

function StarCore.Unregister(core)
	StarCore.Cores[core] = nil
end

local function addWithChildren(e, out)
	if not IsValid(e) or out[e] then return end
	out[e] = true
	for _, c in ipairs(e:GetChildren()) do addWithChildren(c, out) end
end

-- rebuilds core.Parts, core.PhysParts, core.Seats, core.LocalMins/Maxs (ship size in core space)
function StarCore.Scan(core)
	StarCore.Cores[core] = true
	local set = {}
	for e in pairs(constraint.GetAllConstrainedEntities(core) or {}) do addWithChildren(e, set) end
	addWithChildren(core, set)
	if istable(core.ExtraParts) then -- added with the tool
		for e in pairs(core.ExtraParts) do if IsValid(e) then addWithChildren(e, set) end end
	end

	local parts, phys, seats, other = {}, {}, {}, nil
	for e in pairs(set) do
		if IsValid(e) and not e:IsPlayer() and not e:IsNPC() and not (core.Excluded and core.Excluded[e]) then
			parts[#parts + 1] = e
			if e ~= core and e:GetClass() == "starcore" and (not other or e:EntIndex() < other:EntIndex()) then other = e end
			if e:IsVehicle() then seats[#seats + 1] = e end
			local p = e:GetPhysicsObject()
			-- (e.StarCoreFollower: a body that follows another by itself - a SpaceGrid ship follows its keel)
			if not IsValid(e:GetParent()) and IsValid(p) and not e.StarCoreFollower then phys[#phys + 1] = e end
		end
	end

	-- two cores on one ship: the older one (lower index) is in charge
	core.Sleeping = IsValid(other) and other:EntIndex() < core:EntIndex()
	core:SetNWBool("starcore_sleeping", core.Sleeping == true)

	local tooBig = #parts > StarCore.CV.maxParts:GetInt()
	core.TooBig = tooBig
	core:SetNWBool("starcore_toobig", tooBig)

	-- new parts must follow the current flight state
	if core.Helm and core.Helm.on and core.PhysParts then
		local old = {}
		for _, e in ipairs(core.PhysParts) do old[e] = true end
		for _, e in ipairs(phys) do
			if not old[e] then
				local p = e:GetPhysicsObject()
				if IsValid(p) then p:EnableGravity(false); StarCore.HelmDrag(e, p, true) end
			end
		end
	end

	-- parts that are no longer joined to the ship (the part they were welded to got destroyed) are let go: gravity,
	-- drag and motion back, so they fall. They used to keep the ship's flight state and hung in the air where the hull
	-- had been.
	if core.Helm and core.PhysParts and (core.Helm.on or core.Helm.frozen) then
		local now, others = {}, nil
		for _, e in ipairs(phys) do now[e] = true end
		for _, e in ipairs(core.PhysParts) do
			if IsValid(e) and not now[e] and not others then
				-- (parts of a docked ship or of another core's ship stay as their own ship has them)
				others = {}
				for c in pairs(StarCore.Cores) do
					if c ~= core and IsValid(c) then for _, o in ipairs(c.Parts or {}) do others[o] = true end end
				end
			end
			if IsValid(e) and not now[e] and not others[e] and not IsValid(e:GetParent()) and not e.StarCoreFollower then
				local p = e:GetPhysicsObject()
				if IsValid(p) then
					if core.Helm.on then p:EnableGravity(true); StarCore.HelmDrag(e, p, false) end
					if core.Helm.frozen then p:EnableMotion(true) end
					p:Wake()
				end
			end
		end
	end

	table.sort(seats, function(a, b) return a:EntIndex() < b:EntIndex() end)
	core.Parts, core.PhysParts, core.Seats = parts, phys, seats
	core.PartRest = nil   -- (where each welded part sits against the core: taken anew by the helm, sv_helm.lua)
	if not (IsValid(core.PilotSeat) and table.HasValue(seats, core.PilotSeat)) then
		-- auto: the first placed seat that has no other role flies the ship (until the tool picks another one)
		core.PilotSeat = nil
		for _, s in ipairs(seats) do
			local r = (core.SeatRoles and core.SeatRoles[s]) or s.StarCoreRolePreset
			if r == nil or r == "pilot" then core.PilotSeat = s break end
		end
	end
	core:SetNWEntity("starcore_pilotseat", core.PilotSeat or NULL)
	core:SetNWInt("starcore_parts", #parts)
	core:SetNWInt("starcore_seats", #seats)

	-- ship size in core-local space (8 corners of every part's box)
	local mins, maxs = Vector(math.huge, math.huge, math.huge), Vector(-math.huge, -math.huge, -math.huge)
	local mass = 0
	for _, e in ipairs(parts) do
		local a, b = e:OBBMins(), e:OBBMaxs()
		for i = 0, 7 do
			local c = Vector(bit.band(i, 1) > 0 and b.x or a.x, bit.band(i, 2) > 0 and b.y or a.y, bit.band(i, 4) > 0 and b.z or a.z)
			local l = core:WorldToLocal(e:LocalToWorld(c))
			mins.x = math.min(mins.x, l.x); mins.y = math.min(mins.y, l.y); mins.z = math.min(mins.z, l.z)
			maxs.x = math.max(maxs.x, l.x); maxs.y = math.max(maxs.y, l.y); maxs.z = math.max(maxs.z, l.z)
		end
		local p = e:GetPhysicsObject()
		if IsValid(p) then mass = mass + p:GetMass() end
	end
	core.LocalMins, core.LocalMaxs, core.Mass = mins, maxs, mass
	core:SetNWVector("starcore_size", maxs - mins)
	core:SetNWVector("starcore_lmins", mins)
	core:SetNWVector("starcore_lmaxs", maxs)
	if StarCore.SG then StarCore.SG.Attach(core) end
	if StarCore.CombatAttach then StarCore.CombatAttach(core) end
	if StarCore.PowerAttach then StarCore.PowerAttach(core) end
	if StarCore.TransporterAttach then StarCore.TransporterAttach(core) end
	core.Screens = {}
	for _, e in ipairs(parts) do
		if IsValid(e) and e:GetClass() == "starcore_screen" then
			core.Screens[#core.Screens + 1] = e
			if e:GetCore() ~= core then e:SetCore(core) end
		end
	end
	if StarCore.CrewAttach then StarCore.CrewAttach(core) end
	-- the ship's own parts and box (class, docking checks, power); then the ships docked in it join the part lists and
	-- the box (sv_dock.lua), after everything above has seen only its own parts
	core.OwnParts, core.OwnMins, core.OwnMaxs = parts, mins, maxs
	StarCore.SyncNW(core)
	if StarCore.DockAddCarried then StarCore.DockAddCarried(core) end
end

-- world-aligned box (relative to a point) that surely contains the ship when the core sits at pos/ang
function StarCore.ShipBox(core, ang)
	local a, b = core.LocalMins, core.LocalMaxs
	local mins, maxs = Vector(math.huge, math.huge, math.huge), Vector(-math.huge, -math.huge, -math.huge)
	for i = 0, 7 do
		local c = Vector(bit.band(i, 1) > 0 and b.x or a.x, bit.band(i, 2) > 0 and b.y or a.y, bit.band(i, 4) > 0 and b.z or a.z)
		c:Rotate(ang)
		mins.x = math.min(mins.x, c.x); mins.y = math.min(mins.y, c.y); mins.z = math.min(mins.z, c.z)
		maxs.x = math.max(maxs.x, c.x); maxs.y = math.max(maxs.y, c.y); maxs.z = math.max(maxs.z, c.z)
	end
	return mins, maxs -- offsets from the core position
end

-- is a player/NPC standing inside the ship (its box, a bit taller so people on deck count)?
function StarCore.IsInside(core, ent)
	if not core.LocalMins then return false end
	local l = core:WorldToLocal(ent:GetPos() + Vector(0, 0, 8))
	local a, b = core.LocalMins, core.LocalMaxs
	return l.x >= a.x - 16 and l.x <= b.x + 16 and l.y >= a.y - 16 and l.y <= b.y + 16 and l.z >= a.z - 16 and l.z <= b.z + 96
end

-- limit + cleanup for the spawn menu / tool
-- AGP: cleanup.Register("starcores") is in sh_config.lua now (the client's Cleanup menu needs it too) AGP: a core
-- counts for its player once - spawned (PlayerSpawnedSENT: the spawn menu, AdvDupe2) or pasted with the GMod
-- duplicator (the core's PostEntityPaste, which AdvDupe2 calls too)
StarCore.Counted = StarCore.Counted or setmetatable({}, { __mode = "k" })
function StarCore.IsCounted(ent) return StarCore.Counted[ent] == true end
function StarCore.CountCore(ply, ent)
	if StarCore.Counted[ent] then return end
	StarCore.Counted[ent] = true
	ply:AddCount("starcores", ent)
	ply:AddCleanup("starcores", ent)
end
hook.Add("PlayerSpawnedSENT", "StarCore.Limit", function(ply, ent)
	if IsValid(ent) and ent:GetClass() == "starcore" then
		StarCore.CountCore(ply, ent)
		ent:SetNWEntity("starcore_owner", ply)
	end
end)
hook.Add("PlayerSpawnSENT", "StarCore.Limit", function(ply, class)
	-- AGP: the spawn menu hands over its list key ("starcore_<design>"), not the class: the limit never held there. The
	-- class behind the key counts (the same cores StarCore.CountCore counts)
	local entry = isstring(class) and (list.GetEntry and list.GetEntry("SpawnableEntities", class) or list.GetForEdit("SpawnableEntities")[class])
	local cls = istable(entry) and entry.ClassName or class
	if cls == "starcore" and not ply:CheckLimit("starcores") then return false end
end)
