-- StarCore: walk inside a moving ship. Normally GMod players slide off moving props; here everyone inside a flying
-- StarCore ship moves with it (position and turning), on server and client alike (prediction), so you can walk
-- around the bridge while the ship flies. Turned off with starcore_walk 0 (server).
local cvWalk = CreateConVar("starcore_walk", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY }, "Players move along with flying StarCore ships", 0, 1)

local function inside(core, pos)
	local mins, maxs = core:GetNWVector("starcore_lmins"), core:GetNWVector("starcore_lmaxs")
	if core:GetClass() == "spacegrid_hull" then mins, maxs = core:OBBMins(), core:OBBMaxs() end
	if mins == maxs then return false end
	local l = core:WorldToLocal(pos + Vector(0, 0, 8))
	return l.x >= mins.x - 16 and l.x <= maxs.x + 16 and l.y >= mins.y - 16 and l.y <= maxs.y + 16 and l.z >= mins.z - 16 and l.z <= maxs.z + 96
end

-- has it moved since it was looked at last (a few times a second)? Faster than about 30 units a second
local function moving(e)
	local now = CurTime()
	if not e.StarCoreWalkSeen or now - e.StarCoreWalkSeen > 1 then e.StarCoreWalkSeen, e.StarCoreWalkAt, e.StarCoreWalkMoves = now, e:GetPos(), true
	elseif now - e.StarCoreWalkSeen >= 0.2 then
		e.StarCoreWalkMoves = e:GetPos():DistToSqr(e.StarCoreWalkAt) > (30 * (now - e.StarCoreWalkSeen)) ^ 2
		e.StarCoreWalkSeen, e.StarCoreWalkAt = now, e:GetPos()
	end
	return e.StarCoreWalkMoves
end

-- which ship is this player in (checked 4 times a second)
-- (test rcengineoff: engine off or the core gone in full flight, the ship went on and whoever stood in it was left in the air,
-- 4000 units behind. Who was carried is carried on until the ship stands still or he is out of it; with the core gone, by
-- the body the ship named.)
local function shipOf(ply)
	-- (who jumped - a Stargate, rings, beaming - is looked at again at once: for up to 0.25 s the ship left behind still took them
	-- along, out of the one they had come into or behind its gate - test rcshipgates)
	local here = ply:GetPos()
	if ply.StarCoreWalkSpot and here:DistToSqr(ply.StarCoreWalkSpot) > 150 * 150 then ply.StarCoreWalkCheck, ply.StarCoreEnd = 0, nil end
	ply.StarCoreWalkSpot = here
	-- (a core that is gone: looked at again at once, or the ship is a step of 0.25 s away)
	if (ply.StarCoreWalkCheck or 0) > CurTime() and (ply.StarCoreWalkCore == nil or IsValid(ply.StarCoreWalkCore)) then return ply.StarCoreWalkCore end
	ply.StarCoreWalkCheck = CurTime() + 0.25
	local found
	for _, c in ipairs(ents.FindByClass("starcore")) do
		if c:GetNWBool("starcore_hover") and inside(c, ply:GetPos()) then found = c break end
	end
	if found then
		local named = found:GetNWEntity("starcore_walk_on")
		ply.StarCoreWalkBody = IsValid(named) and named or nil
		moving(found)
	else
		local was, body = ply.StarCoreWalkCore, ply.StarCoreWalkBody
		if IsValid(was) and was:GetClass() == "starcore" then
			if inside(was, ply:GetPos()) and moving(was) then found = was end
		elseif IsValid(body) and body:GetClass() == "spacegrid_hull" and inside(body, ply:GetPos()) and moving(body) then found = body end
		if not found then ply.StarCoreWalkBody = nil end
	end
	ply.StarCoreWalkCore = found
	return found
end
local function walkBody(core)
	if core:GetClass() == "spacegrid_hull" then return core end
	local named = core:GetNWEntity("starcore_walk_on")
	if IsValid(named) then return named end
end

StarCore.WalkShipOf = shipOf

-- A ship that names the body one stands on (SpaceGrid's hull, NW "starcore_walk_on"): carried before the player's own step
-- (carried along after it, he took every step from where the deck had been - the deck that moved was in his feet or a wall
-- in his side, and he could hardly walk in flight). A ship of props: after it, as ever - its deck is a moving body that
-- pushes by itself, and carried before the step a climbing one crushed and threw who stood on it (the release
-- chat's rcpropwalk).
local function carry(ply, mv, before)
	if not cvWalk:GetBool() or ply:InVehicle() or ply:GetMoveType() ~= MOVETYPE_WALK then ply.StarCoreWalkLast = nil return end
	local core = shipOf(ply)
	if not IsValid(core) then ply.StarCoreWalkLast = nil return end
	local base = walkBody(core)
	local named = base ~= nil
	if named ~= before then
		-- (a deck of props in flight: between two moves the game's physics shifts whoever walks on it by 3 units towards the flight,
		-- 177 units in 3 seconds and over the edge - test rcdriftprop. Where his move ended is where the next begins)
		local at, g = ply.StarCoreWalkEnd, ply:GetGroundEntity()
		if not named and at and at.core == core and IsValid(g) and (g == core or StarCore.PartCore and StarCore.PartCore[g] == core) then
			-- (only sideways: the same shift lifts his feet out of a deck that leans or climbs; 3 a tick, so more after a gap)
			local p = core:GetPhysicsObject()
			if core:GetVelocity():LengthSqr() > 100 * 100 or IsValid(p) and p:GetAngleVelocity():LengthSqr() > 10 * 10 then
				local d = mv:GetOrigin() - at.pos
				d.z = 0
				local far = 8 * math.Clamp(engine.TickCount() - (ply.StarCoreWalkTick or 0), 1, 10)
				if d:LengthSqr() > 0.01 and d:LengthSqr() < far * far then mv:SetOrigin(mv:GetOrigin() - d) end
			end
		end
		return
	end
	if not named then base = core end
	local cp, ca = base:GetPos(), base:GetAngles()
	local last = ply.StarCoreWalkLast
	-- (between two moves the game's physics drags the player's body after the hull: it gives them a speed of their own and shifts
	-- them - a push every second step on a leaning deck, 430 units a second after a tick without a move, 144 sideways while
	-- walking: 60 units along the deck in a turn, jumps 190 units off, through a wall. Taken back for whoever is aboard, standing,
	-- walking or in the air; a push from outside is harder and stays. Tests rcdrift, odd_jump, deckflight)
	local was = named and before and ply.StarCoreEnd
	-- (only while the ship moves or leans; not what came with a hit, or from a lift)
	if was and last and last.core == core and last.base == base and was.core == core and (ply.StarCoreHit or 0) < was.tick and (ply.SGLifted or 0) < was.tick
		and (cp:DistToSqr(last.pos) > 0.0025 or ca ~= last.ang or base:GetUp().z < 0.9999) then
		local gap = math.Clamp(engine.TickCount() - was.tick, 1, 10)
		local dv, dp = mv:GetVelocity() - was.vel, mv:GetOrigin() - was.pos
		local hard = (was.filled or gap > 1) and 700 or 150
		if dv:LengthSqr() > 0.01 and dv:LengthSqr() < hard * hard then mv:SetVelocity(was.vel) end
		local far = 8 * gap + (was.filled and 40 or 0)
		local g = ply:GetGroundEntity()   -- (a lift moves who stands on it)
		if (g == base or not IsValid(g)) and dp:LengthSqr() > 0.0001 and dp:LengthSqr() < far * far then mv:SetOrigin(was.pos) end
	end
	ply.StarCoreEnd = nil
	if last and last.core == core and last.base == base then
		local origin = mv:GetOrigin()
		local lp = WorldToLocal(origin, Angle(), last.pos, last.ang)
		local np = LocalToWorld(lp, Angle(), cp, ca)
		local delta = np - origin
		-- a jump (teleport) moves people itself; only follow normal flight
		if delta:LengthSqr() > 1e-4 and delta:LengthSqr() < 300 * 300 then
			if named then
				-- (moved along with a deck that leans or climbs, the feet got into it - 5 units, for good)
				local to = origin + delta
				local mins, maxs = ply:GetHull()
				if ply:Crouching() then mins, maxs = ply:GetHullDuck() end
				if util.TraceHull({ start = to, endpos = to, mins = mins, maxs = maxs, mask = MASK_PLAYERSOLID, filter = ply }).StartSolid then
					-- (a wall that leans over him: a little towards the ship's middle)
					local mid = core == base and core:LocalToWorld(core:OBBCenter()) or core:LocalToWorld((core:GetNWVector("starcore_lmins") + core:GetNWVector("starcore_lmaxs")) / 2)
					local in2 = Vector(mid.x - to.x, mid.y - to.y, 0):GetNormalized()
					local found
					for _, d in ipairs({ 0, 4, 9, 16 }) do
						local at = to + in2 * d
						local tr = util.TraceHull({ start = at + Vector(0, 0, 14), endpos = at, mins = mins, maxs = maxs, mask = MASK_PLAYERSOLID, filter = ply })
						if not tr.StartSolid then delta = tr.HitPos - origin found = true break end
					end
					-- (a low cockpit that leans: no room for 14 up, and the wall is not on the far side from the ship's middle - he
					-- stood wedged and could not take a step. Any way that is free, the nearest first, never behind a wall)
					if not found and (ply.StarCoreWedged or 0) < CurTime() then
						local c = Vector(0, 0, (mins.z + maxs.z) / 2)
						for _, d in ipairs({ 0, 4, 9, 16, 24 }) do
							for turn = 0, d == 0 and 0 or 315, 45 do
								local at = to + Angle(0, in2:Angle().y + turn, 0):Forward() * d
								for _, up in ipairs({ 2, 6, 10 }) do
									local tr = util.TraceHull({ start = at + Vector(0, 0, up), endpos = at, mins = mins, maxs = maxs, mask = MASK_PLAYERSOLID, filter = ply })
									if not tr.StartSolid and not util.TraceLine({ start = to + c, endpos = tr.HitPos + c, mask = MASK_PLAYERSOLID, filter = ply }).Hit then delta = tr.HitPos - origin found = true break end
								end
								if found then break end
							end
							if found then break end
						end
						if not found then ply.StarCoreWedged = CurTime() + 0.1 end
					end
				end
			end
			mv:SetOrigin(origin + delta)
			if SERVER then
				StarCore.WalkApplied = (StarCore.WalkApplied or 0) + 1
				-- the player's physics shadow must come along, otherwise it pulls the player back
				local po = ply:GetPhysicsObject()
				if IsValid(po) then po:SetPos(origin + delta, true) end
			end
			ply.StarCoreYaw = (ply.StarCoreYaw or 0) + math.AngleDifference(ca.y, last.ang.y)
			ply.StarCoreShipSpeed = delta:Length() / engine.TickInterval()
		elseif delta:LengthSqr() <= 1e-4 then ply.StarCoreShipSpeed = 0 end
	end
	ply.StarCoreWalkLast = { core = core, base = base, pos = cp, ang = ca }
	ply.StarCoreWalkEnd = not named and { core = core, pos = mv:GetOrigin() } or nil
	ply.StarCoreWalkTick = engine.TickCount()
end
-- In multiplayer the player's own game runs his moves ahead of the server and does them again after every message from it
-- (and the newest one every frame). Meanwhile it has the piece he stands on where the server has it, the rest of the ship
-- where it is drawn - about a tenth of a second behind - and the picture is drawn at yet another moment. Carried there as on
-- the server, what he saw jumped by up to 70 units a frame. So there: every move is done round the piece he stands on, as it
-- is at that move; each move's end is remembered in that piece; and his view is put where that is on the ship as it is drawn.
local drawn          -- the local player's ship: core, base (the piece), yaw at the last move, his newest move
local ends = {}      -- command number % 128 -> { cn, base, pos, ang, out, lp }: where his last moves ended
local function offShip() drawn = nil if next(ends) then ends = {} end end
local function baseOf(ply, core)
	local named = walkBody(core)
	if named then return named end
	local g = ply:GetGroundEntity()
	if IsValid(g) and not g:IsWorld() and not g:IsPlayer() and not g:IsNPC() and g:GetMoveType() == MOVETYPE_VPHYSICS then return g end
	return drawn and drawn.core == core and IsValid(drawn.base) and drawn.base or core
end
local shipSpeed = 0   -- how fast the piece he stands on is drawn to move
local onOther = -1   -- when he last stood on something else than the ship itself (a lift moves him without a key of his)
local lastCn, chained   -- the newest move so far; the move done before in this go
local devSince, devSeen   -- since when, and when last, the server had him somewhere else on the ship than his own game
local function carryDrawn(ply, mv, cmd)
	if not cvWalk:GetBool() or ply:InVehicle() or ply:GetMoveType() ~= MOVETYPE_WALK then offShip() return end
	local core = shipOf(ply)
	if not IsValid(core) then offShip() return end
	if drawn and drawn.core ~= core then offShip() end
	local base = baseOf(ply, core)
	local origin = mv:GetOrigin()
	local cn = cmd:CommandNumber()
	-- his own game's move before, or the server's place (the nearer one of where that move ended and the same spot of the ship
	-- as the server has it)
	local from = base
	local fp, fa = base:GetNetworkOrigin(), base:GetNetworkAngles()
	local e = ends[(cn - 1) % 128]
	if e and e.cn == cn - 1 and e.out and IsValid(e.base) then
		-- (a message from the server: the game goes back to what that says and does the moves since once more - the first of them
		-- starts at the server's place. The one after the last, and the newest over again every frame, start at his own move's end.
		-- By which of the two is nearer alone, a lift - the server moves him, his game does not know - was taken for the own move
		-- now and then, and the view jumped the 90 units the ship is ahead; deckflight)
		-- (but the game may go on from a move of its own after a message too, and it may have pushed him a little after the
		-- move - in a climb: by the order alone, the view jumped the 50 units the ship is ahead; sgshake. Clearly nearer counts)
		local own = origin:DistToSqr(e.out)
		local there = origin:DistToSqr(LocalToWorld(e.lp, angle_zero, e.base:GetNetworkOrigin(), e.base:GetNetworkAngles()))
		local again = lastCn and cn < lastCn and chained ~= cn - 1
		-- (who stands still on the ship itself: the nearer of the two, as before - by the order the view jumped now and then in a
		-- climb and a turn; sgshake)
		local ge = ply:GetGroundEntity()
		if IsValid(ge) and ge ~= base then onOther = RealTime() end
		local still = RealTime() - onOther > 0.5 and cmd:GetForwardMove() == 0 and cmd:GetSideMove() == 0 and not cmd:KeyDown(IN_JUMP) and ply:OnGround()
		if still then again = false end
		if own < 0.25 or not again and own <= there or again and own < 16 * 16 and own * 16 < there or not still and lastCn and cn <= lastCn and chained == cn - 1 and own < 60 * 60 then
			from, fp, fa = e.base, e.pos, e.ang
		end
	end
	lastCn, chained = math.max(lastCn or 0, cn), cn
	local np = LocalToWorld((WorldToLocal(origin, angle_zero, fp, fa)), angle_zero, from:GetPos(), from:GetAngles())
	-- (a message in which the ship has moved and he not yet - a tick without a move of his - puts him back by a tick's way, 12
	-- units, till the next one: a jump of the picture, sgshake and rcview on a server. Believed only if it lasts)
	-- (who stands still on a ship that moves: for a walk or a jump the server is right at once)
	if RealTime() - onOther > 0.5 and shipSpeed > 50 and e and e.cn == cn - 1 and e.lp and IsValid(e.base) and cmd:GetForwardMove() == 0 and cmd:GetSideMove() == 0 and not cmd:KeyDown(IN_JUMP) and ply:OnGround() and mv:GetVelocity():LengthSqr() < 5 * 5 then
		local own = LocalToWorld(e.lp, angle_zero, e.base:GetPos(), e.base:GetAngles())
		local d, t = np:DistToSqr(own), RealTime()
		if d > 0.1 and d < 60 * 60 then
			devSince, devSeen = devSince or t, t
			if t - devSince < 0.25 then np = own end
		elseif not devSeen or t - devSeen > 0.1 then devSince = nil end
	end
	-- (farther: a jump or a Stargate, the server moves people itself)
	local ok = np:DistToSqr(origin) < 600 * 600
	if ok then mv:SetOrigin(np) end
	local yaw = core:GetAngles().y
	local m = { cn = cn, base = base, pos = base:GetPos(), ang = base:GetAngles() }
	if drawn and drawn.move and drawn.move.cn == cn then m.at = drawn.move.at else m.at = RealTime() end
	ends[cn % 128] = m
	drawn = { core = core, base = base, yaw = yaw, move = m }
end
local function carried(ply, mv)
	local m = drawn and drawn.move
	if not m then return end
	m.out = mv:GetOrigin()
	m.lp = WorldToLocal(m.out, angle_zero, m.pos, m.ang)
end
-- where he is on the ship as it is drawn now: between his last two moves, as the game draws any player. A correction from the
-- server (with lag, walking on a flying deck) is worn off in a moment instead of seen as a jump - in the ship, not in the world
-- (kept for a frame is the place in the ship only: the game asks at several moments of it, with the ship at other places)
local shown = {}   -- frame, base, lp (as it is), off (what is still worn off), t
local function drawnPlace()
	local m = drawn and drawn.move
	if not (m and m.lp and IsValid(m.base)) then shown = {} return end
	if shown.frame == FrameNumber() and shown.base == m.base then return LocalToWorld(shown.lp + shown.off, angle_zero, m.base:GetPos(), m.base:GetAngles()) end
	local lp = m.lp
	local e = ends[(m.cn - 1) % 128]
	if e and e.cn == m.cn - 1 and e.lp and IsValid(e.base) then
		local was = e.base == m.base and e.lp or WorldToLocal(LocalToWorld(e.lp, angle_zero, e.base:GetPos(), e.base:GetAngles()), angle_zero, m.base:GetPos(), m.base:GetAngles())
		if was:DistToSqr(lp) < 64 * 64 then lp = LerpVector(math.Clamp((RealTime() - m.at) / engine.TickInterval(), 0, 1), was, lp) end
	end
	local now, off = RealTime(), vector_origin
	if shown.base == m.base and now - shown.t < 0.5 then
		local dt = now - shown.t
		off = shown.off * math.exp(-dt / 0.1)
		local jump = shown.lp - lp
		local far = jump:Length()
		if far > 600 * dt + 2 and far < 128 then off = off + jump end
		if off:LengthSqr() > 128 * 128 then off = vector_origin end
	end
	shown = { frame = FrameNumber(), base = m.base, lp = lp, off = off, t = now }
	return LocalToWorld(lp + off, angle_zero, m.base:GetPos(), m.base:GetAngles())
end

-- out of a Stargate on board of a flying ship (Ascension Gates): on the ship from that moment - before, it flew 24 units on under
-- the feet first, and whoever came out stood in the horizon (server, test rcshipgates)
if SERVER then
	hook.Add("StarGate.Arrived", "StarCore.Walk", function(ply)
		if not ply:IsPlayer() or not cvWalk:GetBool() then return end
		ply.StarCoreWalkCheck, ply.StarCoreWalkSpot = 0, ply:GetPos()
		local core = shipOf(ply)
		local base = IsValid(core) and (walkBody(core) or core)
		ply.StarCoreWalkLast = base and { core = core, base = base, pos = base:GetPos(), ang = base:GetAngles() } or nil
		ply.StarCoreWalkEnd, ply.StarCoreEnd = nil, nil
		ply.StarCoreWalkTick = engine.TickCount()
	end)
	hook.Add("EntityTakeDamage", "StarCore.WalkHit", function(e) if e:IsPlayer() then e.StarCoreHit = engine.TickCount() end end)
	-- who had no move yet in this tick, along with the ship as far as it is now
	local function carryNow(ply, tick)
		local last = ply.StarCoreWalkLast
		if not (last and ply.StarCoreWalkTick and ply.StarCoreWalkTick ~= tick and tick - ply.StarCoreWalkTick < 200 and cvWalk:GetBool() and ply:Alive() and not ply:InVehicle() and ply:GetMoveType() == MOVETYPE_WALK
			and IsValid(last.core) and IsValid(last.base) and ply.StarCoreWalkCore == last.core and walkBody(last.core) == last.base) then return end
		local origin, cp, ca = ply:GetPos(), last.base:GetPos(), last.base:GetAngles()
		local np = LocalToWorld((WorldToLocal(origin, angle_zero, last.pos, last.ang)), angle_zero, cp, ca)
		local d = np:DistToSqr(origin)
		-- (jumped in this very tick: not by the ship left behind - rcshipgates, server)
		if ply.StarCoreWalkSpot and origin:DistToSqr(ply.StarCoreWalkSpot) > 150 * 150 then
			ply.StarCoreWalkLast, ply.StarCoreWalkCheck, ply.StarCoreEnd = nil, 0, nil
			return
		end
		if d > 1e-4 and d < 300 * 300 then
			-- (SetLocalPos: SetPos is a teleport for the game - the smoothing of the view starts anew, a jump came down 190 units off)
			ply:SetLocalPos(np)
			local po = ply:GetPhysicsObject()
			if IsValid(po) then po:SetPos(np, true) end
			ply.StarCoreWalkSpot = np
			if ply.StarCoreEnd then ply.StarCoreEnd.pos, ply.StarCoreEnd.filled = np, true end
			ply.StarCoreYaw = (ply.StarCoreYaw or 0) + math.AngleDifference(ca.y, last.ang.y)
		end
		last.pos, last.ang = cp, ca
	end
	-- A shot at somebody on the same flying ship (test rcshots: at 100 ms 0 of 13 hit in boost and in a climb): for a shot the server
	-- takes the other players back to where they were in the world, the ship and who shoots from it not. On one ship they are
	-- where they are on it - the rest as ever. (asked
	-- for by AGP's shot checks as well: a body asked for before - is a gate, a shield in the way? - is kept for a tenth of a second
	-- where the server had taken it back to; so before they ask)
	function StarCore.ShotAboard(e)
		if game.SinglePlayer() or not IsValid(e) then return end
		local ply = e:IsPlayer() and e or (IsValid(e:GetOwner()) and e:GetOwner():IsPlayer() and e:GetOwner())
		if not ply or ply:InVehicle() or not cvWalk:GetBool() then return end
		local core = ply.StarCoreWalkCore
		if not IsValid(core) or not ply.StarCoreWalkLast then return end
		local base = walkBody(core) or core
		if base:GetVelocity():LengthSqr() < 50 * 50 and (not ply.StarCoreShipSpeed or ply.StarCoreShipSpeed < 50) then return end
		ply:LagCompensation(false)
		-- (the others aboard: as far as the ship is now)
		for _, o in ipairs(player.GetAll()) do
			if o ~= ply and o.StarCoreWalkCore == core then
				carryNow(o, engine.TickCount())
			end
		end
		local tr = util.TraceLine({ start = ply:GetShootPos(), endpos = ply:GetShootPos() + ply:GetAimVector() * 8192, mask = MASK_SHOT, filter = ply })
		local hit = tr.Entity
		local aboard = IsValid(hit) and (hit == base or hit == core or hit:IsPlayer() and hit.StarCoreWalkCore == core or StarCore.PartCore[hit] == core)
		if not aboard then ply:LagCompensation(true) end
	end
	hook.Add("EntityFireBullets", "StarCore.Walk", function(e) StarCore.ShotAboard(e) end)
	-- A tick without a move of his (a lagging connection, seen at 100 ms): the ship flew on without him until the next one, 12
	-- units a tick - whoever stood near a wall was pushed out through it by two such ticks (deckflight, server), or into a gate's
	-- horizon behind him. Not on a deck of props: the game's physics moves who stands on it (rc_walk_mp)
	hook.Add("Think", "StarCore.Walk", function()
		local tick = engine.TickCount()
		for _, ply in ipairs(player.GetAll()) do carryNow(ply, tick) end
	end)
end

if CLIENT and not game.SinglePlayer() then
	hook.Add("SetupMove", "StarCore.Walk", function(ply, mv, cmd) if ply == LocalPlayer() then carryDrawn(ply, mv, cmd) end end)
	hook.Add("FinishMove", "StarCore.Walk", function(ply, mv) if ply == LocalPlayer() then carried(ply, mv) end end)
	hook.Add("CalcView", "StarCore.Walk", function(ply, origin)
		if not drawn or ply ~= LocalPlayer() or not ply:Alive() or ply:GetViewEntity() ~= ply then return end
		local at = drawnPlace()
		if not at then return end
		local eye = at + ply:GetCurrentViewOffset()
		if eye:DistToSqr(origin) < 600 * 600 then origin:Set(eye) end
	end)
	-- (the arms: the game puts them round its own place for the eyes)
	hook.Add("CalcViewModelView", "StarCore.Walk", function(_, _, oldPos, _, pos)
		local ply = LocalPlayer()
		if not drawn or not ply:Alive() or ply:GetViewEntity() ~= ply then return end
		local at = drawnPlace()
		if not at then return end
		local d = at + ply:GetCurrentViewOffset() - oldPos
		if d:LengthSqr() > 600 * 600 then return end
		oldPos:Add(d)
		if pos ~= oldPos then pos:Add(d) end
	end)
	-- (his own body, seen in a mirror or from outside)
	hook.Add("PrePlayerDraw", "StarCore.Walk", function(ply)
		if not drawn or ply ~= LocalPlayer() then return end
		local at = drawnPlace()
		if at then ply:SetRenderOrigin(at) ply.StarCoreDrawnAt = true end
	end)
	hook.Add("PostPlayerDraw", "StarCore.Walk", function(ply)
		if ply.StarCoreDrawnAt then ply.StarCoreDrawnAt = nil ply:SetRenderOrigin(nil) end
	end)
	-- The others aboard: the game draws them and the ship at two moments - in full flight 80 units further back on the deck than they
	-- stand, in a climb half in it (server, test rcplayers). Both as the server sent them last gives their place on the ship; there
	-- they are drawn, on the ship as it is drawn. Their own steps are worn in over a tenth of a second.
	local others, cores, nextLook = {}, {}, 0
	hook.Add("PreRender", "StarCore.Walk", function()
		local now = RealTime()
		if now > nextLook then nextLook = now + 0.25 cores = ents.FindByClass("starcore") end
		for _, ply in ipairs(player.GetAll()) do
			local st, at = others[ply], nil
			if #cores > 0 and cvWalk:GetBool() and ply ~= LocalPlayer() and ply:Alive() and not ply:IsDormant() and not ply:InVehicle() and ply:GetMoveType() == MOVETYPE_WALK then
				for _, core in ipairs(cores) do
					if IsValid(core) and not core:IsDormant() and core:GetNWBool("starcore_hover") then
						local base = walkBody(core) or core
						local lp = WorldToLocal(ply:GetNetworkOrigin(), angle_zero, base:GetNetworkOrigin(), base:GetNetworkAngles())
						-- (in the body one walks in, by its own box: the core on it is drawn at yet another moment - in a climb they were
						-- aboard one frame and not the next)
						local mn, mx = base:OBBMins(), base:OBBMaxs()
						local aboard = base ~= core and lp.x > mn.x - 16 and lp.x < mx.x + 16 and lp.y > mn.y - 16 and lp.y < mx.y + 16 and lp.z > mn.z - 16 and lp.z < mx.z + 96
						if aboard or base == core and inside(core, base:LocalToWorld(lp)) then
							if not st or st.base ~= base or st.to:DistToSqr(lp) > 200 * 200 then st = { base = base, from = lp, to = lp, t = now }
							elseif st.to ~= lp then
								st.from = LerpVector(math.Clamp((now - st.t) / 0.1, 0, 1), st.from, st.to)
								st.to, st.t = lp, now
							end
							others[ply] = st
							at = base:LocalToWorld(LerpVector(math.Clamp((now - st.t) / 0.1, 0, 1), st.from, st.to))
							break
						end
					end
				end
			end
			-- (a player is drawn where they are, whatever SetRenderOrigin says: put there; the game sets its own place again next frame)
			if at then
				ply:SetPos(at)
				ply:InvalidateBoneCache()
			elseif st then others[ply] = nil end
		end
	end)
else
	hook.Add("SetupMove", "StarCore.Walk", function(ply, mv) carry(ply, mv, true) end)
	hook.Add("FinishMove", "StarCore.Walk", function(ply, mv)
		carry(ply, mv, false)
		local last = ply.StarCoreWalkLast
		if last and walkBody(last.core) == last.base then ply.StarCoreEnd = { core = last.core, vel = mv:GetVelocity(), pos = mv:GetOrigin(), tick = engine.TickCount() } else ply.StarCoreEnd = nil end
	end)
end

if CLIENT then
	-- turn the view with the ship
	local turnOf, turnAt, turnBy
	-- (on a server: by the piece he stands on as it is drawn, once a frame. By the core as the game had it at each move - the
	-- network's steps - the view trembled by 2 to 7 degrees every frame on a turning ship of props: the author saw it, rcview)
	if not game.SinglePlayer() then
		local shipAt, shipT
		hook.Add("PreRender", "StarCore.WalkTurn", function()
			local base = drawn and IsValid(drawn.base) and drawn.base or nil
			local now, t = base and base:GetAngles().y, RealTime()
			if base and turnOf == base and turnAt then turnBy = (turnBy or 0) + math.AngleDifference(now, turnAt) else turnBy = nil end
			if base and turnOf == base and shipAt and t > shipT then shipSpeed = base:GetPos():Distance(shipAt) / (t - shipT) elseif not base then shipSpeed = 0 end
			shipAt, shipT = base and base:GetPos(), t
			turnOf, turnAt = base, now
		end)
	end
	hook.Add("CreateMove", "StarCore.WalkTurn", function(cmd)
		local ply = LocalPlayer()
		local y
		if game.SinglePlayer() then
			y = ply.StarCoreYaw
			ply.StarCoreYaw = 0
		else
			y, turnBy = turnBy, nil
		end
		if not y or y == 0 then return end
		local a = cmd:GetViewAngles()
		a.y = a.y + y
		cmd:SetViewAngles(a)
	end)
end
