--!strict
-- Who is an admin (D-069), checked on the server only, never on the client's
-- word: the experience owner (game.CreatorId when game.CreatorType is User;
-- for a group-owned game, a member of that group at Config.ADMIN_GROUP_RANK or
-- above, read with GroupService:GetRolesInGroupAsync, which the docs say
-- supersedes the deprecated Player:GetRankInGroupAsync) and the user ids in
-- Config.ADMIN_USER_IDS. Admins own the Color Pass and the Name Pass for free
-- (server/PassService) and may review reported names (server/NameReview).
-- The group rank yields, so it is read once per visit (`refresh`, on join)
-- and cached; a failed read is "not an admin".

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Sim.Config)

local Admins = {}

-- The admin user ids (from Config; replaceable by the specs).
Admins.userIds = table.clone(Config.defaults.ADMIN_USER_IDS) :: { number }

local groupAdmins: { [number]: boolean } = {} -- user id -> admin by group rank (this visit)

local function owner(): (string?, number?)
	local ok, kind, id = pcall(function(): (any, any)
		return game.CreatorType, game.CreatorId
	end)
	if not ok or type(id) ~= "number" or id <= 0 then
		return nil, nil
	end
	local name = if typeof(kind) == "EnumItem" then (kind :: EnumItem).Name else tostring(kind)
	return name, id
end

-- True if this user id is an admin as far as the server knows now. Never yields.
function Admins.isAdminId(userId: number): boolean
	if table.find(Admins.userIds, userId) ~= nil then
		return true
	end
	local kind, id = owner()
	if kind == "User" and id == userId then
		return true
	end
	return groupAdmins[userId] == true
end

function Admins.isAdmin(player: Player): boolean
	return Admins.isAdminId(player.UserId)
end

-- Reads a group-owned game's rank for `player` (yields; call on join).
function Admins.refresh(player: Player)
	local kind, groupId = owner()
	if kind ~= "Group" or groupId == nil then
		return
	end
	local ok, info = pcall(function(): any
		return game:GetService("GroupService"):GetRolesInGroupAsync(player.UserId, groupId)
	end)
	local best = 0
	if ok and type(info) == "table" and info.IsMember == true and type(info.Roles) == "table" then
		for _, role in info.Roles do
			if type(role) == "table" and type(role.Rank) == "number" then
				best = math.max(best, role.Rank)
			end
		end
	end
	groupAdmins[player.UserId] = best >= Config.defaults.ADMIN_GROUP_RANK
end

function Admins.forget(player: Player)
	groupAdmins[player.UserId] = nil
end

return Admins
