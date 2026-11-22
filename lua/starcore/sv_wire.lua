-- StarCore server, level 2 (Wiremod): Wire inputs/outputs on the core, for players who build their own panels.
-- Nothing here is needed to fly; a ship without wires works fully automatic.
-- (one name for one thing - the input "Park" is now "Freeze", like the menu button and the key)
local INPUTS = {
	"Hover", "Freeze", "Jump", "Jump Mark", "Jump Pos [VECTOR]", "Cancel Jump", "Fire", "Target [ENTITY]", "Next Target",
	"Shield", "Iris", "Dial [STRING]", "Close Gate", "Autopilot", "Autopilot Pos [VECTOR]",
	-- fly by wire like a Gyro-Pod (read by the helm, sv_helm.lua addWire)
	"Forward", "Turn", "Up", "Strafe", "Pitch", "Boost",
	-- (keys for tractor beam and cloak, "and wire of course"): Cloak 1/0; Tractor 1 = hold, 2 = pull in, 3 = push away, 0 =
	-- let go - it takes Tractor Entity when wired, else the radar target, else what is straight ahead of the ship
	"Cloak", "Tractor", "Tractor Entity [ENTITY]",
	-- (carriers): 1 = dock into the bigger ship this one is in, 0 = let go
	"Dock",
}
local OUTPUTS = {
	"Hover", "Speed", "Altitude", "FTL State", "Power %", "Shield Up", "Shield %", "Hull %", "Target [ENTITY]",
	"Target Pos [VECTOR]", "Contacts", "Hostiles", "Gate Open", "Iris Closed", "Autopilot",
	-- where the ship is
	"Position [VECTOR]", "Velocity [VECTOR]", "Angle [ANGLE]", "Heading", "Pitch", "Roll",
	-- 1 while the ship is frozen in place (input Freeze, the menu's / screen's Freeze button or the pilot's key) - for a lamp
	"Frozen",
	-- 1 while cloaked; what the tractor beam holds (NULL = nothing)
	"Cloaked", "Tractor [ENTITY]",
	-- 1 while docked in a bigger ship; how many ships are docked in this one
	"Docked", "Docked Ships",
}

function StarCore.WireSetup(core)
	if not WireLib then return end
	core.Inputs = WireLib.CreateInputs(core, INPUTS)
	core.Outputs = WireLib.CreateOutputs(core, OUTPUTS)
end

local function owner(core) return core:GetNWEntity("starcore_owner") end

function StarCore.WireInput(core, name, v)
	local ply = owner(core)
	local last = core.WireLast or {}
	core.WireLast = last
	local rising = isnumber(v) and v ~= 0 and (last[name] or 0) == 0
	last[name] = isnumber(v) and v or last[name]
	if name == "Hover" then StarCore.HelmSetOn(core, v ~= 0)
	elseif name == "Freeze" then if core.Helm and core.Helm.on then StarCore.SetFrozen(core, v ~= 0) end
	elseif name == "Jump" and rising then
		local pos = core.Inputs["Jump Pos"] and core.Inputs["Jump Pos"].Value
		local mark = core.Inputs["Jump Mark"] and core.Inputs["Jump Mark"].Value or 0
		local target
		if isvector(pos) and pos:LengthSqr() > 0 then target = { kind = "coord", pos = pos }
		elseif mark > 0 then target = { kind = "mark", index = math.floor(mark) } end
		if target then
			local ok, why = StarCore.RequestJump(core, ply, target)
			if not ok and IsValid(ply) then StarCore.Notify(ply, why, NOTIFY_ERROR) end
		end
	elseif name == "Cancel Jump" and rising then StarCore.CancelJump(core)
	elseif name == "Fire" then
		core.Engage = v ~= 0
		if not core.Engage then StarCore.StopWeapons(core) end
	elseif name == "Target" then
		if IsValid(v) and StarCore.ContactOf(core, v) then core.Target = v; core:SetNWEntity("starcore_target", v) end
	elseif name == "Next Target" and rising then StarCore.CycleTarget(core, 1)
	elseif name == "Shield" then StarCore.ShieldSet(core, v ~= 0)
	elseif name == "Iris" and StarCore.SG and StarCore.SG.Available() then StarCore.SG.SetIris(core, v ~= 0)
	elseif name == "Dial" and isstring(v) and v ~= "" and StarCore.SG and StarCore.SG.Available() then StarCore.SG.Dial(core, ply, v, "fast")
	elseif name == "Close Gate" and rising and StarCore.SG and StarCore.SG.Available() then StarCore.SG.Close(core)
	elseif name == "Cloak" then
		local ok, why = StarCore.CloakSet(core, v ~= 0)
		if not ok and IsValid(ply) then StarCore.Notify(ply, why, NOTIFY_ERROR) end
	elseif name == "Tractor" then
		if v == 0 then StarCore.TractorSet(core, nil)
		else
			local mode = v >= 3 and "push" or v >= 2 and "pull" or "hold"
			local held = core.Tractor and core.Tractor.ent
			if IsValid(held) then core.Tractor.mode = mode   -- (1 -> 2 or 3 while holding: pull it in / push it away)
			else
				local ent = core.Inputs["Tractor Entity"] and core.Inputs["Tractor Entity"].Value
				local why
				if not IsValid(ent) then ent = IsValid(core.Target) and core.Target or nil end
				if not IsValid(ent) then
					local ang = core:LocalToWorldAngles(core.Helm and core.Helm.refAng or Angle())
					ent, why = StarCore.TractorPick(core, StarCore.ShipCenter(core), ang:Forward())
				end
				local ok = false
				if IsValid(ent) then ok, why = StarCore.TractorSet(core, ent, mode) end
				if not ok and IsValid(ply) then StarCore.Notify(ply, why or "tractor_nothing", NOTIFY_ERROR) end
			end
		end
	elseif name == "Dock" and StarCore.Dock then
		if v ~= 0 and not core.DockedTo then
			local ok, why = StarCore.Dock(core, ply)
			if not ok and IsValid(ply) then StarCore.Notify(ply, why, NOTIFY_ERROR) end
		elseif v == 0 and core.DockedTo then StarCore.Undock(core) end
	elseif name == "Autopilot" and StarCore.AutopilotSet then
		local pos = core.Inputs["Autopilot Pos"] and core.Inputs["Autopilot Pos"].Value
		if v ~= 0 and isvector(pos) and pos:LengthSqr() > 0 then StarCore.AutopilotSet(core, pos) else StarCore.AutopilotSet(core, nil) end
	end
end

function StarCore.WireOutputs(core)
	if not WireLib or not core.Outputs then return end
	local now = CurTime()
	if now < (core.NextWireOut or 0) then return end
	core.NextWireOut = now + 0.25
	local hostiles = 0
	for _, c in ipairs(core.Contacts or {}) do if c.iff == StarCore.IFF.hostile then hostiles = hostiles + 1 end end
	local t = core.Target
	local hullMax = core:GetNWInt("starcore_hull_max")
	local out = {
		["Hover"] = core:GetNWBool("starcore_hover") and 1 or 0,
		["Frozen"] = core:GetNWBool("starcore_frozen") and 1 or 0,
		["Cloaked"] = core:GetNWBool("starcore_cloaked") and 1 or 0,
		["Tractor"] = IsValid(core:GetNWEntity("starcore_tractor")) and core:GetNWEntity("starcore_tractor") or NULL,
		["Speed"] = core:GetNWFloat("starcore_speed"),
		["Altitude"] = core:GetNWFloat("starcore_alt"),
		["FTL State"] = core:GetNWInt("starcore_ftl"),
		["Power %"] = core:GetNWFloat("starcore_power_pct", -1),
		["Shield Up"] = core:GetNWBool("starcore_shield_up") and 1 or 0,
		["Shield %"] = core:GetNWFloat("starcore_shield_strength", -1),
		["Hull %"] = hullMax > 0 and core:GetNWInt("starcore_hull") / hullMax * 100 or -1,
		["Target"] = IsValid(t) and t or NULL,
		["Target Pos"] = IsValid(t) and t:GetPos() or Vector(0, 0, 0),
		["Contacts"] = #(core.Contacts or {}),
		["Hostiles"] = hostiles,
		["Gate Open"] = core:GetNWBool("starcore_gate_open") and 1 or 0,
		["Iris Closed"] = core:GetNWBool("starcore_iris_closed") and 1 or 0,
		["Autopilot"] = core:GetNWBool("starcore_autopilot") and 1 or 0,
		["Docked"] = core.DockedTo and 1 or 0,
		["Docked Ships"] = core:GetNWInt("starcore_docked_ships"),
	}
	-- where the ship is: the core is welded to the hull; the ship's front is the helm's reference (the way W flies), not the
	-- core's own axes (the core can sit turned in the hull)
	local ph = core:GetPhysicsObject()
	local ang = core:LocalToWorldAngles(core.Helm and core.Helm.refAng or Angle())
	out["Position"] = core:GetPos()
	out["Velocity"] = IsValid(ph) and ph:GetVelocity() or core:GetVelocity()
	out["Angle"] = ang
	out["Heading"] = (90 - ang.y) % 360   -- compass: 0 = map north (+Y), 90 = east (+X)
	out["Pitch"] = -math.NormalizeAngle(ang.p)   -- positive = nose up
	out["Roll"] = math.NormalizeAngle(ang.r)
	for k, v in pairs(out) do
		local o = core.Outputs[k]
		if o and o.Value ~= v then WireLib.TriggerOutput(core, k, v) end
	end
end
