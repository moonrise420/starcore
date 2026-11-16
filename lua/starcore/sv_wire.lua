-- StarCore server, level 2 (Wiremod): Wire inputs/outputs on the core, for players who build their own panels.
-- Nothing here is needed to fly; a ship without wires works fully automatic.
local INPUTS = {
	"Hover", "Park", "Jump", "Jump Mark", "Jump Pos [VECTOR]", "Cancel Jump", "Fire", "Target [ENTITY]", "Next Target",
	"Shield", "Iris", "Dial [STRING]", "Close Gate", "Autopilot", "Autopilot Pos [VECTOR]",
	-- 2026-11-14: fly by wire like a Gyro-Pod (read by the helm, sv_helm.lua addWire)
	"Forward", "Turn", "Up", "Strafe", "Pitch", "Boost",
}
local OUTPUTS = {
	"Hover", "Speed", "Altitude", "FTL State", "Power %", "Shield Up", "Shield %", "Hull %", "Target [ENTITY]",
	"Target Pos [VECTOR]", "Contacts", "Hostiles", "Gate Open", "Iris Closed", "Autopilot",
	-- 2026-11-14: where the ship is (owner: "compass, gps with vectors")
	"Position [VECTOR]", "Velocity [VECTOR]", "Angle [ANGLE]", "Heading", "Pitch", "Roll",
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
	elseif name == "Park" then if core.Helm and core.Helm.on then StarCore.SetFrozen(core, v ~= 0) end
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
