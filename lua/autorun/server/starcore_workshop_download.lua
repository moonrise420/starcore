-- Players who join a server download this addon's models, materials and sounds from the Steam Workshop before they
-- spawn (resource.AddWorkshop). Without it they see ERROR models and missing textures. Fill in the Workshop item
-- IDs after the upload; empty = nothing is sent. Servers with their own FastDL can turn it off: agp_workshop_download 0
local IDS = {
	"3840678974", -- StarCore
}

local cv = CreateConVar("agp_workshop_download", "1", FCVAR_ARCHIVE, "Send the Ascension Gates addons' Workshop content to joining players (1 = on)")
if not cv:GetBool() then return end
for _, id in ipairs(IDS) do
	if id ~= "" then resource.AddWorkshop(id) end
end
