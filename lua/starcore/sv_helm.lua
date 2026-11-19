-- StarCore server: flight. The whole ship moves as one rigid body: every part gets the same motion each tick,
-- so welds are never stressed. Gravity is off while the helm is on; the ship holds its height and stays level.
local Defaults = StarCore.Defaults

local function approach(cur, target, step)
	if cur < target then return math.min(cur + step, target) end
	return math.max(cur - step, target)
end

-- which way is "forward" for the pilot: the seat's eye direction (seats are turned 90 degrees in Source)
local function seatYaw(seat)
	local id = seat:LookupAttachment("vehicle_driver_eyes")
	if id and id > 0 then
		local a = seat:GetAttachment(id)
		if a then return a.Ang.y end
	end
	return seat:GetAngles().y + 90
end

local function setFrozen(core, frozen)
	for _, e in ipairs(core.PhysParts or {}) do
		local p = IsValid(e) and e:GetPhysicsObject()
		if IsValid(p) then
			p:EnableMotion(not frozen)
			if not frozen then p:Wake() end
		end
	end
	core.Helm.frozen = frozen
	core:SetNWBool("starcore_frozen", frozen)
end
StarCore.SetFrozen = setFrozen

-- the ship's level frame (pitch/roll 0) stored relative to the core, so the core can be welded at any angle
-- which way is the ship's front: (2026-11-14, owner: "how can the player set for the starcore were oriantation forward is")
-- 1. the front the player set in the core's menu ("Set front: the way I look", core.FrontYaw, local to the core, duped),
-- 2. else the pilot seat's eye direction, 3. else the way the core itself points
function StarCore.FrontYaw(core)
	if isnumber(core.FrontYaw) then return core:LocalToWorldAngles(Angle(0, core.FrontYaw, 0)).y end
	return IsValid(core.PilotSeat) and seatYaw(core.PilotSeat) or core:GetAngles().y
end

-- 2026-11-18 (owner: "when i press forward it makes a little wobble to the left ... back a wobble to the right"): while the
-- helm flies, the game's air drag is off on every part. It pulled each part on its own, and the weld turned that into a
-- turn of the whole ship when the parts were not lined up (test ptwobble: core 25 units beside the seat, 3.4 degrees).
-- The helm sets the speed itself; the drag comes back as it was when the helm lets go.
function StarCore.HelmDrag(e, p, on)
	if on then
		if e.StarCoreDrag == nil then e.StarCoreDrag = p:IsDragEnabled() end
		p:EnableDrag(false)
	elseif e.StarCoreDrag ~= nil then
		p:EnableDrag(e.StarCoreDrag)
		e.StarCoreDrag = nil
	end
end

function StarCore.HelmRelock(core)
	local yaw = StarCore.FrontYaw(core)
	core.Helm.refAng = core:WorldToLocalAngles(Angle(0, yaw, 0))
	core.Helm.holdYaw = nil
	core.Helm.targetZ = nil
	core.Helm.vel = Vector(0, 0, 0)
	core.Helm.angvel = Vector(0, 0, 0)
end

function StarCore.HelmSetOn(core, on)
	if not IsValid(core) or not core.Helm then return end
	if on and (core.Sleeping or core.TooBig or core.Disabled or core.DockedTo) then return end   -- (docked: the big ship flies it)
	core.Helm.on = on
	core.Helm.idle = 0
	core:SetNWBool("starcore_hover", on)
	if on then
		StarCore.Scan(core)
		StarCore.HelmRelock(core)
	end
	for _, e in ipairs(core.PhysParts or {}) do
		local p = IsValid(e) and e:GetPhysicsObject()
		if IsValid(p) then
			p:EnableGravity(not on)
			StarCore.HelmDrag(e, p, on)
			if on then p:EnableMotion(true) end
			p:Wake()
		end
	end
	core.Helm.frozen = false
	core:SetNWBool("starcore_frozen", false)
end

-- mouse steering (per player, starcore_mouse_steer): the mouse moves of every command are summed up here,
-- the helm takes them once per tick. Looking around (the look-around key, Alt by default: starcore_looking, cl_hud.lua)
-- = the view is free instead.
local function mouseSteer(ply)
	return ply:GetInfoNum("starcore_mouse_steer", 0) == 1 and ply:GetInfoNum("starcore_looking", 0) == 0
end
hook.Add("StartCommand", "StarCore.MouseSteer", function(ply, cmd)
	if not ply:InVehicle() or not ply.StarCorePilot then return end
	ply.StarCoreMouseX = math.Clamp((ply.StarCoreMouseX or 0) + cmd:GetMouseX(), -1000, 1000)
	ply.StarCoreMouseY = math.Clamp((ply.StarCoreMouseY or 0) + cmd:GetMouseY(), -1000, 1000)
end)

-- mouse -> a virtual stick: X is a turn rate that springs back when the mouse rests, Y holds a nose angle
-- that drifts back to level slowly. Both are clamped and filtered, so the ship never jitters.
local MAX_PITCH = 30
local MAX_BANK = 22
local function readMouse(core, ply, inp)
	local h = core.Helm
	local dt = FrameTime()
	local dx, dy = ply.StarCoreMouseX or 0, ply.StarCoreMouseY or 0
	ply.StarCoreMouseX, ply.StarCoreMouseY = 0, 0
	local sens = math.Clamp(ply:GetInfoNum("starcore_mouse_sens", 1), 0.2, 3)
	h.stickX = math.Clamp((h.stickX or 0) + dx * 0.004 * sens, -1, 1)
	h.stickY = math.Clamp((h.stickY or 0) + dy * 0.003 * sens, -1, 1)
	if dx == 0 then h.stickX = approach(h.stickX, 0, dt * 2) end
	if dy == 0 then h.stickY = approach(h.stickY, 0, dt * 0.25) end
	-- low-pass so single mouse counts never show
	h.mouseTurn = Lerp(math.min(dt * 8, 1), h.mouseTurn or 0, -h.stickX)
	h.mousePitch = Lerp(math.min(dt * 4, 1), h.mousePitch or 0, h.stickY * MAX_PITCH)
	inp.turn = math.abs(h.mouseTurn) > 0.03 and h.mouseTurn or 0
	inp.pitch = h.mousePitch
	-- A/D slide sideways while the mouse turns the ship
	inp.strafe = (ply:KeyDown(IN_MOVERIGHT) and 1 or 0) - (ply:KeyDown(IN_MOVELEFT) and 1 or 0)
end

-- Wire flight (2026-11-14, owner via the SpaceGrid chat: "a gyro pod and compass, gps with vectors" - fly the core by wire
-- like SBEP's Gyro-Pod): the inputs Forward, Turn, Up, Strafe (-1..1), Pitch (-1..1, 1 = nose up, up to MAX_PITCH) and
-- Boost (non-zero) act like a pilot's keys - alone when no one sits in the pilot seat, added to the pilot's keys when
-- someone does. The helm must be on (input Hover) like for a pilot.
local WIRE_AXES = { { "Forward", "fwd" }, { "Turn", "turn" }, { "Up", "up" }, { "Strafe", "strafe" } }
local function wireValue(core, name)
	local i = core.Inputs and core.Inputs[name]
	local v = i and i.Value
	return isnumber(v) and math.Clamp(v, -1, 1) or 0
end
local function addWire(core, inp)
	if not core.Inputs then return end
	for _, a in ipairs(WIRE_AXES) do inp[a[2]] = math.Clamp((inp[a[2]] or 0) + wireValue(core, a[1]), -1, 1) end
	inp.pitch = math.Clamp((inp.pitch or 0) - wireValue(core, "Pitch") * MAX_PITCH, -MAX_PITCH, MAX_PITCH)
	if wireValue(core, "Boost") ~= 0 then inp.boost = true end
end

-- what the pilot presses (all zero without a pilot and without wire: the ship then just holds its place)
local function readInput(core)
	local seat = core.PilotSeat
	local ply = IsValid(seat) and seat:GetDriver()
	local inp = { fwd = 0, turn = 0, up = 0, boost = false, strafe = 0, pitch = 0 }
	if not IsValid(ply) or not StarCore.CanControl(core, ply) then
		if not (core.FTLData and core.FTLData.state == StarCore.FTL.JUMPING) then addWire(core, inp) end
		return inp, nil
	end
	ply.StarCorePilot = core
	if core.FTLData and core.FTLData.state == StarCore.FTL.JUMPING then return inp, ply end
	inp.fwd = (ply:KeyDown(IN_FORWARD) and 1 or 0) - (ply:KeyDown(IN_BACK) and 1 or 0)
	inp.up = (ply:KeyDown(IN_JUMP) and 1 or 0) - (ply:KeyDown(IN_DUCK) and 1 or 0)
	inp.boost = ply:KeyDown(IN_SPEED)
	if mouseSteer(ply) then
		readMouse(core, ply, inp)
	else
		inp.turn = (ply:KeyDown(IN_MOVELEFT) and 1 or 0) - (ply:KeyDown(IN_MOVERIGHT) and 1 or 0)
		-- mouse off (or Alt held): forget the stick, the nose goes back to level
		core.Helm.stickX, core.Helm.stickY, core.Helm.mouseTurn = 0, 0, 0
		core.Helm.mousePitch = approach(core.Helm.mousePitch or 0, 0, FrameTime() * 20)
		inp.pitch = core.Helm.mousePitch
		ply.StarCoreMouseX, ply.StarCoreMouseY = 0, 0
	end
	addWire(core, inp)
	return inp, ply
end
StarCore.ReadInput = readInput -- tests replace this to simulate a pilot

function StarCore.HelmThink(core)
	local h = core.Helm
	if not h or not h.on or core.Sleeping or core.TooBig or core.DockedTo or not core.LocalMins then return end
	-- in a Stargate's wormhole (Ascension Gates holds the whole ship until it comes out of the far gate): hands off
	local p1 = core.PhysParts and core.PhysParts[1]
	if core.AGPRideWith or (IsValid(p1) and p1.AGPRideWith) then return end
	local cp = core:GetPhysicsObject()
	if not IsValid(cp) then return end
	local s = core.Settings or Defaults
	local dt = FrameTime()
	local inp = StarCore.ReadInput(core)
	local active = inp.fwd ~= 0 or math.abs(inp.turn) > 0.15 or inp.up ~= 0 or (inp.strafe or 0) ~= 0
	if core.Autopilot then
		if active and not core.AutopilotInputs then
			StarCore.AutopilotSet(core, nil) -- the pilot takes over
		else
			inp = StarCore.AutopilotInput(core) or inp
			-- the autopilot may have just arrived (and parked the ship): only real movement counts as active
			active = inp.fwd ~= 0 or inp.turn ~= 0 or inp.up ~= 0
		end
	end

	-- parked: frozen until someone steers again
	if h.frozen then
		if not active then return end
		setFrozen(core, false)
	end

	local pivot = core:LocalToWorld((core.LocalMins + core.LocalMaxs) * 0.5)
	local shipAng = core:LocalToWorldAngles(h.refAng or Angle())
	local pitch = core.Autopilot and 0 or (inp.pitch or 0) -- nose angle from mouse steering (positive = nose down)
	-- lean into the turn like a helicopter (the more it turns, the more it banks; back to level when it flies straight)
	h.bank = Lerp(math.min(dt * 3, 1), h.bank or 0, core.Autopilot and 0 or -(inp.turn or 0) * MAX_BANK)
	local fwd = Angle(pitch, shipAng.y, 0):Forward()

	-- linear: measured velocity wins after a collision, otherwise the commanded one keeps it smooth
	h.vel = h.vel or Vector(0, 0, 0)
	-- velocity at the ship centre: remove the part that comes from turning (big ships turn fast at the edges)
	local wPrev = (h.angvel or Vector(0, 0, 0)) * (math.pi / 180)
	local meas = cp:GetVelocity() - wPrev:Cross(cp:LocalToWorld(cp:GetMassCenter()) - pivot)
	if (meas - h.vel):Length() > 300 then h.vel = meas end
	h.measSpeed = meas:Length()   -- (what the HUD shows: the ship's real speed, also when something holds it back)
	local maxSpeed = StarCore.CV.maxSpeed:GetFloat()
	local speed = math.min(s.speed * (inp.boost and s.boost or 1), maxSpeed)
	local want = fwd * speed * inp.fwd + Angle(0, shipAng.y, 0):Right() * speed * 0.6 * (inp.strafe or 0)
	local climb = math.min(s.climb, maxSpeed)
	if inp.fwd ~= 0 and math.abs(pitch) > 2 then
		-- flying along a pitched nose: climb/dive with it (Space/Ctrl still add on top)
		want.z = want.z + climb * inp.up
		h.targetZ = nil
	elseif inp.up ~= 0 then
		want.z = climb * inp.up
		h.targetZ = nil
	else
		if not h.targetZ then h.targetZ = pivot.z + h.vel.z * 0.25 end -- stop softly where the climb ends
		want.z = math.Clamp((h.targetZ - pivot.z) * 2, -climb, climb)
	end
	local acc = s.accel * dt
	h.vel = Vector(approach(h.vel.x, want.x, acc), approach(h.vel.y, want.y, acc), approach(h.vel.z, want.z, acc * 2))

	-- angular (degrees per second, world space): turn input + keep the ship level
	local yawRate = s.turn * inp.turn
	-- no turn input: the nose stays where the last turn ended (2026-11-18, owner: the ship turned a little on W / S);
	-- the heading is taken once the turn has run out, so letting go of a turn never swings it back
	if math.abs(inp.turn or 0) > 0.01 then
		h.holdYaw = nil
	elseif not h.holdYaw then
		if math.abs((h.angvel or vector_origin).z) < 2 then h.holdYaw = shipAng.y end
	else
		yawRate = math.Clamp(math.NormalizeAngle(h.holdYaw - shipAng.y) * 3, -20, 20)
	end
	local up = shipAng:Up()
	local wantUp = Angle(pitch, shipAng.y, h.bank):Up() -- level, or tilted to the mouse pitch and the bank
	local axis = up:Cross(wantUp)
	local sinA = axis:Length()
	local level = Vector(0, 0, 0)
	if sinA > 0.0001 then
		local angle = math.asin(math.min(sinA, 1))
		if up:Dot(wantUp) < 0 then angle = math.pi - angle end
		level = axis * (1 / sinA) * math.min(math.deg(angle) * 2, 60)
	end
	local wantW = Vector(level.x, level.y, yawRate + level.z)
	h.angvel = h.angvel or Vector(0, 0, 0)
	local step = 90 * dt
	h.angvel = Vector(approach(h.angvel.x, wantW.x, step * 2), approach(h.angvel.y, wantW.y, step * 2), approach(h.angvel.z, wantW.z, step))
	local wRad = h.angvel * (math.pi / 180)

	-- move every part like one rigid body. The parts of ships docked in this one are left to StarCore.DockThink, run
	-- right after for each of them: it keeps them on their place (2026-11-18: this loop also set them, without making
	-- up their small way off; when this core thought after the docked one, the docked ship slid off in a turn and was
	-- put back hard - it shook in 3 of 6 test runs)
	local docked = core:GetNWInt("starcore_docked_ships", 0) > 0 and StarCore.DockedShips and StarCore.DockedShips(core)
	local skip
	if docked and #docked > 0 then
		skip = {}
		for _, d in ipairs(docked) do
			for e in pairs(d.DockRel or {}) do skip[e] = true end
		end
	end
	for _, e in ipairs(core.PhysParts) do
		local p = IsValid(e) and e:GetPhysicsObject()
		if IsValid(p) and not (skip and skip[e]) then
			local r = p:LocalToWorld(p:GetMassCenter()) - pivot
			p:SetVelocity(h.vel + wRad:Cross(r))
			p:SetAngleVelocity(p:WorldToLocalVector(h.angvel))
			p:Wake()
		end
	end
	if skip then
		for _, d in ipairs(docked) do StarCore.DockThink(d) end
	end

	-- idle: freeze the parked ship to save server time
	if not active and h.vel:Length() < 5 and h.angvel:Length() < 1 then
		h.idle = (h.idle or 0) + dt
		if s.idleFreeze > 0 and h.idle > s.idleFreeze then setFrozen(core, true) end
	else
		h.idle = 0
	end

	-- HUD values, 5 times a second
	if (h.nextNW or 0) < CurTime() then
		h.nextNW = CurTime() + 0.2
		core:SetNWFloat("starcore_speed", h.measSpeed or h.vel:Length())   -- 2026-11-15: measured, not the commanded speed
		core:SetNWFloat("starcore_alt", StarCore.HeightOverGround(core))
	end
end

-- height of the ship's lowest point over the ground (or water) straight below it, in game units; -1 = no ground below
-- (space, over the sky). Owner 2026-11-15: "clearly over the ground and it tells me -330 m" - it showed the world's Z.
-- Only the map counts (world brushes, displacements, water), never props or the ship's own parts.
function StarCore.HeightOverGround(core)
	local mins, maxs = core.LocalMins, core.LocalMaxs
	local mid, bottom
	if mins and maxs then
		mid = core:LocalToWorld((mins + maxs) / 2)
		bottom = math.huge
		for i = 0, 7 do
			local c = Vector(bit.band(i, 1) > 0 and maxs.x or mins.x, bit.band(i, 2) > 0 and maxs.y or mins.y, bit.band(i, 4) > 0 and maxs.z or mins.z)
			bottom = math.min(bottom, core:LocalToWorld(c).z)
		end
	else
		mid, bottom = core:GetPos(), core:GetPos().z
	end
	local tr = util.TraceLine({ start = mid, endpos = mid - Vector(0, 0, 60000), mask = bit.bor(MASK_SOLID_BRUSHONLY, MASK_WATER) })
	if not tr.Hit or tr.HitSky or tr.StartSolid then return -1 end
	return math.max(0, bottom - tr.HitPos.z)
end

-- sitting down in the pilot seat starts the helm; R opens the menu
hook.Add("PlayerLeaveVehicle", "StarCore.MouseSteer", function(ply)
	ply.StarCorePilot, ply.StarCoreMouseX, ply.StarCoreMouseY = nil, 0, 0
end)

hook.Add("PlayerEnteredVehicle", "StarCore.Helm", function(ply, veh)
	for core in pairs(StarCore.Cores) do
		if IsValid(core) and core.PilotSeat == veh and StarCore.CanControl(core, ply) then
			-- docked in a bigger ship (sv_dock.lua): its helm stays off, the dock key lets go
			if core.DockedTo then StarCore.Notify(ply, "dock_docked_hint", NOTIFY_HINT, StarCore.ShipLabel(core.DockedTo)) return end
			if not core.Helm.on then StarCore.HelmSetOn(core, true) else StarCore.HelmRelock(core) end
			-- the keys hint only the first time per game (2026-11-17, owner: "first time ok, but not always when entering")
			if not ply.StarCorePilotHinted then ply.StarCorePilotHinted = true; StarCore.Notify(ply, "pilot_hint", NOTIFY_HINT) end
			return
		end
	end
end)

-- 2026-11-15 (owner: Ctrl is "down" and he loves it, but in the seat it also flipped first / third person): in a StarCore
-- pilot seat the game's own VehicleMove (Ctrl = view toggle, mouse wheel = camera distance) is replaced by the wheel part
-- alone. First / third person: the button in the menu's Helm tab (handlers.view). Other seats keep the game's behaviour.
hook.Add("VehicleMove", "StarCore.PilotNoDuckView", function(ply, veh, mv)
	if not IsValid(veh) then return end
	local core = veh:GetNWEntity("starcore")
	if not IsValid(core) or core.PilotSeat ~= veh then return end
	local wheel = ply:GetCurrentCommand():GetMouseWheel()
	if wheel ~= 0 and veh.SetCameraDistance then
		veh:SetCameraDistance(math.Clamp(veh:GetCameraDistance() - wheel * 0.03 * (1.1 + veh:GetCameraDistance()), -1, 10))
	end
	return true
end)

hook.Add("KeyPress", "StarCore.Menu", function(ply, key)
	if key ~= IN_RELOAD or not ply:InVehicle() then return end
	local veh = ply:GetVehicle()
	for core in pairs(StarCore.Cores) do
		if IsValid(core) and core.Seats and table.HasValue(core.Seats, veh) and StarCore.CanControl(core, ply) then
			StarCore.OpenMenu(ply, core)
			return
		end
	end
end)
