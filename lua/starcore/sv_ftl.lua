-- StarCore server: hyperspace jumps. IDLE > CHARGING > JUMPING > COOLDOWN > IDLE.
-- The landing spot is checked with the ship's real size; if it is blocked, nearby spots are tried; if none is free the
-- jump is cancelled (never an endless retry loop, never a fallback onto a player).
local FTL = StarCore.FTL
local OUT_TIME = 0.6 -- seconds of the "jump out" effect before the ship moves

local function setState(core, state, t0, t1)
	core.FTLData.state = state
	core:SetNWInt("starcore_ftl", state)
	core:SetNWFloat("starcore_ftl_t0", t0 or 0)
	core:SetNWFloat("starcore_ftl_t1", t1 or 0)
end

local shipCenter

local function effect(core, phase, from, to)
	local fx = EffectData()
	fx:SetOrigin(from)
	fx:SetStart(to or from)
	fx:SetEntity(core)
	fx:SetMagnitude(math.max(core:GetNWVector("starcore_size"):Length() * 0.5, 64))
	fx:SetFlags(phase) -- 1 charge, 2 out, 3 in
	util.Effect("starcore_jump", fx, true, true)
end

function shipCenter(core, corePos, coreAng)
	-- only the position (LocalToWorld also returns an angle, which must not reach callers as an extra value)
	local pos = LocalToWorld((core.LocalMins + core.LocalMaxs) * 0.5, Angle(), corePos or core:GetPos(), coreAng or core:GetAngles())
	return pos
end

StarCore.ShipCenter = shipCenter

-- free place for the ship with the core at pos? (inside the map, no world or other props in the way)
function StarCore.SpotIsFree(core, pos, filter)
	local mins, maxs = StarCore.ShipBox(core, core:GetAngles())
	if not util.IsInWorld(pos) then return false end
	for i = 0, 7 do
		local c = pos + Vector(bit.band(i, 1) > 0 and maxs.x or mins.x, bit.band(i, 2) > 0 and maxs.y or mins.y, bit.band(i, 4) > 0 and maxs.z or mins.z)
		if not util.IsInWorld(c) then return false end
	end
	local tr = util.TraceHull({ start = pos, endpos = pos + Vector(0, 0, 1), mins = mins, maxs = maxs, filter = filter, mask = MASK_SOLID })
	return not tr.Hit and not tr.StartSolid
end

-- the target first, then above, around, below (all within a few ship sizes)
function StarCore.FindSafeSpot(core, pos)
	StarCore.Scan(core)
	local filter = table.Copy(core.Parts)
	for _, p in ipairs(StarCore.Passengers(core)) do filter[#filter + 1] = p end
	for _, ply in ipairs(player.GetAll()) do if ply:InVehicle() and table.HasValue(core.Parts, ply:GetVehicle()) then filter[#filter + 1] = ply end end
	local size = core.LocalMaxs - core.LocalMins
	local stepUp = math.max(size.z, 150) * 1.2
	local ring = math.max(size.x, size.y, 150) * 1.2
	local tries = { pos }
	for k = 1, 5 do tries[#tries + 1] = pos + Vector(0, 0, stepUp * k) end
	for k = 1, 2 do
		for a = 0, 315, 45 do
			local r = math.rad(a)
			tries[#tries + 1] = pos + Vector(math.cos(r) * ring * k, math.sin(r) * ring * k, 0)
			tries[#tries + 1] = pos + Vector(math.cos(r) * ring * k, math.sin(r) * ring * k, stepUp)
		end
	end
	for k = 1, 2 do tries[#tries + 1] = pos - Vector(0, 0, stepUp * k) end
	for i, t in ipairs(tries) do
		if StarCore.SpotIsFree(core, t, filter) then return t, i end
	end
	return nil
end

-- target = { kind = "mark", index = n } | { kind = "coord", pos = Vector } | { kind = "gate", id = entindex } | { kind = "owner" }
function StarCore.ResolveTarget(core, target)
	if target.kind == "mark" then
		local m = core.Marks[target.index]
		return m and m.pos
	elseif target.kind == "coord" and isvector(target.pos) then
		return target.pos
	elseif target.kind == "gate" and StarCore.SG and StarCore.SG.Available() then
		return StarCore.SG.JumpSpot(core, Entity(tonumber(target.id) or 0))
	elseif target.kind == "contact" then
		local e = Entity(tonumber(target.id) or 0)
		if not IsValid(e) or not StarCore.ContactOf(core, e) then return nil end
		-- above the contact with room for the ship (the safe-spot search moves it if needed)
		local up = core.LocalMaxs and (core.LocalMaxs.z - core.LocalMins.z) or 200
		local center = StarCore.ShipCenter(core)
		return e:GetPos() + Vector(0, 0, up + 400) - (center - core:GetPos())
	elseif target.kind == "owner" then
		local o = core:GetNWEntity("starcore_owner")
		if IsValid(o) and o:Alive() then
			-- above the owner, so the ship does not land on them
			local up = core.LocalMaxs and (core.LocalMaxs.z - core.LocalMins.z) or 200
			return o:GetPos() + Vector(0, 0, up + 300)
		end
	end
end

function StarCore.RequestJump(core, ply, target)
	local d = core.FTLData
	if core.Sleeping or core.TooBig then return false, core.TooBig and "too_big" or "second_core" end
	if core.Disabled then return false, "ship_disabled" end
	if d.state == FTL.COOLDOWN then return false, "cooling_down" end
	if d.state == FTL.JUMPING then return false, "busy" end
	local pos = StarCore.ResolveTarget(core, target)
	if not pos then return false, "no_target" end
	if not util.IsInWorld(pos) then return false, "outside_map" end
	local range = StarCore.CV.jumpRange:GetFloat()
	if range > 0 and pos:Distance(core:GetPos()) > range then return false, "too_far" end
	if pos:Distance(core:GetPos()) < 50 then return false, "already_there" end
	local cost = StarCore.JumpCost and StarCore.JumpCost(core, pos:Distance(core:GetPos())) or 0
	if cost > 0 and StarCore.JumpEnergy and StarCore.JumpEnergy(core) < cost then return false, "no_energy" end   -- AGP 2026-11-08: the ship's networks (sv_power.lua)
	d.cost = cost
	local charge = math.max(core.Settings.charge, StarCore.CV.chargeMin:GetFloat())
	d.target = pos
	d.by = ply
	setState(core, FTL.CHARGING, CurTime(), CurTime() + charge)
	core:EmitSound("ambient/levels/labs/teleport_preblast_suckin1.wav", 85, 100)
	effect(core, 1, shipCenter(core))
	hook.Run("StarCore.Event", core, "jump_charge")
	return true
end

function StarCore.CancelJump(core)
	if core.FTLData.state ~= FTL.CHARGING then return false end
	setState(core, FTL.IDLE)
	core:StopSound("ambient/levels/labs/teleport_preblast_suckin1.wav")
	return true
end

function StarCore.FTLThink(core)
	local d = core.FTLData
	if not d or d.state == FTL.IDLE then return end
	local now = CurTime()
	if d.state == FTL.CHARGING and now >= core:GetNWFloat("starcore_ftl_t1") then
		local spot = StarCore.FindSafeSpot(core, d.target)
		if not spot then
			setState(core, FTL.IDLE)
			StarCore.NotifyShip(core, "no_safe_spot", NOTIFY_ERROR)
			core:EmitSound("buttons/button10.wav")
			return
		end
		d.spot = spot
		setState(core, FTL.JUMPING, now, now + OUT_TIME)
		if core.Helm and core.Helm.frozen then StarCore.SetFrozen(core, false) end
		core:EmitSound("ambient/levels/citadel/portal_beam_shoot" .. math.random(1, 6) .. ".wav", 90)
		effect(core, 2, shipCenter(core), shipCenter(core, spot))
	elseif d.state == FTL.JUMPING and now >= core:GetNWFloat("starcore_ftl_t1") then
		-- something may have moved into the spot during the jump-out: check once more
		local spot = d.spot
		local filter = table.Copy(core.Parts)
		if not StarCore.SpotIsFree(core, spot, filter) then spot = StarCore.FindSafeSpot(core, d.target) end
		if not spot then
			setState(core, FTL.IDLE)
			StarCore.NotifyShip(core, "no_safe_spot", NOTIFY_ERROR)
			return
		end
		if d.cost and d.cost > 0 and not StarCore.PayJump(core, d.cost) then
			setState(core, FTL.IDLE)
			StarCore.NotifyShip(core, "no_energy", NOTIFY_ERROR)
			return
		end
		d.lastSafe = core:GetPos()
		local fromCenter = shipCenter(core)
		d.movedParts, d.movedPeople = StarCore.MoveShip(core, spot, core:GetAngles())
		sound.Play("ambient/machines/teleport4.wav", shipCenter(core), 100, 100)
		hook.Run("StarCore.Event", core, "arrived")
		effect(core, 3, shipCenter(core), fromCenter)
		local cd = math.max(core.Settings.cooldown, StarCore.CV.cooldownMin:GetFloat())
		setState(core, FTL.COOLDOWN, now, now + cd)
		hook.Run("StarCore.Jumped", core, d.lastSafe, spot)
	elseif d.state == FTL.COOLDOWN and now >= core:GetNWFloat("starcore_ftl_t1") then
		setState(core, FTL.IDLE)
	end
end

-- marks: the core position, so a jump back lands exactly where the mark was saved (no drift)
function StarCore.SaveMark(core, index, name)
	if index < 1 or index > StarCore.MaxMarks then return false end
	core.Marks[index] = { name = (name and name ~= "" and name or ("Mark " .. index)):sub(1, 32), pos = core:GetPos() }
	StarCore.SyncNW(core)
	return true
end
