-- StarCore: crew and cargo of a ship made of props go through a Stargate with it (Ascension Gates). Without this who stood on
-- the deck touched the horizon alone, rode alone and came out at the far gate beside the ship (release check; a SpaceGrid
-- ship keeps its own crew, sv_keel.lua). While the ship is in the wormhole they are held - not seen, not solid, people
-- see the tunnel too - and then they are on the ship where they were. A ship that is lost in the gate takes them along.
local held = {}   -- core -> { at, t, seen, lost, list }
StarCore.GateHeld = held   -- (tests read it)

local function propShip(core) return IsValid(core) and not IsValid(core:GetNWEntity("starcore_walk_on")) and not core.DockedTo end
local function partOf(x, core)
	if not IsValid(x) then return false end
	if x == core or StarCore.PartCore[x] == core then return true end
	local p = x:GetParent()
	return IsValid(p) and StarCore.PartCore[p] == core
end
local function person(e)
	return (e:IsPlayer() and e:Alive() and not e:InVehicle() and e:GetMoveType() ~= MOVETYPE_NOCLIP and not e.AGPRide) or (e:IsNPC() and e:Health() > 0) or (e.IsNextBot and e:IsNextBot())
end
local function cargo(e, inHand)
	local p = e:GetPhysicsObject()
	return IsValid(p) and p:IsMotionEnabled() and e:GetMoveType() == MOVETYPE_VPHYSICS and e:GetSolid() == SOLID_VPHYSICS and not IsValid(e:GetParent())
		and StarCore.PartCore[e] == nil and not constraint.HasConstraints(e) and (inHand or not e:IsPlayerHolding()) and not e.AGPRideWith and not e.AGPReplicator and not e.NotTeleportable
end
-- on the ship: in its box and standing on a part of it, or with one under it
local function stands(core, e)
	if not StarCore.IsInside(core, e) then return false end
	if partOf(e:GetGroundEntity(), core) then return true end
	local c = e:WorldSpaceCenter()
	return util.TraceLine({ start = c, endpos = c - Vector(0, 0, 160), ignoreworld = true, filter = function(x) return partOf(x, core) end }).Hit
end
local function flyingWith(e)
	for core in pairs(StarCore.Cores) do
		if propShip(core) and core.Helm and core.Helm.on and core.LocalMins and core:GetVelocity():LengthSqr() > 20 * 20 and stands(core, e) then return core end
	end
end

local function tunnel(ply, on)
	if util.NetworkStringToID("AGP.WormholeRide") == 0 or (on and ply:GetInfoNum("cl_stargate_wormhole", 1) == 0) then return end
	ply.AGPRideView = on or nil   -- (AGP takes it off when they die)
	net.Start("AGP.WormholeRide") net.WriteBool(on) net.Send(ply)
end
local function letOut(core, st, place)
	local e = st.e
	if not IsValid(e) then return end
	e.StarCoreGateHeld = nil
	if e.AGPRideWith == core then e.AGPRideWith = nil end
	if not st.notSolid then e:SetNotSolid(false) end
	e:SetNoDraw(st.noDraw)
	local np, na
	if place and IsValid(core) then np, na = LocalToWorld(st.lp, st.la, core:GetPos(), core:GetAngles()) end
	if e:IsPlayer() then
		if st.tunnel then tunnel(e, false) end
		if not st.god then e:GodDisable() end
		e:Freeze(st.frozen)
		if e:Alive() and e:Deaths() == st.deaths and not e:InVehicle() then
			e:SetMoveType(st.move)
			if np then
				e:SetPos(np)
				e:SetEyeAngles(Angle(st.eye.p, st.eye.y + math.AngleDifference(core:GetAngles().y, st.yaw), 0))
			end
			e:SetLocalVelocity(vector_origin)
		end
	elseif st.person then
		e:SetMoveType(st.move)
		if np then e:SetPos(np) e:SetAngles(Angle(0, na.y, 0)) end
	else
		local p = e:GetPhysicsObject()
		if np then e:SetPos(np) e:SetAngles(na) end
		if IsValid(p) then
			if np then p:SetPos(np, true) p:SetAngles(na) end
			p:EnableMotion(true)
			local bp = IsValid(core) and core:GetPhysicsObject()
			p:SetVelocity(IsValid(bp) and bp:GetVelocity() or vector_origin)
			p:Wake()
		end
	end
end
local function release(core, place)
	local h = held[core]
	held[core] = nil
	for _, st in ipairs(h and h.list or {}) do letOut(core, st, place) end
	return h
end
local function hold(core)
	if held[core] then return end
	local list = {}
	held[core] = { at = core:GetPos(), t = CurTime(), list = list }
	local cp, ca = core:GetPos(), core:GetAngles()
	local mid = core:LocalToWorld((core.LocalMins + core.LocalMaxs) / 2)
	for _, e in ipairs(ents.FindInSphere(mid, (core.LocalMaxs - core.LocalMins):Length() / 2 + 120)) do
		local man = person(e)
		if not e.StarCoreGateHeld and not e.SGGateHeld and not IsValid(e:GetParent()) and (man or cargo(e, true)) and stands(core, e) then
			if not man then e:ForcePlayerDrop() end   -- (in somebody's hand or physgun)
			local p = e:GetPhysicsObject()
			local lp, la = WorldToLocal(man and e:GetPos() or p:GetPos(), man and Angle(0, e:GetAngles().y, 0) or p:GetAngles(), cp, ca)
			local st = { e = e, person = man, lp = lp, la = la, noDraw = e:GetNoDraw(), notSolid = bit.band(e:GetSolidFlags(), FSOLID_NOT_SOLID) > 0, move = e:GetMoveType() }
			list[#list + 1] = st
			e.StarCoreGateHeld, e.AGPRideWith = true, core
			e:SetNotSolid(true)
			e:SetNoDraw(true)
			if e:IsPlayer() then
				st.god, st.frozen, st.eye, st.yaw, st.deaths = e:HasGodMode(), e:IsFrozen(), e:EyeAngles(), ca.y, e:Deaths()
				e:GodEnable()
				e:Freeze(true)
				e:SetMoveType(MOVETYPE_NONE)
			elseif man then e:SetMoveType(MOVETYPE_NONE)
			else p:EnableMotion(false) end
		end
	end
	timer.Simple(0, function()
		for _, st in ipairs(IsValid(core) and core.AGPRideWith and held[core] and held[core].list or {}) do
			if IsValid(st.e) and st.e:IsPlayer() then st.tunnel = true tunnel(st.e, true) end
		end
	end)
end

hook.Add("StarGate.Teleport", "StarCore.GateCrew", function(e, eh)
	if not IsValid(e) then return end
	local core = e:GetClass() == "starcore" and e or StarCore.PartCore[e]
	if IsValid(core) then
		if propShip(core) and core.Helm and core.Helm.on and core.LocalMins then hold(core) end
		return
	end
	if e.StarCoreGateHeld then return false end
	if not (person(e) or cargo(e, true)) then return end
	-- (who stands far forward on the deck reaches the horizon before the ship itself goes in; a gate on board is the ship's own)
	local ship = flyingWith(e)
	local g = IsValid(eh) and eh:GetParent()
	if ship and not (IsValid(g) and StarCore.PartCore[g] == ship) then return false end
end)
hook.Add("StarGate.Lost", "StarCore.GateCrew", function(e)
	local core = IsValid(e) and (e:GetClass() == "starcore" and e or StarCore.PartCore[e])
	if core and held[core] then held[core].lost = true end
end)
hook.Add("Tick", "StarCore.GateCrew", function()
	for core, h in pairs(held) do
		if h.lost or not IsValid(core) then
			-- (lost in the gate: whoever was aboard too; only removed - undo, cleanup -: they are let go where they were held)
			local st = release(core, false)
			if st.lost then
				local people = {}
				for _, x in ipairs(st.list) do
					if IsValid(x.e) then if x.person then people[#people + 1] = x.e else x.e:Remove() end end
				end
				StarCore.KillAboard(people, core)
			end
		else
			local p1 = core.PhysParts and core.PhysParts[1]
			local riding = core.AGPRideWith ~= nil or (IsValid(p1) and p1.AGPRideWith ~= nil)
			if riding then h.seen = true
			elseif h.seen or core:GetPos():DistToSqr(h.at) > 500 * 500 or CurTime() > h.t + 15 then release(core, true) end
		end
	end
end)
hook.Add("PlayerDisconnected", "StarCore.GateCrew", function(ply) ply.StarCoreGateHeld = nil end)

-- The deck one walks on never hurts: a moving part of one's own ship touches the feet harder than the game likes now and then
-- (server test with 100 ms lag: 20 damage while walking in full flight). Any other hit counts as ever.
hook.Add("EntityTakeDamage", "StarCore.OwnDeck", function(e, d)
	if not e:IsPlayer() or not d:IsDamageType(DMG_CRUSH) then return end
	local core = e.StarCoreWalkCore
	if not IsValid(core) or core:GetClass() ~= "starcore" or e:InVehicle() then return end
	if partOf(d:GetInflictor(), core) or partOf(d:GetAttacker(), core) then return true end
end)
