--!strict
-- Who may buy, set and see custom candidate names (the Name Pass, D-063): only
-- accounts Roblox has verified as at least Config.NAME_MIN_AGE (16) years old.
-- Everyone else, and anyone whose age the game cannot read, is not eligible:
-- this fails closed.
--
-- What the Roblox engine docs offer a game script (checked Oct 2026 in
-- creator-docs, reference/engine), and why none of it is used:
--   Player.AgeChecked (Enum.AgeCheckStatus Unchecked | Checked): whether the
--     player finished an age check (Player:PromptAgeCheck). It does not say
--     which age the check found, so it cannot tell 16+ from 9-15.
--   Player:IsVerified(Enum.VerifiedLevel.Low | High): "real-world signals"
--     such as a phone number or government ID; not an age. Always false in Studio.
--   PolicyService:GetPolicyInfoForPlayerAsync: policy flags (AreAdsAllowed,
--     ArePaidRandomItemsRestricted, IsContentSharingAllowed, IsPhotoToAvatarAllowed
--     "reflects age (for example, users under 13)", ...). No age or 16+ flag.
--   TextChatService:CanUserChatAsync / CanUsersChatAsync / GetChatGroupsAsync:
--     whether players may chat (age checks and parental controls feed it); not an age.
--   Players / Player have no age, age group or birthday.
-- The one exact 16+ guarantee is outside scripts: a game whose maturity label
-- is "Content May Vary" is only open to age-checked users 16+
-- (production/promotion/content-maturity, production/publishing/kids-and-select).
--
-- So `verifiedAge` returns nil for everyone until Roblox offers an API; plug it
-- in here and nowhere else. The specs replace `verifiedAge` to test the rest.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Sim.Config)
local CustomName = require(ReplicatedStorage.Shared.Net.CustomName)

local NameEligibility = {}

-- The player's age as Roblox has verified it, or nil when the game cannot know.
-- No engine API returns it today (see the header), so: nil.
function NameEligibility.verifiedAge(_player: Player): number?
	return nil
end

-- True only for an account verified as NAME_MIN_AGE or older. Never yields
-- longer than verifiedAge does; never throws (a failure is "not eligible").
function NameEligibility.isEligible(player: Player): boolean
	local ok, age = pcall(NameEligibility.verifiedAge, player)
	return ok and CustomName.eligibleAge(age, Config.defaults)
end

return NameEligibility
