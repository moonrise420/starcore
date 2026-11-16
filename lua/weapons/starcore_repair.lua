-- StarCore repair tool: hold left mouse on any part of a StarCore ship to repair its hull
AddCSLuaFile()

SWEP.PrintName = "#starcore.repair_tool"
SWEP.Category = "StarCore"
SWEP.IconOverride = "entities/starcore_repair.png"
SWEP.Spawnable = true
SWEP.AdminOnly = false
SWEP.ViewModel = "models/weapons/c_toolgun.mdl"
SWEP.WorldModel = "models/weapons/w_toolgun.mdl"
SWEP.UseHands = true
SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = true
SWEP.Primary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

function SWEP:PrimaryAttack()
	self:SetNextPrimaryFire(CurTime() + 0.2)
	local ply = self:GetOwner()
	local tr = ply:GetEyeTrace()
	if not tr.Hit or tr.HitPos:Distance(ply:GetShootPos()) > 200 then return end
	local fx = EffectData()
	fx:SetOrigin(tr.HitPos)
	fx:SetNormal(tr.HitNormal)
	fx:SetMagnitude(1); fx:SetScale(1); fx:SetRadius(2)
	util.Effect("Sparks", fx)
	if CLIENT then return end
	local core = StarCore.PartCore and StarCore.PartCore[tr.Entity]
	if not IsValid(core) or not core.HullMax then return end
	local added = StarCore.HullRepair(core, math.ceil(core.HullMax * 0.01))
	if added > 0 then
		self:EmitSound("ambient/energy/spark" .. math.random(1, 6) .. ".wav", 60, 110)
	end
end

function SWEP:SecondaryAttack() end

if CLIENT then
	function SWEP:DrawHUD()
		local tr = LocalPlayer():GetEyeTrace()
		local core
		for _, c in ipairs(ents.FindByClass("starcore")) do
			if IsValid(tr.Entity) and tr.HitPos:Distance(LocalPlayer():GetShootPos()) < 200 and c:GetNWInt("starcore_hull_max") > 0 then
				local mins, maxs = c:GetNWVector("starcore_lmins"), c:GetNWVector("starcore_lmaxs")
				local l = c:WorldToLocal(tr.HitPos)
				if l.x >= mins.x - 4 and l.x <= maxs.x + 4 and l.y >= mins.y - 4 and l.y <= maxs.y + 4 and l.z >= mins.z - 4 and l.z <= maxs.z + 4 then core = c break end
			end
		end
		if not core then return end
		local pct = core:GetNWInt("starcore_hull") / math.max(core:GetNWInt("starcore_hull_max"), 1)
		local w, x, y = 260, ScrW() / 2 - 130, ScrH() / 2 + 40
		draw.RoundedBox(4, x, y, w, 18, Color(0, 0, 0, 180))
		draw.RoundedBox(4, x + 2, y + 2, (w - 4) * pct, 14, pct < 0.3 and Color(255, 90, 60) or Color(90, 220, 120))
		draw.SimpleText(StarCore.T("hud_hull", math.floor(pct * 100)), "DermaDefaultBold", ScrW() / 2, y + 9, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end
