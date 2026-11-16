-- StarCore E2 functions: control a StarCore you are allowed to use (owner, prop protection friends, public ships)
E2Lib.RegisterExtension("starcore", true, "Lets E2 chips fly and command StarCore ship cores their owner may use.")

local function core(self, ent)
	if not IsValid(ent) or ent:GetClass() ~= "starcore" or not StarCore then return nil end
	if not StarCore.CanControl(ent, self.player) then return nil end
	return ent
end

__e2setcost(5)

-- 1 if the chip may use this core
e2function number entity:starcoreValid()
	return core(self, this) and 1 or 0
end

e2function number entity:starcoreHover(number on)
	local c = core(self, this) if not c then return 0 end
	StarCore.HelmSetOn(c, on ~= 0)
	return 1
end

__e2setcost(20)

-- jump to a position / to a saved mark; returns 1 when the jump started
e2function number entity:starcoreJump(vector pos)
	local c = core(self, this) if not c then return 0 end
	local ok = StarCore.RequestJump(c, self.player, { kind = "coord", pos = Vector(pos[1], pos[2], pos[3]) })
	return ok and 1 or 0
end

e2function number entity:starcoreJumpMark(number index)
	local c = core(self, this) if not c then return 0 end
	local ok = StarCore.RequestJump(c, self.player, { kind = "mark", index = math.floor(index) })
	return ok and 1 or 0
end

__e2setcost(5)

e2function number entity:starcoreFire(number on)
	local c = core(self, this) if not c then return 0 end
	c.Engage = on ~= 0
	if not c.Engage then StarCore.StopWeapons(c) end
	return 1
end

e2function number entity:starcoreSetTarget(entity target)
	local c = core(self, this) if not c then return 0 end
	if not IsValid(target) or not StarCore.ContactOf(c, target) then return 0 end
	c.Target = target
	c:SetNWEntity("starcore_target", target)
	return 1
end

e2function entity entity:starcoreTarget()
	local c = core(self, this) if not c then return NULL end
	return IsValid(c.Target) and c.Target or NULL
end

e2function number entity:starcoreShield(number on)
	local c = core(self, this) if not c then return 0 end
	return StarCore.ShieldSet(c, on ~= 0)
end

e2function number entity:starcoreSpeed()
	local c = core(self, this) if not c then return 0 end
	return c:GetNWFloat("starcore_speed")
end

e2function number entity:starcorePower()
	local c = core(self, this) if not c then return -1 end
	return c:GetNWFloat("starcore_power_pct", -1)
end

e2function number entity:starcoreFTLState()
	local c = core(self, this) if not c then return -1 end
	return c:GetNWInt("starcore_ftl")
end

__e2setcost(20)

-- every radar contact (hostiles first)
e2function array entity:starcoreContacts()
	local c = core(self, this) if not c then return {} end
	local out = {}
	for i, k in ipairs(c.Contacts or {}) do out[i] = k.ent end
	return out
end

e2function array entity:starcoreHostiles()
	local c = core(self, this) if not c then return {} end
	local out = {}
	for _, k in ipairs(c.Contacts or {}) do if k.iff == StarCore.IFF.hostile then out[#out + 1] = k.ent end end
	return out
end
