-- Pet names are visible to visitors, so Roblox requires them to go through
-- the text filter before they're shown.

local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PetRules"))

local Names = {}

-- Returns the filtered name, or nil and a message for the player.
function Names.Filter(player: Player, raw: any): (string?, string?)
	local clean = PetRules.CleanName(raw)
	if not clean then
		return nil, "Names need 1-20 letters or numbers."
	end
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(clean, player.UserId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		return nil, "Couldn't check that name right now. Please try again."
	end
	if string.find(result, "#") then
		return nil, "That name isn't allowed. Try another!"
	end
	return result, nil
end

return Names
