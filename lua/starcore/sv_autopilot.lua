-- StarCore server: autopilot. The ship FLIES to a place (no jump): turns towards it, keeps a safe height, climbs over
-- obstacles, slows down near the end. Any pilot key takes over. Targets: a position, or an entity it follows.
function StarCore.AutopilotSet(core, target, follow)
	if target == nil then
		if core.Autopilot then core.Autopilot = nil; core:SetNWBool("starcore_autopilot", false) end
		return true
	end
	if core.Sleeping or core.TooBig then return false, core.TooBig and "too_big" or "second_core" end
	if core.DockedTo then return false, "dock_is_docked" end   --
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

-- (outside the spawn city, the gate inside as target, the ship sank forward into the city wall - it went down to the
-- goal's height at once and only looked straight ahead at its own height). Now it looks along the whole way to the
-- goal (up to LOOK units ahead): hull traces straight down at points on that line, as wide as the ship, find the
-- highest thing under it; the ship keeps that height + CLEAR until the stretch is behind it, and only then sinks to
-- the goal. The goal's own spot does not count (landing there is the point).
local CLEAR, SCAN_EVERY = 120, 0.2
local function scanAhead(core, ap, c, g, dist, speed)
	local mins, maxs = StarCore.ShipBox(core, core:GetAngles())
	local base = core:GetPos()
	local r = math.max(maxs.x - mins.x, maxs.y - mins.y) * 0.5 + 16
	local below = c.z - (base.z + mins.z)                    -- ship centre above its lowest point
	-- not an obstacle: the ship itself, the followed target, people (a passenger on deck would make it climb forever)
	local own = {}
	for _, e in ipairs(core.Parts or {}) do own[e] = true end
	if IsValid(ap.ent) then own[ap.ent] = true end
	local filter = function(e) return not (own[e] or e:IsPlayer() or e:IsNPC()) end
	local up = util.TraceLine({ start = c, endpos = c + Vector(0, 0, 6000), mask = MASK_SOLID_BRUSHONLY })
	local top = math.max(up.HitPos.z - 20, c.z)              -- (the sky or a ceiling)
	local reach = math.max(up.HitPos.z - ((base.z + maxs.z) - c.z) - 40, c.z)   -- highest its centre gets under it
	local bottom = base.z + mins.z
	local dir = Vector(g.x - c.x, g.y - c.y, 0):GetNormalized()
	local look = math.min(dist - (r + 100), math.max(speed * 3, 1500))
	local step = math.max(r * 1.5, 120)
	local safe, safeNear = -math.huge, -math.huge
	local near = speed * 1.5 + r + 150
	local d = 0
	while d <= look do
		local p = c + dir * d
		local tr = util.TraceHull({ start = Vector(p.x, p.y, top), endpos = Vector(p.x, p.y, g.z - below - 60),
			mins = Vector(-r, -r, 0), maxs = Vector(r, r, 1), mask = MASK_SOLID, filter = filter })
		local need
		if tr.StartSolid then
			-- (the gate on the ground as goal, the ship only rose and hung at the map's top: a box starting in a wall
			-- or a lower step of the sky set "as high as it goes" for the ship's centre, which it can never reach, so it
			-- climbed for ever with no forward.) Look again with a thin line.
			local tl = util.TraceLine({ start = Vector(p.x, p.y, top), endpos = Vector(p.x, p.y, g.z - below - 60), mask = MASK_SOLID, filter = filter })
			if tl.Hit and not tl.StartSolid then need = tl.HitPos.z + below + CLEAR end
		elseif tr.Hit and not (d < 2 * r and tr.HitPos.z > bottom - 8) then   -- (not what lies on its own deck)
			need = tr.HitPos.z + below + CLEAR
		end
		if need then
			need = math.min(need, reach)                        -- never above what the ship can reach
			safe = math.max(safe, need)
			if d <= near then safeNear = math.max(safeNear, need) end
		end
		d = d + step
	end
	ap.safe, ap.safeNear, ap.nextScan = safe, safeNear, CurTime() + SCAN_EVERY
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
	-- the way ahead: keep the height it needs, climb first when something higher is close (scanAhead above)
	local r = core.LocalMins and (core.LocalMaxs - core.LocalMins):Length2D() * 0.5 or 100
	if dist > r + 150 then
		if (ap.nextScan or 0) <= CurTime() then scanAhead(core, ap, c, g, dist, (core.Settings.speed or 800)) end
		if ap.safe and ap.safe > g.z then
			inp.up = math.max(inp.up, math.Clamp((ap.safe - c.z) / 250, -1, 1))   -- never sink below it, climb to it
		end
		if ap.safeNear and c.z < ap.safeNear - 40 then inp.fwd = 0; inp.boost = false end   -- climb before going on
	else
		ap.safe, ap.safeNear = nil, nil
	end

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
