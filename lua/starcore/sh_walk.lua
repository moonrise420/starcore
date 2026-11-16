-- StarCore: walk inside a moving ship. Normally GMod players slide off moving props; here everyone inside a flying
-- StarCore ship moves with it (position and turning), on server and client alike (prediction), so you can walk
-- around the bridge while the ship flies. Turned off with starcore_walk 0 (server).
local cvWalk = CreateConVar("starcore_walk", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY }, "Players move along with flying StarCore ships", 0, 1)

local function inside(core, pos)
	local mins, maxs = core:GetNWVector("starcore_lmins"), core:GetNWVector("starcore_lmaxs")
	if mins == maxs then return false end
	local l = core:WorldToLocal(pos + Vector(0, 0, 8))
	return l.x >= mins.x - 16 and l.x <= maxs.x + 16 and l.y >= mins.y - 16 and l.y <= maxs.y + 16 and l.z >= mins.z - 16 and l.z <= maxs.z + 96
end

-- which ship is this player in (checked 4 times a second)
local function shipOf(ply)
	if (ply.StarCoreWalkCheck or 0) > CurTime() then return ply.StarCoreWalkCore end
	ply.StarCoreWalkCheck = CurTime() + 0.25
	local found
	for _, c in ipairs(ents.FindByClass("starcore")) do
		if c:GetNWBool("starcore_hover") and inside(c, ply:GetPos()) then found = c break end
	end
	ply.StarCoreWalkCore = found
	return found
end

StarCore.WalkShipOf = shipOf

hook.Add("FinishMove", "StarCore.Walk", function(ply, mv)
	if not cvWalk:GetBool() or ply:InVehicle() or ply:GetMoveType() ~= MOVETYPE_WALK then ply.StarCoreWalkLast = nil return end
	local core = shipOf(ply)
	if not IsValid(core) then ply.StarCoreWalkLast = nil return end
	local cp, ca = core:GetPos(), core:GetAngles()
	local last = ply.StarCoreWalkLast
	if last and last.core == core then
		local origin = mv:GetOrigin()
		local lp = WorldToLocal(origin, Angle(), last.pos, last.ang)
		local np = LocalToWorld(lp, Angle(), cp, ca)
		local delta = np - origin
		-- a jump (teleport) moves people itself; only follow normal flight
		if delta:LengthSqr() > 1e-4 and delta:LengthSqr() < 300 * 300 then
			mv:SetOrigin(origin + delta)
			if SERVER then
				StarCore.WalkApplied = (StarCore.WalkApplied or 0) + 1
				-- the player's physics shadow must come along, otherwise it pulls the player back
				local po = ply:GetPhysicsObject()
				if IsValid(po) then po:SetPos(origin + delta, true) end
			end
			ply.StarCoreYaw = (ply.StarCoreYaw or 0) + math.AngleDifference(ca.y, last.ang.y)
		end
	end
	ply.StarCoreWalkLast = { core = core, pos = cp, ang = ca }
end)

if CLIENT then
	-- turn the view with the ship
	hook.Add("CreateMove", "StarCore.WalkTurn", function(cmd)
		local ply = LocalPlayer()
		local y = ply.StarCoreYaw
		if not y or y == 0 then return end
		ply.StarCoreYaw = 0
		local a = cmd:GetViewAngles()
		a.y = a.y + y
		cmd:SetViewAngles(a)
	end)
end
