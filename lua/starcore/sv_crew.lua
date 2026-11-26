-- StarCore server: crew seats (pilot, gunner, engineer, passenger) and hull points with damage and repair.
-- Hull: the ship has hull points from its mass. Hits on ship parts take them away (a raised shield blocks most hits
-- before they arrive). At 0 the ship is disabled (no flight, no weapons, no jumps), nothing is deleted.
-- Repair: the StarCore repair tool, or an engineer on board (slowly).
StarCore.ROLES = { "pilot", "gunner", "engineer", "passenger" }

-- seats of a ship: role from the tool, from the seat type in the spawn menu, or "first seat = pilot"
function StarCore.CrewAttach(core)
	core.SeatRoles = core.SeatRoles or {}
	local pilotSet = IsValid(core.PilotSeat)
	for i, seat in ipairs(core.Seats or {}) do
		local role = core.SeatRoles[seat] or seat.StarCoreRolePreset
		if not role then role = (seat == core.PilotSeat or (not pilotSet and i == 1)) and "pilot" or "passenger" end
		if role == "pilot" and core.PilotSeat ~= seat and IsValid(core.PilotSeat) and core.SeatRoles[seat] == nil then role = "passenger" end
		if seat:GetNWString("starcore_role") ~= role then seat:SetNWString("starcore_role", role) end
		if seat:GetNWEntity("starcore") ~= core then seat:SetNWEntity("starcore", core) end
	end
	-- hull points follow the ship's mass (a changed ship keeps its damage in percent)
	local max = math.Clamp(math.floor((core.Mass or 1000) * 3), 1000, 500000)
	if core.HullMax ~= max then
		local frac = core.HullMax and core.HullMax > 0 and (core.Hull or max) / core.HullMax or 1
		core.HullMax = max
		core.Hull = math.floor(max * frac)
	end
	core:SetNWInt("starcore_hull_max", StarCore.CV.hull:GetBool() and core.HullMax or 0)
	core:SetNWInt("starcore_hull", core.Hull)
end

function StarCore.SeatRole(core, seat)
	return IsValid(seat) and seat:GetNWString("starcore_role", "passenger") or "passenger"
end

-- people in a role right now
function StarCore.CrewIn(core, role)
	local list = {}
	for _, seat in ipairs(core.Seats or {}) do
		if IsValid(seat) and StarCore.SeatRole(core, seat) == role then
			local d = seat:GetDriver()
			if IsValid(d) and StarCore.CanControl(core, d) then list[#list + 1] = d end
		end
	end
	return list
end

-- the tool cycles a seat's role
function StarCore.CycleSeatRole(core, seat)
	local cur = StarCore.SeatRole(core, seat)
	local idx = 1
	for i, r in ipairs(StarCore.ROLES) do if r == cur then idx = i end end
	local nextRole = StarCore.ROLES[idx % #StarCore.ROLES + 1]
	core.SeatRoles[seat] = nextRole
	if nextRole == "pilot" then
		-- only one pilot seat: the old one becomes a normal seat again
		if IsValid(core.PilotSeat) and core.PilotSeat ~= seat then core.SeatRoles[core.PilotSeat] = nil end
		core.PilotSeat = seat
	elseif core.PilotSeat == seat then
		-- this seat stops being the pilot seat: the first seat without another role takes over
		core.PilotSeat = nil
		for _, s in ipairs(core.Seats or {}) do
			local r = core.SeatRoles[s] or s.StarCoreRolePreset
			if s ~= seat and (r == nil or r == "pilot") then core.PilotSeat = s break end
		end
	end
	core:SetNWEntity("starcore_pilotseat", core.PilotSeat or NULL)
	StarCore.CrewAttach(core)
	return nextRole
end

-- seats from the spawn menu know their role already
hook.Add("PlayerSpawnedVehicle", "StarCore.SeatPreset", function(ply, veh)
	local t = veh.VehicleTable
	if t and t.StarCoreRole then veh.StarCoreRolePreset = t.StarCoreRole end
end)

-- ===== hull =====
function StarCore.HullDamage(core, amount)
	if not StarCore.CV.hull:GetBool() or not core.HullMax or amount <= 0 then return end
	local before = core.Hull
	core.LastHit = CurTime()   -- (engineers pause after a hit: CrewThink)
	core.Hull = math.max(core.Hull - amount, 0)
	core:SetNWInt("starcore_hull", core.Hull)
	local pct = core.Hull / core.HullMax
	if before / core.HullMax >= 0.3 and pct < 0.3 then hook.Run("StarCore.Event", core, "hull_low") end
	if before / core.HullMax >= 0.1 and pct < 0.1 then hook.Run("StarCore.Event", core, "hull_critical") end
	if before > 0 and core.Hull == 0 then
		if StarCore.CV.destroyMode:GetInt() == 0 then StarCore.Disable(core, true) else StarCore.Destroy(core) end
	end
end

function StarCore.HullRepair(core, amount)
	if not core.HullMax then return 0 end
	local before = core.Hull
	core.Hull = math.min(core.Hull + amount, core.HullMax)
	core:SetNWInt("starcore_hull", core.Hull)
	if core.Disabled and core.Hull >= core.HullMax * 0.25 then StarCore.Disable(core, false) end
	return core.Hull - before
end

-- destroyed ship: everything offline (falls if it was flying), dramatic but nothing is removed
function StarCore.Disable(core, off)
	core.Disabled = off
	core:SetNWBool("starcore_disabled", off)
	if off then
		StarCore.HelmSetOn(core, false)
		if StarCore.StopWeapons then StarCore.StopWeapons(core) end
		if StarCore.AutopilotSet then StarCore.AutopilotSet(core, nil) end
		StarCore.NotifyShip(core, "ship_disabled", NOTIFY_ERROR)
		for i = 1, math.min(#(core.Parts or {}), 6) do
			local e = core.Parts[math.random(#core.Parts)]
			if IsValid(e) then
				local fx = EffectData(); fx:SetOrigin(e:WorldSpaceCenter()); fx:SetMagnitude(2)
				timer.Simple(i * 0.25, function() util.Effect("Explosion", fx) end)
			end
		end
	else
		StarCore.NotifyShip(core, "ship_repaired", NOTIFY_GENERIC)
	end
end

-- who is in or on a ship: in its seats, standing on it, with it under their feet - players, NPCs, nextbots. (Not who only is
-- in the box round it: under its belly, beside its wing.)
function StarCore.PeopleAboard(core)
	local list, seen = {}, {}
	local function add(p) if IsValid(p) and not seen[p] then seen[p] = true list[#list + 1] = p end end
	local function part(x) return IsValid(x) and (StarCore.PartCore[x] == core or (IsValid(x:GetParent()) and StarCore.PartCore[x:GetParent()] == core)) end
	for _, seat in ipairs(core.Seats or {}) do if IsValid(seat) then add(seat:GetDriver()) end end
	for _, e in ipairs(core.Parts or {}) do if IsValid(e) and e:IsVehicle() then add(e:GetDriver()) end end
	if not core.LocalMins then return list end
	local c, r = core:LocalToWorld((core.LocalMins + core.LocalMaxs) / 2), (core.LocalMaxs - core.LocalMins):Length() / 2 + 120
	for _, e in ipairs(ents.FindInSphere(c, r)) do
		local person = (e:IsPlayer() and e:Alive()) or (e:IsNPC() and e:Health() > 0) or (e.IsNextBot and e:IsNextBot())
		if person and not seen[e] and StarCore.IsInside(core, e) then
			local from = e:WorldSpaceCenter()
			if part(e:GetGroundEntity()) or util.TraceLine({ start = from, endpos = from - Vector(0, 0, 160), ignoreworld = true, filter = part }).Hit then add(e) end
		end
	end
	return list
end
function StarCore.KillAboard(list, core)
	for _, e in ipairs(list) do
		if IsValid(e) and not (e:IsPlayer() and (not e:Alive() or e:HasGodMode())) then
			if e:IsPlayer() and e:InVehicle() then e:ExitVehicle() end
			local d = DamageInfo()
			d:SetDamage(10000)
			d:SetDamageType(DMG_BLAST)
			d:SetAttacker(IsValid(core) and core or game.GetWorld())
			d:SetInflictor(IsValid(core) and core or game.GetWorld())
			d:SetDamagePosition(e:WorldSpaceCenter())
			e:TakeDamageInfo(d)
			if e:IsPlayer() and e:Alive() then e:Kill() end
		end
	end
end

-- destroyed: explosions, the welds break, the parts fall as a burning wreck (mode 1) or vanish (mode 2); the core is gone
function StarCore.Destroy(core)
	if core.Destroyed then return end
	core.Destroyed = true
	hook.Run("StarCore.Event", core, "destroyed")
	StarCore.HelmSetOn(core, false)
	if StarCore.StopWeapons then StarCore.StopWeapons(core) end
	if StarCore.CloakSet and core.Cloaked then StarCore.CloakSet(core, false) end
	local mode = StarCore.CV.destroyMode:GetInt()
	local parts = table.Copy(core.Parts or {})
	local aboard = StarCore.PeopleAboard(core)
	local c = StarCore.ShipCenter(core)
	local radius = math.max(core:GetNWVector("starcore_size"):Length() * 0.5, 150)
	util.ScreenShake(c, 12, 6, 2.5, radius * 4)
	for i, e in ipairs(parts) do
		if IsValid(e) and e ~= core and not e:IsPlayer() then
			if e:IsVehicle() and IsValid(e:GetDriver()) then e:GetDriver():ExitVehicle() end
			timer.Simple(math.min(i * 0.04, 2), function()
				if not IsValid(e) then return end
				if i % 3 == 1 then
					local fx = EffectData(); fx:SetOrigin(e:WorldSpaceCenter()); fx:SetMagnitude(3); fx:SetScale(2)
					util.Effect("Explosion", fx)
				end
				if mode == 2 then e:Remove() return end
				constraint.RemoveAll(e)
				e:SetParent(nil)
				local p = e:GetPhysicsObject()
				if IsValid(p) then
					p:EnableMotion(true)
					p:EnableGravity(true)
					p:Wake()
					p:ApplyForceCenter((e:WorldSpaceCenter() - c):GetNormalized() * p:GetMass() * math.Rand(150, 450) + Vector(0, 0, p:GetMass() * 120))
					p:AddAngleVelocity(VectorRand() * 200)
				end
				if math.random() < 0.3 then e:Ignite(math.Rand(8, 20)) end
				e:SetColor(Color(90, 80, 70, e:GetColor().a))
			end)
		end
	end
	-- (the seated were only put out)
	StarCore.KillAboard(aboard, core)
	timer.Simple(0.2, function() if IsValid(core) then core:Remove() end end)
end

hook.Add("EntityTakeDamage", "StarCore.Hull", function(ent, dmg)
	-- the own ship's shots and blasts (AGP weapons on this ship) never count: AGP blocks them too, but the order of
	-- damage hooks is not fixed
	if StarGate and StarGate.OwnShipDamage and StarGate.OwnShipDamage(ent, dmg) then return end
	-- an unseen helper body inside the ship (SpaceGrid's keel): an area hit already counts on the part round it
	if ent.StarCoreNoDamage then return end
	local core = StarCore.PartCore and StarCore.PartCore[ent]
	if not IsValid(core) then return end
	local att = dmg:GetAttacker()
	if IsValid(att) and StarCore.PartCore[att] == core then return end -- own guns / own parts bumping
	if dmg:IsDamageType(DMG_CRUSH) and dmg:GetDamage() < 50 then return end -- small knocks while flying
	-- Ascension Gates' weapon balance: "Series power" ranks the weapons against ship hulls as in the series, hand weapons
	-- 5 %; "AGP sandbox" keeps each weapon's own damage (agp_weapon_balance, stargate/server/ship_weapons.lua)
	local f = StarGate and StarGate.HullFactor and StarGate.HullFactor(dmg) or 1
	StarCore.HullDamage(core, dmg:GetDamage() * f)
end)

-- engineers on board: slow repair (and the ship can not fly while disabled). (it was 1 % a second with any number
-- of engineers, a full repair in 100 s even in a fight): 0.5 % of the hull a second for each engineer, at most two
-- working (full from empty in about 3.5 minutes with one, under 2 with two), and none for 5 s after the last hit.
-- Parts of a point are kept, so small ships (1000 hull = 5 a second) repair evenly.
local REPAIR_RATE, REPAIR_MAX_ENGINEERS, REPAIR_PAUSE = 0.005, 2, 5   -- (0.5 % and 5 s)
StarCore.RepairRate, StarCore.RepairMaxEngineers, StarCore.RepairPause = REPAIR_RATE, REPAIR_MAX_ENGINEERS, REPAIR_PAUSE
function StarCore.CrewThink(core)
	if (core.NextCrew or 0) > CurTime() then return end
	core.NextCrew = CurTime() + 1
	if not core.HullMax or core.Hull >= core.HullMax then core.RepairCarry = 0 return end
	local n = math.min(#StarCore.CrewIn(core, "engineer"), REPAIR_MAX_ENGINEERS)
	if n == 0 or CurTime() - (core.LastHit or -math.huge) < REPAIR_PAUSE then return end
	local amount = core.HullMax * REPAIR_RATE * n + (core.RepairCarry or 0)
	local whole = math.floor(amount)
	core.RepairCarry = amount - whole
	if whole > 0 then StarCore.HullRepair(core, whole) end
end
