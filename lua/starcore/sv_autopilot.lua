-- StarCore server: autopilot. The ship FLIES to a place (no jump): turns towards it, keeps a safe height, climbs over
-- obstacles, slows down near the end. Any pilot key takes over. Targets: a position, or an entity it follows.
function StarCore.AutopilotSet(core, target, follow)
	if target == nil then
		if core.Autopilot then core.Autopilot = nil; core:SetNWBool("starcore_autopilot", false) end
		return true
	end
	if core.Sleeping or core.TooBig then return false, core.TooBig and "too_big" or "second_core" end
	if not core.Helm.on then StarCore.HelmSetOn(core, true) end
	if core.Helm.frozen then StarCore.SetFrozen(core, false) end
	core.Autopilot = { pos = isvector(target) and target or nil, ent = IsEntity(target) and target or nil, follow = follow }
	core:SetNWBool("starcore_autopilot", true)
	return true
end

-- target position of the ship centre right now
local function goal(core)
	local ap = core.Autopilot
	if IsValid(ap.ent) then
		local up = core.LocalMaxs and (core.LocalMaxs.z - core.LocalMins.z) or 200
		return ap.ent:GetPos() + Vector(0, 0, up + 300)
	end
	return ap.pos
end

-- returns a pilot-like input table, or nil when the autopilot is off
function StarCore.AutopilotInput(core)
	local ap = core.Autopilot
	if not ap then return nil end
	if ap.ent ~= nil and not IsValid(ap.ent) then StarCore.AutopilotSet(core, nil) return nil end
	local g = goal(core)
	if not g then StarCore.AutopilotSet(core, nil) return nil end
	local c = StarCore.ShipCenter(core)
	local shipAng = core:LocalToWorldAngles(core.Helm.refAng or Angle())
	local flat = Vector(g.x - c.x, g.y - c.y, 0)
	local dist = flat:Length()
	local dz = g.z - c.z
	local inp = { fwd = 0, turn = 0, up = 0, boost = false }

	local nearXY, nearZ = 150, 120
	if ap.precise then nearXY, nearZ = 60, 12 end
	-- precise (landing): standing on the ground and unable to go lower for a second = arrived
	local realVZ = IsValid(core:GetPhysicsObject()) and core:GetPhysicsObject():GetVelocity().z or 0
	if ap.precise and dist < nearXY and dz < 20 and math.abs(realVZ) < 8 then
		ap.stall = (ap.stall or 0) + FrameTime()
	else
		ap.stall = 0
	end
	if (dist < nearXY and math.abs(dz) < nearZ) or (ap.stall or 0) > 1 then
		if not ap.follow then
			StarCore.AutopilotSet(core, nil)
			StarCore.NotifyShip(core, "autopilot_arrived", NOTIFY_GENERIC)
			hook.Run("StarCore.Event", core, "autopilot_arrived")
		end
		return inp
	end
	-- above the spot already (e.g. landing straight down): no turning, no forward creep, only up/down
	if dist >= nearXY then
		local wantYaw = flat:Angle().y
		local err = math.AngleDifference(wantYaw, shipAng.y)
		inp.turn = math.Clamp(err / 25, -1, 1)
		if math.abs(err) < 35 then inp.fwd = math.Clamp(dist / 1200, 0.15, 1) end
		inp.boost = dist > 6000 and math.abs(err) < 10
	end
	inp.up = math.Clamp(dz / 250, -1, 1)
	if ap.precise and math.abs(dz) < 150 then inp.up = math.Clamp(dz / 60, -0.4, 0.4) end -- gentle touchdown

	-- obstacle ahead (the ship's own size, about 1.5 s of flight): climb instead of crashing
	if inp.fwd > 0 and core.LocalMins then
		local speed = (core.Settings.speed or 800) * inp.fwd
		local mins, maxs = StarCore.ShipBox(core, core:GetAngles())
		local dir = Angle(0, shipAng.y, 0):Forward()
		local tr = util.TraceHull({ start = core:GetPos(), endpos = core:GetPos() + dir * math.max(speed * 1.5, 200), mins = mins * 0.95, maxs = maxs * 0.95,
			filter = core.Parts, mask = MASK_SOLID })
		if tr.Hit and not (IsValid(ap.ent) and tr.Entity == ap.ent) then
			inp.fwd = 0
			inp.up = 1
		end
	end
	return inp
end
