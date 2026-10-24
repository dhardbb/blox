--!strict
-- Rematch on the Results screen (docs/DESIGN.md D-080). Pure: MatchService keeps
-- one offer per finished match and asks these helpers what a tap does.
--
-- Against the bot a tap starts a new match at once against the same level.
-- Against a person both must tap within Config.REMATCH_WINDOW_SECONDS; then a
-- new match starts with a new seed and the same seats. If the opponent leaves
-- the server, or starts something else (queues, hosts, plays the bot, another
-- match), the offer is gone and the button says so. The rated rules (D-077,
-- RATED_PAIR_DAILY_MAX) apply to the new match as to any other.

local Rematch = {}

export type State =
	"Open" -- nobody has asked yet
	| "Waiting" -- you asked; the opponent has not
	| "Asked" -- the opponent asked; you have not
	| "Started" -- both asked: the new match is starting
	| "Gone" -- the opponent left or started something else
	| "Expired" -- the window passed

-- What one player is told (message kind "Rematch").
export type Status = {
	matchId: string, -- the finished match
	state: State,
	untilAt: number?, -- server time the window closes (Open, Waiting, Asked)
}

export type Offer = {
	matchId: string,
	players: { string }, -- the human players, seat order
	vsBot: boolean,
	untilAt: number, -- server time
	asked: { [string]: boolean },
	gone: { [string]: boolean },
	started: boolean,
}

-- Why a rematch tap is turned down.
Rematch.Reason = table.freeze({
	NotYours = "NoRematch", -- no such finished match for this player
	Expired = "RematchExpired",
	Gone = "OpponentLeft",
})

function Rematch.new(matchId: string, players: { string }, vsBot: boolean, now: number, window: number): Offer
	return {
		matchId = matchId,
		players = table.clone(players),
		vsBot = vsBot,
		untilAt = now + window,
		asked = {},
		gone = {},
		started = false,
	}
end

local function isPlayer(offer: Offer, id: string): boolean
	return table.find(offer.players, id) ~= nil
end

-- Player `id` taps Rematch at `now`. Returns "Start" (start the new match now),
-- "Waiting" (noted; the opponent has not tapped yet) or nil and a reason code.
-- Against the bot there is no window: the player is right there.
function Rematch.ask(offer: Offer, id: string, now: number): (("Start" | "Waiting")?, string?)
	if not isPlayer(offer, id) or offer.started or offer.gone[id] then
		return nil, Rematch.Reason.NotYours
	end
	if offer.vsBot then
		offer.started = true
		return "Start", nil
	end
	for _, other in offer.players do
		if other ~= id and offer.gone[other] then
			return nil, Rematch.Reason.Gone
		end
	end
	if now > offer.untilAt then
		return nil, Rematch.Reason.Expired
	end
	offer.asked[id] = true
	for _, other in offer.players do
		if not offer.asked[other] then
			return "Waiting", nil
		end
	end
	offer.started = true
	return "Start", nil
end

-- Player `id` left the server or started something else. Returns true if
-- that changed the offer (the others should be told).
function Rematch.leave(offer: Offer, id: string): boolean
	if not isPlayer(offer, id) or offer.gone[id] or offer.started then
		return false
	end
	offer.gone[id] = true
	return true
end

-- True once nothing can happen with the offer any more (it can be dropped).
function Rematch.closed(offer: Offer, now: number): boolean
	if offer.started then
		return true
	end
	if offer.vsBot then
		return offer.gone[offer.players[1]] == true
	end
	if now > offer.untilAt then
		return true
	end
	for _, id in offer.players do
		if not offer.gone[id] then
			return false
		end
	end
	return true
end

-- What player `id` sees.
function Rematch.status(offer: Offer, id: string, now: number): Status
	local state: State = "Open"
	if offer.started then
		state = "Started"
	elseif offer.vsBot then
		state = "Open"
	else
		local otherGone, otherAsked = false, false
		for _, other in offer.players do
			if other ~= id then
				otherGone = otherGone or offer.gone[other] == true
				otherAsked = otherAsked or offer.asked[other] == true
			end
		end
		if otherGone then
			state = "Gone"
		elseif now > offer.untilAt then
			state = "Expired"
		elseif offer.asked[id] then
			state = "Waiting"
		elseif otherAsked then
			state = "Asked"
		end
	end
	local live = state == "Open" or state == "Waiting" or state == "Asked"
	return {
		matchId = offer.matchId,
		state = state,
		untilAt = if live and not offer.vsBot then offer.untilAt else nil,
	}
end

return table.freeze(Rematch)
