-- StarCore: the "brain" you weld to your ship
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "StarCore"
ENT.Author = "Ascension Gates team"
ENT.Spawnable = false -- the spawn menu entries below set the design
ENT.RenderGroup = RENDERGROUP_OPAQUE

for _, d in ipairs(StarCore.Designs) do
	list.Set("SpawnableEntities", "starcore_" .. d.id, {
		PrintName = "#starcore.design." .. d.id,
		ClassName = "starcore",
		Category = "StarCore",
		KeyValues = { design = d.id },
	})
end
-- old spawn names (starcore_reactor, ...) from saved spawn lists still spawn: server only, so the spawn menu
-- does not show them twice
if SERVER then
	for old, new in pairs(StarCore.DesignAliases) do
		list.Set("SpawnableEntities", "starcore_" .. old, {
			PrintName = "#starcore.design." .. new,
			ClassName = "starcore",
			Category = "StarCore",
			KeyValues = { design = new },
		})
	end
end

if CLIENT then
	language.Add("starcore", "StarCore")

	function ENT:Draw()
		self:DrawModel()
	end

	return
end

-- AGP: a pasted / loaded core came loose: its PostEntityPaste set the design again, which made new physics (unfrozen,
-- awake) after the duplicator had frozen it. The physics are made new only when the model really changes, and a
-- frozen core stays frozen then
function ENT:SetupDesign(id)
	self.Design = StarCore.DesignId(id or self.Design)
	local model = StarCore.DesignModel(self.Design)
	self:SetNWString("starcore_design", self.Design)
	local phys = self:GetPhysicsObject()
	if IsValid(phys) and self:GetModel() == model then return end
	local frozen = IsValid(phys) and not phys:IsMotionEnabled()
	self:SetModel(model)
	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	phys = self:GetPhysicsObject()
	if IsValid(phys) then
		if frozen then phys:EnableMotion(false) else phys:Wake() end
	end
end

-- AGP: the design a model belongs to (the duplicator sets the model before the core spawns)
local function designOfModel(model)
	for _, d in ipairs(StarCore.Designs) do if d.model == model then return d.id end end
end

-- live design change from the menu: new model + physics in the same place, its welds are made again
function ENT:ChangeDesign(id)
	id = StarCore.DesignId(id)
	if id == self.Design then return true end
	if (self.Helm and self.Helm.on) or (self.FTLData and self.FTLData.state ~= StarCore.FTL.IDLE) then return false, "design_land_first" end
	local pos, ang, parent = self:GetPos(), self:GetAngles(), self:GetParent()
	local phys = self:GetPhysicsObject()
	local frozen = IsValid(phys) and not phys:IsMotionEnabled()
	local welds = {}
	for _, c in ipairs(constraint.FindConstraints(self, "Weld") or {}) do
		local other, bone = c.Ent2, c.Bone2
		if other == self then other, bone = c.Ent1, c.Bone1 end
		if IsValid(other) or (other and other.IsWorld and other:IsWorld()) then
			welds[#welds + 1] = { ent = other, bone = bone or 0, force = c.forcelimit or 0, nocollide = c.nocollide == true }
		end
	end
	constraint.RemoveConstraints(self, "Weld")
	self:SetupDesign(id)
	self:SetPos(pos)
	self:SetAngles(ang)
	phys = self:GetPhysicsObject()
	if IsValid(phys) and (frozen or IsValid(parent)) then phys:EnableMotion(false) end
	for _, w in ipairs(welds) do
		if IsValid(w.ent) or w.ent:IsWorld() then constraint.Weld(self, w.ent, 0, w.bone, w.force, w.nocollide) end
	end
	self.NextScan = 0 -- find the ship again right away
	return true
end

function ENT:Initialize()
	self:SetupDesign(self.Design or designOfModel(self:GetModel()))   -- AGP: a pasted core keeps its model
	self:SetUseType(SIMPLE_USE)
	self.Settings = table.Copy(StarCore.Defaults)
	if StarCore.IdentityNew then StarCore.IdentityNew(self) end   -- (a random name and a hull number)
	self.Marks = self.Marks or {}
	self.Parts = { self }
	self.Seats = {}
	self.Helm = { on = false, targetZ = nil, idle = 0 }
	self.FTLData = { state = StarCore.FTL.IDLE }
	self.NextScan = 0
	self:SetNWInt("starcore_ftl", StarCore.FTL.IDLE)
	if StarCore.WireSetup then StarCore.WireSetup(self) end
	self.Initialized = true
end

-- AGP: GMod's duplicator (and AdvDupe2) pastes a class that is not Spawnable only for admins, so everyone else got
-- their ship without its core. Spawnable = true above would also put a plain "StarCore" into the spawn menu next to
-- the designs, so the server marks the class spawnable once it is registered (again after a Lua refresh, which
-- registers it anew); the client's spawn menu never sees it. sbox_maxstarcores: PostEntityPaste below.
timer.Simple(0, function()
	local st = scripted_ents.GetStored("starcore")
	if st and st.t then st.t.Spawnable = true end
end)

-- the spawn menu sets the design after spawning (KeyValues)
function ENT:KeyValue(k, v)
	if k == "design" then
		self.Design = v
		if self.Initialized then self:SetupDesign(v) end
	end
end

function ENT:TriggerInput(name, value)
	if StarCore.WireInput then StarCore.WireInput(self, name, value) end
end

function ENT:Use(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return end
	if not StarCore.CanControl(self, ply) then
		StarCore.Notify(ply, "no_permission", NOTIFY_ERROR)
		return
	end
	StarCore.OpenMenu(ply, self)
end

function ENT:Think()
	local now = CurTime()
	if not IsValid(self:GetNWEntity("starcore_owner")) then
		local owner = (self.CPPIGetOwner and self:CPPIGetOwner()) or self:GetCreator()
		if IsValid(owner) then self:SetNWEntity("starcore_owner", owner) end
	end
	if now >= self.NextScan then
		StarCore.Scan(self)
		self.NextScan = now + 2
	end
	if now >= (self.NextSG or 0) then
		self.NextSG = now + 0.5
		if StarCore.SG and StarCore.SG.Available() then StarCore.SG.Think(self) end
	end
	if StarCore.DockThink then StarCore.DockThink(self) end
	StarCore.HelmThink(self)
	StarCore.FTLThink(self)
	StarCore.CombatThink(self)
	StarCore.PowerThink(self)
	StarCore.CrewThink(self)
	StarCore.SystemsThink(self)
	if StarCore.WireOutputs then StarCore.WireOutputs(self) end
	self:NextThink(now)
	return true
end

function ENT:OnRemove()
	if self.DockedTo and StarCore.Undock then StarCore.Undock(self, true) end   -- (the lock goes with it)
	StarCore.HelmSetOn(self, false)
	-- (a held frozen prop stayed unfrozen when the core went - the beam lets it go as when switched off)
	if self.Tractor and StarCore.TractorSet then StarCore.TractorSet(self, nil) end
	if StarCore.StopWeapons then StarCore.StopWeapons(self) end
	if StarCore.CloakSet and self.Cloaked then StarCore.CloakSet(self, false) end
	timer.Remove("StarCore.SelfDestruct" .. self:EntIndex())
	StarCore.Unregister(self)
end

-- AGP: what a core only has while it runs. The duplicator copies the whole entity table into the copy (and merges it
-- into the pasted core), so a pasted ship came with the original's: it hovered / jumped like it, took the original's
-- tool-added parts (ExtraParts) into its own ship, thought itself cloaked, kept the original's enemies, target and
-- part lists, and its Wire outputs still drove what the original was wired to. A copy leaves these out; a pasted
-- core (also from AdvDupe2 or an older dupe that still has them) starts with its own, as a new core does.
local RUNTIME = {
	"Helm", "FTLData", "Autopilot", "AutopilotInputs", "Landing", "FleetLeader", "FleetOffset", "NextFleet",
	"Hostiles", "Target", "TargetLock", "Contacts", "Viewers", "Engage", "Firing", "Weapons", "NextWeapons", "NextSensor",
	"Tractor", "Transporter", "NextBeam", "Cloaked", "CloakSaved", "ExtraParts", "Excluded", "PilotSeat", "SeatRoles",
	"Parts", "PhysParts", "Seats", "Screens", "Shields", "PowerSources", "RDPart", "Gate", "Iris", "SGOutbound", "SGIrisByUs", "SGNear", "SGDialled", "SGDialledAt",
	"Sleeping", "TooBig", "Destroyed", "Mass", "LocalMins", "LocalMaxs", "CombatMarked",
	"DockedTo", "DockRoot", "DockRel", "OwnParts", "OwnMins", "OwnMaxs",   -- (docking, sv_dock.lua; a pasted ship is not docked)
	"PowerRate", "LastStored", "LastStoredT", "LowPowerWarned", "ShieldWasUp", "ShieldOffByUs", "NextAutoShield",
	"NextScan", "NextSG", "NextPower", "NextCrew", "NextWireOut", "WireLast", "VoiceLast",
}

local function freshState(core)
	for _, k in ipairs(RUNTIME) do core[k] = nil end
	core.Helm = { on = false, targetZ = nil, idle = 0 }
	core.FTLData = { state = StarCore.FTL.IDLE }
	core.Parts, core.Seats, core.NextScan = { core }, {}, 0
	core:SetNWInt("starcore_ftl", StarCore.FTL.IDLE)
end

function ENT:OnEntityCopyTableFinish(data)
	for _, k in ipairs(RUNTIME) do data[k] = nil end
	data.Inputs, data.Outputs = nil, nil   -- (the core makes its own; wires travel as WireDupeInfo)
end

-- the Wire ports a pasted core got merged from the original: its own entity again, no wire to anything outside this
-- paste (the wires of the paste are made again from the dupe info, by the core and by the parts wired to it)
local function ownWirePorts(core, created)
	local mine = { [core] = true }
	for _, e in pairs(created or {}) do if IsValid(e) then mine[e] = true end end
	for _, port in pairs(istable(core.Inputs) and core.Inputs or {}) do
		if istable(port) then
			port.Entity = core
			if port.Src ~= nil and not mine[port.Src] then
				port.Src, port.SrcId, port.Path = nil, nil, nil
				local dt = WireLib and WireLib.DT and WireLib.DT[port.Type]
				local zero = dt and dt.Zero
				if isfunction(zero) then zero = zero() end
				if zero ~= nil then port.Value = zero end
			end
		end
	end
	for _, port in pairs(istable(core.Outputs) and core.Outputs or {}) do
		if istable(port) then
			port.Entity = core
			local keep = {}
			for _, c in ipairs(istable(port.Connected) and port.Connected or {}) do
				if istable(c) and mine[c.Entity] then keep[#keep + 1] = c end
			end
			port.Connected = keep
		end
	end
end

local function pasted(created, id)
	if not (created and id) then return nil end
	local e = created[id] or created[tonumber(id) or -1] or created[tostring(id)]
	return IsValid(e) and e or nil
end

-- dupes: settings, marks and the chosen pilot seat travel with the ship
function ENT:PreEntityCopy()
	-- AGP: wires into the core were lost on dupe / save (no Wire dupe info was written)
	duplicator.ClearEntityModifier(self, "WireDupeInfo")
	if WireLib and WireLib.BuildDupeInfo then
		local info = WireLib.BuildDupeInfo(self)
		if istable(info) and istable(info.Wires) and next(info.Wires) then duplicator.StoreEntityModifier(self, "WireDupeInfo", info) end
	end
	-- AGP: the core's whole modifier anew each time (StoreEntityModifier merges into the old one)
	duplicator.ClearEntityModifier(self, "starcore")
	local pilot = self.PilotSeat
	duplicator.StoreEntityModifier(self, "starcore", {
		design = self.Design,
		settings = self.Settings,
		marks = self.Marks,
		pilot = IsValid(pilot) and pilot:EntIndex() or nil,
		irisAuto = self.SGIrisAuto ~= false,
		roles = (function()
			local r = {}
			for seat, role in pairs(self.SeatRoles or {}) do if IsValid(seat) then r[seat:EntIndex()] = role end end
			return r
		end)(),
		hull = self.Hull,
		front = self.FrontYaw,   -- (the front set in the menu, local to the core) AGP: the
		-- tool-added parts by index (the paste maps them to its own new parts), and while cloaked how the parts really
		-- look (a copy taken while cloaked would stay see-through: it is pasted uncloaked)
		extra = (function()
			local x = {}
			for e in pairs(istable(self.ExtraParts) and self.ExtraParts or {}) do if IsValid(e) then x[#x + 1] = e:EntIndex() end end
			return x
		end)(),
		look = self.Cloaked and (function()
			local x = {}
			for e, s in pairs(istable(self.CloakSaved) and self.CloakSaved or {}) do
				if IsValid(e) and istable(s) and s.col then x[#x + 1] = { id = e:EntIndex(), mode = s.mode, col = { s.col.r, s.col.g, s.col.b, s.col.a } } end
			end
			return x
		end)() or nil,
	})
end

function ENT:PostEntityPaste(ply, ent, created)
	-- AGP: a pasted core counts against sbox_maxstarcores like a spawned one (AdvDupe2 has counted it already,
	-- through PlayerSpawnedSENT); a player over the limit does not keep it. Admins are not held to it here: they load
	-- game saves (the duplicator too) with any number of ships
	if IsValid(ply) and ply:IsPlayer() and not StarCore.IsCounted(self) then
		if not ply:IsAdmin() and not ply:CheckLimit("starcores") then
			SafeRemoveEntityDelayed(self, 0)
			return
		end
		StarCore.CountCore(ply, self)
	end
	-- AGP: a new ship: its own running state, its own Wire ports, and the wires into it made again
	freshState(self)
	if StarCore.IdentityPasted then StarCore.IdentityPasted(self) end   -- (name kept, a new number if taken)
	if self.Disabled then self:SetNWBool("starcore_disabled", true) end   -- (the hull damage came along: so does being disabled)
	ownWirePorts(self, created)
	local wireInfo = self.EntityMods and self.EntityMods.WireDupeInfo
	if WireLib and WireLib.ApplyDupeInfo and istable(wireInfo) then
		WireLib.ApplyDupeInfo(ply, self, wireInfo, function(id, default) return pasted(created, id) or default end)
	end
	local data = self.EntityMods and self.EntityMods.starcore
	if not istable(data) then return end
	if istable(data.extra) then
		for _, id in ipairs(data.extra) do
			local e = pasted(created, id)
			if e and e ~= self then self.ExtraParts = self.ExtraParts or {}; self.ExtraParts[e] = true end
		end
	end
	if istable(data.look) then
		for _, l in ipairs(data.look) do
			local e = istable(l) and pasted(created, l.id)
			if e and istable(l.col) then
				if isnumber(l.mode) then e:SetRenderMode(l.mode) end
				e:SetColor(Color(tonumber(l.col[1]) or 255, tonumber(l.col[2]) or 255, tonumber(l.col[3]) or 255, tonumber(l.col[4]) or 255))
				e:DrawShadow(true)
			end
		end
	end
	if isnumber(data.front) then self.FrontYaw = data.front; self:SetNWFloat("starcore_front", data.front) end
	if data.design then self:SetupDesign(data.design) end
	if istable(data.settings) then
		for k, v in pairs(data.settings) do
			if StarCore.Defaults[k] ~= nil and type(v) == type(StarCore.Defaults[k]) then self.Settings[k] = v end
		end
	end
	if istable(data.marks) then
		self.Marks = {}
		for i, m in ipairs(data.marks) do
			if i > StarCore.MaxMarks then break end
			if isvector(m.pos) then self.Marks[i] = { name = tostring(m.name or ("Mark " .. i)):sub(1, 32), pos = m.pos } end
		end
	end
	if data.pilot and created then
		local seat = created[data.pilot]
		if IsValid(seat) and seat:IsVehicle() then self.PilotSeat = seat end
	end
	if data.irisAuto == false then self.SGIrisAuto = false end
	if istable(data.roles) and created then
		self.SeatRoles = {}
		for idx, role in pairs(data.roles) do
			local seat = created[idx]
			if IsValid(seat) and table.HasValue(StarCore.ROLES, role) then self.SeatRoles[seat] = role end
		end
	end
	if istable(data.settings) and istable(data.settings.shieldColor) then self.Settings.shieldColor = data.settings.shieldColor end
	self:SetNWBool("starcore_public", self.Settings.public == true)
	if IsValid(ply) then self:SetNWEntity("starcore_owner", ply) end
end
