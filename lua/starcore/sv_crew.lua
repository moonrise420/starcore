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

-- destroyed: explosions, the welds break, the parts fall as a burning wreck (mode 1) or vanish (mode 2); the core is gone
function StarCore.Destroy(core)
	if core.Destroyed then return end
	core.Destroyed = true
	hook.Run("StarCore.Event", core, "destroyed")
	StarCore.NotifyShip(core, "ship_destroyed", NOTIFY_ERROR)
	StarCore.HelmSetOn(core, false)
	if StarCore.StopWeapons then StarCore.StopWeapons(core) end
	if StarCore.CloakSet and core.Cloaked then StarCore.CloakSet(core, false) end
	local mode = StarCore.CV.destroyMode:GetInt()
	local parts = table.Copy(core.Parts or {})
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
	timer.Simple(0.2, function() if IsValid(core) then core:Remove() end end)
end

hook.Add("EntityTakeDamage", "StarCore.Hull", function(ent, dmg)
	local core = StarCore.PartCore and StarCore.PartCore[ent]
	if not IsValid(core) then return end
	local att = dmg:GetAttacker()
	if IsValid(att) and StarCore.PartCore[att] == core then return end -- own guns / own parts bumping
	if dmg:IsDamageType(DMG_CRUSH) and dmg:GetDamage() < 50 then return end -- small knocks while flying
	StarCore.HullDamage(core, dmg:GetDamage())
end)

-- engineer on board: slow repair (and the ship can not fly while disabled)
function StarCore.CrewThink(core)
	if (core.NextCrew or 0) > CurTime() then return end
	core.NextCrew = CurTime() + 1
	if core.HullMax and core.Hull < core.HullMax and #StarCore.CrewIn(core, "engineer") > 0 then
		StarCore.HullRepair(core, math.ceil(core.HullMax * 0.01))
	end
end
