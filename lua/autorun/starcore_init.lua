-- StarCore - Spaceship Core: loader
StarCore = StarCore or {}
StarCore.Version = "1.0.2"

local shared = { "sh_config.lua", "sh_license.lua", "sh_voice.lua", "sh_walk.lua", "sh_admin.lua" }
local server = { "sv_core.lua", "sv_helm.lua", "sv_teleport.lua", "sv_ftl.lua", "sv_stargate.lua", "sv_combat.lua", "sv_power.lua", "sv_transporter.lua", "sv_wire.lua", "sv_autopilot.lua", "sv_crew.lua", "sv_systems.lua", "sv_dock.lua", "sv_net.lua" }
local client = { "cl_menu.lua", "cl_hud.lua" }

for _, f in ipairs(shared) do
	if SERVER then AddCSLuaFile("starcore/" .. f) end
	include("starcore/" .. f)
end
for _, f in ipairs(client) do
	if SERVER then AddCSLuaFile("starcore/" .. f) else include("starcore/" .. f) end
end
if SERVER then
	for _, f in ipairs(server) do include("starcore/" .. f) end
end
