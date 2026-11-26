-- StarCore server: flight. The whole ship moves as one rigid body: every part gets the same motion each tick,
-- so welds are never stressed. Gravity is off while the helm is on; the ship holds its height and stays level.
local Defaults = StarCore.Defaults

local function approach(cur, target, step)
	if cur < target then return math.min(cur + step, target) end
	return math.max(cur - step, target)
end

-- How heavy a ship feels: 1 up to about 2000 units across, up to 3 for a very big one. A heavy ship tilts less far
-- and more slowly, and starts and stops its turns and climbs more softly.
--
local function heft(core)
	local sz = core:GetNWVector("starcore_size")
	return math.Clamp((sz and sz:Length() or 0) / 2000, 1, 3)
end
-- How soft its motion is: 0 up to 2000 units across (direct, as in the first release -, small ships like the first
-- release, big ones soft), 1 from 3000.
local function softness(core)
	local sz = core:GetNWVector("starcore_size")
	return math.Clamp(((sz and sz:Length() or 0) - 2000) / 1000, 0, 1)
end
-- Eased motion: a ramp at the most the ship may speed up (as before), then a soft blend onto it, so a turn or a
-- climb never starts or stops with a jolt (soft 1; with soft 0 it is the ramp alone). (Something else set the motion - a jump, a hit, parking: taken from there.)
local function ease(h, key, cur, want, step, dt, soft)
	local rk, ok = key .. "Ramp", key .. "Out"
	local r = h[rk]
	if not r or h[ok] ~= cur then r = cur end
	r = Vector(approach(r.x, want.x, step.x), approach(r.y, want.y, step.y), approach(r.z, want.z, step.z))
	h[rk] = r
	local out = LerpVector(Lerp(soft, 1, math.min(dt * 6, 1)), cur, r)
	h[ok] = out
	return out
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
-- which way is the ship's front
-- 1. the front the player set in the core's menu ("Set front: the way I look", core.FrontYaw, local to the core, duped),
-- 2. else the pilot seat's eye direction, 3. else the way the core itself points
function StarCore.FrontYaw(core)
	if isnumber(core.FrontYaw) then return core:LocalToWorldAngles(Angle(0, core.FrontYaw, 0)).y end
	return IsValid(core.PilotSeat) and seatYaw(core.PilotSeat) or core:GetAngles().y
end

-- while the helm flies, the game's air drag is off on every part. It pulled each part on its own, and the weld turned that
-- into a turn of the whole ship when the parts were not lined up (core 25 units beside the seat, 3.4 degrees). The helm
-- sets the speed itself; the drag comes back as it was when the helm lets go.
--
function StarCore.HelmDrag(e, p, on)
	if on then
		if e.StarCoreDrag == nil then e.StarCoreDrag = p:IsDragEnabled() end
		p:EnableDrag(false)
	elseif e.StarCoreDrag ~= nil then
		p:EnableDrag(e.StarCoreDrag)
		e.StarCoreDrag = nil
	end
end

-- The ship's level frame, from the ship itself and not from how it hangs right now (after free flight the ship stayed
-- "90 degrees tilted to its right, i cant bring it to normal", and W flew it sideways). It was taken as "the world's
-- level at the front's heading" each time someone sat down: sitting down in a tilted ship made the tilt its new
-- level. Now: the pilot seat's up is the ship's up (seats stand on the deck); a seat within 2 degrees of upright counts
-- as upright (the old way). No pilot seat: the frame it had, else the world's level.
local function shipFrame(core)
	local seat = core.PilotSeat
	local up
	if IsValid(seat) then
		up = seat:GetUp()
	elseif core.Helm.refAng then
		return core.Helm.refAng
	end
	if not up or up.z > 0.9994 then up = Vector(0, 0, 1) end
	local fwd
	if isnumber(core.FrontYaw) then
		fwd = core:LocalToWorldAngles(Angle(0, core.FrontYaw, 0)):Forward()
	elseif IsValid(seat) then
		local id = seat:LookupAttachment("vehicle_driver_eyes")
		local a = id and id > 0 and seat:GetAttachment(id)
		fwd = a and a.Ang:Forward() or seat:GetRight()
	else
		fwd = core:GetForward()
	end
	fwd = fwd - up * fwd:Dot(up)
	if fwd:LengthSqr() < 0.0001 then fwd = up:Angle():Up() end
	fwd:Normalize()
	return core:WorldToLocalAngles(fwd:AngleEx(up))
end
StarCore.ShipFrame = shipFrame

function StarCore.HelmRelock(core)
	core.Helm.refAng = shipFrame(core)
	core.Helm.freeLocal = nil
	core.Helm.freeOff = nil
	core.Helm.holdYaw = nil
	core.Helm.mouseOff, core.Helm.mousePitchWant, core.Helm.mousePitch = nil, nil, 0
	core.Helm.stickX, core.Helm.stickY, core.Helm.mouseTurn = 0, 0, 0
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
local function freeFlight(ply)
	return ply:GetInfoNum("starcore_free_flight", 0) == 1
end
local function directFlight(ply)
	return ply:GetInfoNum("starcore_direct_flight", 0) == 1 and not freeFlight(ply)
end
local function mouseSteer(ply)
	return (ply:GetInfoNum("starcore_mouse_steer", 0) == 1 or freeFlight(ply) or directFlight(ply)) and ply:GetInfoNum("starcore_looking", 0) == 0
end
hook.Add("StartCommand", "StarCore.MouseSteer", function(ply, cmd)
	if not ply:InVehicle() or not ply.StarCorePilot then return end
	ply.StarCoreMouseX = math.Clamp((ply.StarCoreMouseX or 0) + cmd:GetMouseX(), -1000, 1000)
	ply.StarCoreMouseY = math.Clamp((ply.StarCoreMouseY or 0) + cmd:GetMouseY(), -1000, 1000)
end)

-- Classic, the default: the first release's stick. X is a turn rate that springs back when the mouse rests, Y holds a
-- nose angle that drifts back to level slowly. Both are clamped and filtered, so the ship never jitters. Ships up to
-- 2000 units across fly with the first release's numbers, bigger ones softer (softness, heft).
--
local function readMouseClassic(core, ply, inp)
	local h = core.Helm
	local dt = FrameTime()
	local dx, dy = ply.StarCoreMouseX or 0, ply.StarCoreMouseY or 0
	ply.StarCoreMouseX, ply.StarCoreMouseY = 0, 0
	local sens = math.Clamp(ply:GetInfoNum("starcore_mouse_sens", 1), 0.2, 3)
	h.mouseOff, h.mousePitchWant = nil, nil
	h.stickX = math.Clamp((h.stickX or 0) + dx * 0.004 * sens, -1, 1)
	h.stickY = math.Clamp((h.stickY or 0) + dy * 0.003 * sens, -1, 1)
	if dx == 0 then h.stickX = approach(h.stickX, 0, dt * 2) end
	if dy == 0 then h.stickY = approach(h.stickY, 0, dt * 0.25) end
	-- low-pass so single mouse counts never show
	h.mouseTurn = Lerp(math.min(dt * 8, 1), h.mouseTurn or 0, -h.stickX)
	h.mousePitch = Lerp(math.min(dt * 4, 1), h.mousePitch or 0, h.stickY * 30)
	inp.turn = math.abs(h.mouseTurn) > 0.03 and h.mouseTurn or 0
	inp.pitch = h.mousePitch
	-- A/D slide sideways while the mouse turns the ship
	inp.strafe = (ply:KeyDown(IN_MOVERIGHT) and 1 or 0) - (ply:KeyDown(IN_MOVELEFT) and 1 or 0)
end

-- Free flight (starcore_direct_flight): the mouse steers 1:1. It was a stick: X a turn rate that ran out slowly, Y a nose angle that drifted back to
-- level. Now X moves a point the nose turns to and stops at, Y sets the nose's angle, and it stays where the mouse
-- left it. A small ship follows at once, a big one softly and slowly (softness, heft).
--
local MAX_PITCH = 30
local MOUSE_PITCH = 60   -- (how far the mouse takes a small ship's nose up or down)
local DEG_COUNT = 0.044  -- degrees a mouse count, at sensitivity 1
local MAX_BANK = 22
local function readMouse(core, ply, inp)
	local h = core.Helm
	local dt = FrameTime()
	local dx, dy = ply.StarCoreMouseX or 0, ply.StarCoreMouseY or 0
	ply.StarCoreMouseX, ply.StarCoreMouseY = 0, 0
	local sens = math.Clamp(ply:GetInfoNum("starcore_mouse_sens", 1), 0.2, 3)
	local soft, s = softness(core), core.Settings or Defaults
	-- left / right: what is left to turn (what the ship turned since is done), and the fastest turn that still stops there
	h.mouseOff = math.Clamp((h.mouseOff or 0) - (h.angvel or vector_origin).z * dt - dx * DEG_COUNT * sens, -90, 90)
	local acc, lag = Lerp(soft, 360, 90) * 0.8, soft / 6
	local a, rate = math.abs(h.mouseOff), 0
	if a >= 0.05 then
		rate = math.min(a * Lerp(soft, 8, 4), acc * (math.sqrt(lag * lag + 2 * a / acc) - lag), s.turn * Lerp(soft, 2.5, 1))
		if h.mouseOff < 0 then rate = -rate end
	end
	inp.mouse, inp.mouseYaw, inp.mouseMoved = true, rate, dx ~= 0 or dy ~= 0
	-- up / down
	local most = Lerp(soft, MOUSE_PITCH, MAX_PITCH)
	h.mousePitchWant = math.Clamp((h.mousePitchWant or h.mousePitch or 0) + dy * DEG_COUNT * sens, -most, most)
	h.mousePitch = Lerp(math.min(dt * Lerp(soft, 25, 4), 1), h.mousePitch or 0, h.mousePitchWant)
	inp.turn = 0
	inp.pitch = h.mousePitch
	-- A/D slide sideways while the mouse turns the ship
	inp.strafe = (ply:KeyDown(IN_MOVERIGHT) and 1 or 0) - (ply:KeyDown(IN_MOVELEFT) and 1 or 0)
end

-- free flight (starcore_free_flight): the mouse gives turn rates about the ship's own axes - X turns the nose left /
-- right, Y up / down - that spring back when the mouse rests; A/D roll. Nothing holds the ship level.
local FREE_PITCH, FREE_ROLL = 1.6, 2.5   -- (times the ship's turn rate)
local function readMouseFree(core, ply, inp)
	local h = core.Helm
	local dt = FrameTime()
	local dx, dy = ply.StarCoreMouseX or 0, ply.StarCoreMouseY or 0
	ply.StarCoreMouseX, ply.StarCoreMouseY = 0, 0
	local sens = math.Clamp(ply:GetInfoNum("starcore_mouse_sens", 1), 0.2, 3)
	-- The nose follows the mouse (free flight is "not really locked to the mouse ... i slowly lean forward ... and
	-- its not smoothly linked to my mouse feeling ... there is a tipping point were its keeping to much"). The mouse
	-- was a stick: it gave a turn speed that ran out slowly after the mouse stopped, so the nose went on past where the
	-- mouse had stopped. Now the mouse moves a point the nose goes to (as far as the mouse moved, like the game's own
	-- view, about 0.022 degrees a count), and the ship turns there and stops there: quick while far, slower near it,
	-- never past it. Mouse down = nose down, as in level flight.
	local o = h.freeOff or { y = 0, p = 0 }
	h.freeOff = o
	local sa = core:LocalToWorldAngles(h.refAng or Angle())
	local w = h.angvel or vector_origin
	local k = 0.022 * sens * 2
	o.y = math.Clamp(o.y - w:Dot(sa:Up()) * dt - dx * k, -90, 90)   -- (what the ship turned since: done)
	o.p = math.Clamp(o.p - w:Dot(sa:Right()) * dt - dy * k, -90, 90)
	local s = core.Settings or Defaults
	local hf = heft(core)
	local acc = 120 / hf * 0.8   -- (HelmFree's turn speed-up, with room to spare: it stops in time)
	local lag = 1 / 6            -- (and its soft blend: the turn follows about a sixth of a second late)
	local function rateFor(off, most)
		local a = math.abs(off)
		if a < 0.05 then return 0 end
		-- the fastest turn that still stops on the point: what it turns during the lag plus while slowing down fits
		local r = math.min(a * 4, acc * (math.sqrt(lag * lag + 2 * a / acc) - lag), most)
		return off > 0 and r or -r
	end
	local yawMost, pitchMost = s.turn, s.turn * FREE_PITCH / hf
	inp.free = true
	h.mouseOff, h.mousePitchWant, h.mousePitch = nil, nil, 0   -- (the level flight's mouse point: afresh next time)
	inp.yawRate = rateFor(o.y, yawMost) / s.turn
	inp.pitchRate = rateFor(o.p, pitchMost) / pitchMost
	inp.roll = (ply:KeyDown(IN_MOVERIGHT) and 1 or 0) - (ply:KeyDown(IN_MOVELEFT) and 1 or 0)
	inp.turn, inp.strafe, inp.pitch = 0, 0, 0
end

-- Wire flight (fly the core by wire like SBEP's Gyro-Pod): the inputs Forward, Turn, Up, Strafe (-1..1), Pitch (-1..1, 1 =
-- nose up, up to MAX_PITCH) and Boost (non-zero) act like a pilot's keys - alone when no one sits in the pilot seat,
-- added to the pilot's keys when someone does. The helm must be on (input Hover) like for a pilot.
--
local WIRE_AXES = { { "Forward", "fwd" }, { "Turn", "turn" }, { "Up", "up" }, { "Strafe", "strafe" } }
local function wireValue(core, name)
	local i = core.Inputs and core.Inputs[name]
	local v = i and i.Value
	return isnumber(v) and math.Clamp(v, -1, 1) or 0
end
local function addWire(core, inp)
	if not core.Inputs then return end
	for _, a in ipairs(WIRE_AXES) do inp[a[2]] = math.Clamp((inp[a[2]] or 0) + wireValue(core, a[1]), -1, 1) end
	local wp = wireValue(core, "Pitch")
	if wp ~= 0 then inp.pitch = math.Clamp((inp.pitch or 0) - wp * MAX_PITCH, -MAX_PITCH, MAX_PITCH) end
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
	if not (mouseSteer(ply) and freeFlight(ply)) then core.Helm.freeOff = nil end   -- (free flight's mouse point: afresh next time)
	if mouseSteer(ply) and freeFlight(ply) then
		readMouseFree(core, ply, inp)
	elseif mouseSteer(ply) and directFlight(ply) then
		core.Helm.stickX, core.Helm.stickY, core.Helm.mouseTurn = 0, 0, 0
		readMouse(core, ply, inp)
	elseif mouseSteer(ply) then
		readMouseClassic(core, ply, inp)
	elseif directFlight(ply) and ply:GetInfoNum("starcore_looking", 0) == 1 then
		-- (looking around with ALT: the nose stays where it is)
		inp.pitch = core.Helm.mousePitch or 0
		core.Helm.mouseOff = nil
		ply.StarCoreMouseX, ply.StarCoreMouseY = 0, 0
	else
		inp.turn = (ply:KeyDown(IN_MOVELEFT) and 1 or 0) - (ply:KeyDown(IN_MOVERIGHT) and 1 or 0)
		-- mouse off: the nose goes back to level
		core.Helm.mouseOff, core.Helm.mousePitchWant = nil, nil
		core.Helm.stickX, core.Helm.stickY, core.Helm.mouseTurn = 0, 0, 0
		core.Helm.mousePitch = approach(core.Helm.mousePitch or 0, 0, FrameTime() * 20)
		inp.pitch = core.Helm.mousePitch
		ply.StarCoreMouseX, ply.StarCoreMouseY = 0, 0
	end
	addWire(core, inp)
	return inp, ply
end
StarCore.ReadInput = readInput -- tests replace this to simulate a pilot

-- Through a Stargate: the far gate turns the ship, but the helm went on with the speed and the heading it had before
-- - the ship flew backwards into the gate or sideways into whatever stood there. The ship's speed is kept as forward /
-- right / up of the ship and goes on in the new direction; heading, height and the mouse's point are taken anew.
--
local function rideOut(core, h)
	local r = h.ride
	h.ride = nil
	local lv = WorldToLocal(r.vel, angle_zero, vector_origin, r.ang)
	h.vel = LocalToWorld(lv, angle_zero, vector_origin, core:GetAngles())
	h.angvel = Vector(0, 0, 0)
	h.velRamp, h.velOut, h.angRamp, h.angOut = nil, nil, nil, nil
	h.holdYaw, h.targetZ, h.mouseOff, h.freeOff, h.freeAdopt = nil, nil, nil, nil, nil
	h.stickX, h.mouseTurn = 0, 0
	h.rideTill = CurTime() + 0.3   -- (the gate's own push on the parts is no hit)
end
hook.Add("StarGate.Teleport", "StarCore.HelmRide", function(e, _, attached)
	local core = StarCore.PartCore and StarCore.PartCore[e]
	if not IsValid(core) and istable(attached) then
		for _, v in ipairs(attached.Attached or {}) do
			core = IsValid(v) and (v:GetClass() == "starcore" and v or StarCore.PartCore[v]) or core
			if IsValid(core) then break end
		end
	end
	local h = IsValid(core) and core.Helm
	if h and h.on then h.ride = { ang = core:GetAngles(), vel = Vector(h.vel or vector_origin) } end
end)

function StarCore.HelmThink(core)
	local h = core.Helm
	if not h or not h.on or core.Sleeping or core.TooBig or core.DockedTo or not core.LocalMins then return end
	-- in a Stargate's wormhole (Ascension Gates holds the whole ship until it comes out of the far gate): hands off
	local p1 = core.PhysParts and core.PhysParts[1]
	if core.AGPRideWith or (IsValid(p1) and p1.AGPRideWith) then return end
	if h.ride then rideOut(core, h) end
	local cp = core:GetPhysicsObject()
	if not IsValid(cp) then return end
	local s = core.Settings or Defaults
	local dt = FrameTime()
	local inp = StarCore.ReadInput(core)
	local active = inp.fwd ~= 0 or math.abs(inp.turn) > 0.15 or inp.up ~= 0 or (inp.strafe or 0) ~= 0
		or (inp.free and (inp.yawRate ~= 0 or inp.pitchRate ~= 0 or inp.roll ~= 0))
		or (inp.mouse and (inp.mouseMoved or math.abs(inp.mouseYaw) > 1))
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
	if inp.free and not core.Autopilot then
		StarCore.HelmFree(core, h, s, inp, shipAng, pivot, cp, dt)
		return StarCore.HelmMove(core, h, s, active, dt)
	end
	local hf = heft(core)
	-- nose angle from mouse steering (positive = nose down); a heavy ship's nose goes less far (30 degrees at most for a
	-- small one, 12 for the biggest)
	local pitch = core.Autopilot and 0 or (inp.pitch or 0) * (1 - (hf - 1) * 0.3)
	-- lean into the turn like a helicopter (the more it turns, the more it banks; back to level when it flies straight).
	-- The lean followed every small left-right correction of the mouse, so steering along rocked the ship from
	-- side to side. It now follows the turn held for a while (a short correction hardly leans), and a heavy ship leans
	-- less.
	h.turnHeld = Lerp(math.min(dt * 1.2, 1), h.turnHeld or 0, core.Autopilot and 0 or math.Clamp((inp.turn or 0) + (inp.mouseYaw or 0) / math.max(s.turn, 1), -1, 1))
	-- (classic: at once, as in the first release)
	local lean = inp.mouse and -h.turnHeld or -(core.Autopilot and 0 or math.Clamp(inp.turn or 0, -1, 1))
	h.bank = Lerp(math.min(dt * (inp.mouse and 2 or 3), 1), h.bank or 0, lean * MAX_BANK / hf)
	local fwd = Angle(pitch, shipAng.y, 0):Forward()

	-- linear: measured velocity wins after a collision, otherwise the commanded one keeps it smooth
	h.vel = h.vel or Vector(0, 0, 0)
	-- velocity at the ship centre: remove the part that comes from turning (big ships turn fast at the edges)
	local wPrev = (h.angvel or Vector(0, 0, 0)) * (math.pi / 180)
	local meas = cp:GetVelocity() - wPrev:Cross(cp:LocalToWorld(cp:GetMassCenter()) - pivot)
	if (meas - h.vel):Length() > 300 and (h.rideTill or 0) < CurTime() then
		-- (the author's play test: a ship that flew into a wall or the map's edge bounced off "like a ping-pong ball",
		-- faster each time. The speed after the hit was taken as the ship's new speed, and a hit that pushed the ship
		-- out of the wall at more than its own speed made it faster.) A hit never makes the ship faster: it goes on the
		-- way the hit sent it, at half the speed it had at most.
		local ms, hs = meas:Length(), h.vel:Length()
		if ms > hs * 0.5 then meas = meas * (hs * 0.5 / math.max(ms, 0.001)) end
		h.vel = meas
	end
	h.measSpeed = meas:Length()   -- (what the HUD shows: the ship's real speed, also when something holds it back)
	local maxSpeed = StarCore.CV.maxSpeed:GetFloat()
	local speed = math.min(s.speed * (inp.boost and s.boost or 1), maxSpeed)
	local want = fwd * speed * inp.fwd + Angle(0, shipAng.y, 0):Right() * speed * 0.6 * (inp.strafe or 0)
	local climb = math.min(s.climb, maxSpeed)
	-- (classic: from 2 degrees on, as in the first release; 1:1 from 0.3 on - its nose stays, so at 2 it would bob)
	if inp.fwd ~= 0 and math.abs(pitch) > (inp.mouse and 0.3 or 2) then
		-- flying along a pitched nose: climb/dive with it (Space/Ctrl still add on top)
		want.z = want.z + climb * inp.up
		h.targetZ = nil
	elseif inp.up ~= 0 then
		want.z = climb * inp.up
		h.targetZ = nil
	else
		if not h.targetZ then h.targetZ = pivot.z + h.vel.z * 0.25 end -- stop softly where the climb ends
		-- (test rcpilot: landed with Ctrl, the height where the descent would have ended lay under the ground - the helm
		-- pressed the ship into it for good, 95 units a second: it ground and spun on the spot. A height it is held off for
		-- half a second is taken as reached.)
		if math.abs(h.targetZ - pivot.z) > 4 and math.abs(meas.z) < 10 then
			h.zStuck = (h.zStuck or 0) + dt
			if h.zStuck > 0.5 then h.targetZ, h.zStuck = pivot.z, 0 end
		else
			h.zStuck = 0
		end
		want.z = math.Clamp((h.targetZ - pivot.z) * 2, -climb, climb)
	end
	local acc = s.accel * dt
	local soft = softness(core)
	h.vel = ease(h, "vel", h.vel, want, Vector(acc, acc, acc * 2 / hf), dt, soft)

	-- angular (degrees per second, world space): turn input + keep the ship level
	local yawRate = s.turn * inp.turn + (inp.mouseYaw or 0)
	-- no turn input: the nose stays where the last turn ended (the ship turned a little on W / S); the heading is
	-- taken once the turn has run out, so letting go of a turn never swings it back
	if math.abs(inp.turn or 0) > 0.01 or (inp.mouseYaw or 0) ~= 0 then
		h.holdYaw, h.yawWatch = nil, nil
	elseif not h.holdYaw then
		if math.abs((h.angvel or vector_origin).z) < 2 then h.holdYaw = shipAng.y end
	else
		-- (test rcpilot: a landing that knocked the nose a few degrees round, with the ground holding it there - the helm
		-- turned at full rate against the ground for good: the landed ship ground on the spot and shoved its welded parts 4
		-- units off. A heading it cannot get back to within 0.75 s is taken as the new one.)
		local off = math.abs(math.NormalizeAngle(h.holdYaw - shipAng.y))
		if off > 3 then
			local now = CurTime()
			if not h.yawWatch then h.yawWatch = { off = off, t = now }
			elseif now - h.yawWatch.t > 0.75 then
				-- (not closer than before: held, or pushed the other way)
				if off > h.yawWatch.off - 1.5 then h.holdYaw = shipAng.y end
				h.yawWatch = nil
			end
		else
			h.yawWatch = nil
		end
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
		-- (with the mouse a small ship's nose goes there at once)
		level = axis * (1 / sinA) * math.min(math.deg(angle) * (inp.mouse and Lerp(soft, 6, 2) or 2), inp.mouse and Lerp(soft, 120, 60 / hf) or 60 / hf)
	end
	local wantW = Vector(level.x, level.y, yawRate + level.z)
	h.angvel = h.angvel or Vector(0, 0, 0)
	local step = 90 * dt
	h.angvel = ease(h, "ang", h.angvel, wantW, inp.mouse and Vector(Lerp(soft, 600, 180 / hf) * dt, Lerp(soft, 600, 180 / hf) * dt, Lerp(soft, 360, 90) * dt)
		or Vector(step * 2 / hf, step * 2 / hf, step), dt, soft)
	return StarCore.HelmMove(core, h, s, active, dt)
end

-- free flight (readMouseFree): speed along the ship's own nose and up, turn rates about its own axes, no levelling
function StarCore.HelmFree(core, h, s, inp, shipAng, pivot, cp, dt)
	h.vel = h.vel or Vector(0, 0, 0)
	local wPrev = (h.angvel or Vector(0, 0, 0)) * (math.pi / 180)
	local meas = cp:GetVelocity() - wPrev:Cross(cp:LocalToWorld(cp:GetMassCenter()) - pivot)
	if (meas - h.vel):Length() > 300 and (h.rideTill or 0) < CurTime() then
		local ms, hs = meas:Length(), h.vel:Length()
		if ms > hs * 0.5 then meas = meas * (hs * 0.5 / math.max(ms, 0.001)) end   -- (a hit never makes it faster)
		h.vel = meas
	end
	h.measSpeed = meas:Length()
	local maxSpeed = StarCore.CV.maxSpeed:GetFloat()
	local speed = math.min(s.speed * (inp.boost and s.boost or 1), maxSpeed)
	local F, R, U = shipAng:Forward(), shipAng:Right(), shipAng:Up()
	h.targetZ, h.holdYaw, h.bank, h.turnHeld = nil, nil, 0, 0
	-- the speed turns with the ship: kept as forward / right / up of the ship, so after a turn the ship flies where its
	-- nose points, not on the old way
	local l = h.freeLocal
	if not l or h.freeAdopt ~= h.vel then l = Vector(h.vel:Dot(F), h.vel:Dot(R), h.vel:Dot(U)) end
	local acc = s.accel * dt
	l = Vector(approach(l.x, speed * inp.fwd, acc), approach(l.y, 0, acc), approach(l.z, math.min(s.climb, maxSpeed) * inp.up, acc))
	h.freeLocal = l
	h.vel = F * l.x + R * l.y + U * l.z
	h.freeAdopt = h.vel
	-- (an angular velocity in the world: about the ship's up = nose left, its right = nose up, its front = roll right)
	-- (a heavy ship pitches and rolls slower and starts and stops its turns softly: heft, ease -)
	--
	local hf = heft(core)
	local rate = s.turn
	local wantW = U * (inp.yawRate * rate) + R * (inp.pitchRate * rate * FREE_PITCH / hf) + F * (inp.roll * rate * FREE_ROLL / hf)
	h.angvel = h.angvel or Vector(0, 0, 0)
	local step = 120 * dt / hf
	h.angvel = ease(h, "ang", h.angvel, wantW, Vector(step, step, step), dt, 1)   -- (the mouse point's stopping counts on the blend)
end

-- the motion of the tick (h.vel, h.angvel) goes onto every part; the parked ship freezes; the HUD values
function StarCore.HelmMove(core, h, s, active, dt)
	local pivot = core:LocalToWorld((core.LocalMins + core.LocalMaxs) * 0.5)
	local wRad = h.angvel * (math.pi / 180)

	-- move every part like one rigid body. The parts of ships docked in this one are left to StarCore.DockThink, run
	-- right after for each of them: it keeps them on their place (this loop also set them, without making up their
	-- small way off; when this core thought after the docked one, the docked ship slid off in a turn and was put back
	-- hard - it shook in 3 of 6 test runs)
	local docked = core:GetNWInt("starcore_docked_ships", 0) > 0 and StarCore.DockedShips and StarCore.DockedShips(core)
	local skip
	if docked and #docked > 0 then
		skip = {}
		for _, d in ipairs(docked) do
			for e in pairs(d.DockRel or {}) do skip[e] = true end
		end
	end
	-- (a part pushed off its place - the deck set down on the ground while the rest still goes down: welded walls stood 4 units
	-- off for good, the same motion every tick left the welds no way to pull them back; rcpilot. A part held only by welds goes
	-- back to where it was against the core when the helm took over)
	local rest = core.PartRest
	if not rest then
		rest = {}
		for _, e in ipairs(core.PhysParts) do
			-- (only a ship of welded props whose core is welded in, not parented: a SpaceGrid keel is moved by its own code)
			local ok, welds = IsValid(e) and e ~= core and not IsValid(core:GetParent()), 0
			if ok then
				for _, c in pairs(constraint.GetTable(e) or {}) do
					if c.Type == "Weld" then welds = welds + 1 elseif c.Type ~= "NoCollide" then ok = false break end
				end
			end
			ok = ok and welds > 0
			if ok then rest[e] = core:WorldToLocal(e:GetPos()) end
		end
		core.PartRest = rest
	end
	-- (the shape, not the core's place: the deck on the ground stops while the core, welded on it, sinks a few units with the rest -
	-- each part goes back by its own way off less the way off of all of them, the core counted as 0)
	local offs, sum, n = {}, Vector(0, 0, 0), 1
	if dt > 0 and h.angvel:LengthSqr() < 10 * 10 then
		for e, lp in pairs(rest) do
			if IsValid(e) then
				local off = core:LocalToWorld(lp) - e:GetPos()
				offs[e] = off
				sum:Add(off)
				n = n + 1
			end
		end
	end
	local mean = sum / n
	for _, e in ipairs(core.PhysParts) do
		local p = IsValid(e) and e:GetPhysicsObject()
		if IsValid(p) and not (skip and skip[e]) then
			local r = p:LocalToWorld(p:GetMassCenter()) - pivot
			local back = vector_origin
			-- (not while it turns fast, and only what is clearly off: with every small way off pulled back in a pitch, the nose
			-- never came up - Wire Pitch)
			local off = offs[e] and offs[e] - mean or e == core and n > 1 and -mean or nil
			if off then
				local d = off:LengthSqr()
				if d > 1 and d < 40 * 40 then back = off * math.min(0.5 / dt, 300 / math.sqrt(d)) end
			end
			p:SetVelocity(h.vel + wRad:Cross(r) + back)
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
		core:SetNWFloat("starcore_speed", h.measSpeed or h.vel:Length())   -- measured, not the commanded speed
		core:SetNWFloat("starcore_alt", StarCore.HeightOverGround(core))
	end
end

-- height of the ship's lowest point over the ground (or water) straight below it, in game units; -1 = no ground below
-- (space, over the sky). - it showed the world's Z. Only the map counts (world brushes, displacements, water), never
-- props or the ship's own parts.
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

-- Getting up from a seat of a ship. The game's own way out of a seat is a fixed spot beside it, else anywhere free - on
-- a ship that can be outside, through a window. So: the free spot nearest the seat on the same deck, that the seat
-- can "see" (nothing solid between - no wall, no window), with room for a standing player. `extra` = spots to try
-- first (world), `inside(pos)` = optional test that the spot lies in the ship. Returns a position, or nil.
--
--
local BOX_MIN, BOX_MAX = Vector(-16, -16, 0), Vector(16, 16, 72)
function StarCore.SeatExitSpot(veh, ply, extra, inside)
	local up = Vector(0, 0, 1)
	local seatAt = veh:GetPos()
	-- (the seat's own up, not the world's: in a tilted or rolled ship - free flight - the world's up from the seat can
	-- be in the deck or a console, a player got up in a rolled ship and stuck in the console and floor)
	local sUp = veh:GetUp()
	local eye = seatAt + sUp * 30
	local function boxFree(at)
		if inside and not inside(at) then return false end
		local tr = util.TraceHull({ start = at, endpos = at, mins = BOX_MIN, maxs = BOX_MAX, filter = { ply, veh }, mask = MASK_PLAYERSOLID })
		return not (tr.StartSolid or tr.Hit)
	end
	local function free(at)
		if not boxFree(at) then return false end
		-- (the seat sees it: no wall or window between)
		local l = util.TraceLine({ start = eye, endpos = at + up * 36, filter = { ply, veh }, mask = MASK_PLAYERSOLID })
		return not l.Hit
	end
	for _, at in ipairs(extra or {}) do
		if free(at) then return at end
	end
	-- rings round the seat in its deck's plane; each spot set onto whatever is below it in the world (a seat on a
	-- dais: the floor a little lower; a rolled ship: its wall) - nothing below: the spot in the room's air
	local f = veh:GetRight()   -- (a seat's front is its right in the game)
	f = f - sUp * f:Dot(sUp)
	if f:LengthSqr() < 0.01 then f = sUp:Angle():Up() end
	f:Normalize()
	local side = f:Cross(sUp)
	local function ring(radii, test)
		for _, r in ipairs(radii) do
			for i = 0, 15 do
				local t = math.rad(i * 22.5)
				local c = seatAt + sUp * 20 + (f * math.cos(t) + side * math.sin(t)) * r
				local d = util.TraceLine({ start = c + up * 40, endpos = c - up * 90, filter = { ply, veh }, mask = MASK_PLAYERSOLID })
				local at = (d.Hit and not d.StartSolid) and (d.HitPos + up * 2) or (not d.StartSolid and c - up * 36) or nil
				if at and test(at) then return at end
			end
		end
	end
	return ring({ 36, 48, 64, 80, 100 }, free)
		-- (nothing in sight of the seat: any free spot near it inside the ship - never stuck in something)
		or ring({ 36, 64, 100, 140, 190 }, boxFree)
end

-- a ship seat that is not a SpaceGrid seat (those have their own spots first: SpaceGrid sv_doors.lua)
hook.Add("PlayerLeaveVehicle", "StarCore.SeatExit", function(ply, veh)
	if not IsValid(veh) or veh.SpaceGridSeat then return end
	local core = StarCore.PartCore and StarCore.PartCore[veh]
	if not IsValid(core) then return end
	local inside = function(at) return StarCore.IsInside(core, { GetPos = function() return at end }) end
	local at = StarCore.SeatExitSpot(veh, ply, nil, inside)
	if not at then return end
	StarCore.PutOutOfSeat(ply, core, at)
end)
-- put a player who got up on his spot in the ship, and again a tick later (the engine may set its own spot after the
-- hook; a flying ship has moved on by then: the spot goes with it), with the ship's speed
function StarCore.PutOutOfSeat(ply, ship, at)
	ply:SetPos(at)
	local lp = ship:WorldToLocal(at)
	local function speed()
		local p = ship:GetPhysicsObject()
		local body = ship.SGKeel or ship
		local bp = IsValid(body) and body:GetPhysicsObject()
		if IsValid(bp) then p = bp end
		if IsValid(p) and p:IsMotionEnabled() then ply:SetVelocity(p:GetVelocity() - ply:GetVelocity()) end
	end
	speed()
	timer.Simple(0, function()
		if not (IsValid(ply) and IsValid(ship)) or ply:InVehicle() then return end
		ply:SetPos(ship:LocalToWorld(lp))
		speed()
	end)
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
			-- the keys hint only the first time per game
			if not ply.StarCorePilotHinted then ply.StarCorePilotHinted = true; StarCore.Notify(ply, "pilot_hint", NOTIFY_HINT) end
			return
		end
	end
end)

-- (Ctrl is "down" and he loves it, but in the seat it also flipped first / third person): in a StarCore pilot seat the
-- game's own VehicleMove (Ctrl = view toggle, mouse wheel = camera distance) is replaced by the wheel part alone. First /
-- third person: the button in the menu's Helm tab (handlers.view). Other seats keep the game's behaviour.
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
