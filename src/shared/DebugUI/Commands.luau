--!strict
-- Parses the debug UI's command line into a request or a local action.
-- Phase 2 only: Phase 3 replaces typing with real screens.
--
--   practice | queue | host [noevents] | join CODE | leave | resync | bank | skip | help
--   pick CANDIDATE COLOR ISSUE ISSUE ISSUE     (pre-pick in the lobby)
--   select CANDIDATE COLOR ISSUE ISSUE ISSUE   (during Select)
--   draft STATE [STATE]
--   plan ACTION; ACTION; ...   with actions:
--     rally ST ISSUE | fund ST | ad ST ISSUE | attack ad ST ISSUE | poll ST
--     rpoll REGION | gotv ST UNITS | pivot DROP ADD | prep N N N
--     (aliases: fundraise = fund; media = ad; attack = attackad = attack ad,
--     so the player-facing names of D-030 work as typed)
--     choice attack|defend|ignore              (only in a week with a Choice event)
--   pass                                       (submit an empty plan)
--   auto | autoplay on|off | show ST | rules  (rules: the "How it works" text)

local Candidates = require("../Sim/Candidates")
local Issues = require("../Sim/Issues")

export type Parsed = {
	kind: "Request" | "Local" | "Error",
	op: string?, -- Request
	code: string?, -- Join
	events: boolean?, -- Host: false for "host noevents"
	pick: any?, -- PrePick
	input: any?, -- Submit
	action: string?, -- Local: "auto" | "autoplay" | "show" | "help" | "rules"
	arg: string?, -- Local argument
	message: string?, -- Error
}

local Commands = {}

local function words(text: string): { string }
	local out = {}
	for word in string.gmatch(text, "%S+") do
		table.insert(out, word)
	end
	return out
end

local function err(message: string): Parsed
	return { kind = "Error", message = message }
end

-- Case-insensitive issue name ("jobs", "transit", "FARMS") to its id.
function Commands.issue(word: string?): string?
	if word == nil then
		return nil
	end
	local lower = string.lower(word)
	for _, issue in Issues.list do
		if string.lower(issue) == lower then
			return issue
		end
	end
	return nil
end

local function region(word: string?): string?
	if word == nil then
		return nil
	end
	local lower = string.lower(word)
	for _, r in Issues.regions do
		if string.lower(r) == lower then
			return r
		end
	end
	return nil
end

local function candidate(word: string?): string?
	if word == nil then
		return nil
	end
	local lower = string.lower(word)
	for _, id in Candidates.ids do
		if id == lower then
			return id
		end
	end
	return nil
end

local function color(word: string?): string?
	if word == nil then
		return nil
	end
	local lower = string.lower(word)
	for _, c in Candidates.colors do
		if string.lower(c) == lower then
			return c
		end
	end
	return nil
end

local function selection(w: { string }): (any?, string?)
	local c = candidate(w[2])
	if c == nil then
		return nil, `unknown candidate; try: {table.concat(Candidates.ids, ", ")}`
	end
	local col = color(w[3])
	if col == nil then
		return nil, `unknown color; try: {table.concat(Candidates.colors, ", ")}`
	end
	local platform = {}
	for k = 4, 6 do
		local issue = Commands.issue(w[k])
		if issue == nil then
			return nil, `need three issues; try: {table.concat(Issues.list, ", ")}`
		end
		table.insert(platform, issue)
	end
	return { candidate = c, color = col, platform = platform }, nil
end

local function state(word: string?): string?
	if word == nil or not string.match(word, "^%a%a$") then
		return nil
	end
	return string.upper(word)
end

-- Command words for the player-facing action names (D-030: Rally, Fundraise, Ad,
-- Attack ad, ...), each to its canonical verb.
local VERBS: { [string]: string } = {
	fundraise = "fund",
	media = "ad",
	attackad = "attack",
}

-- One plan action, or an error message.
local function action(input: { string }): (any?, string?)
	local w = table.clone(input)
	local verb = string.lower(w[1] or "")
	verb = VERBS[verb] or verb
	if verb == "attack" and string.lower(w[2] or "") == "ad" then
		table.remove(w, 2) -- "attack ad OH Jobs"; no state is called AD
	end
	local st = state(w[2])
	if verb == "rally" or verb == "ad" or verb == "attack" then
		local issue = Commands.issue(w[3])
		local shown = if verb == "attack" then "attack ad" else verb
		if st == nil or issue == nil then
			return nil, `{shown} needs a state and an issue, e.g. "{shown} OH Jobs"`
		end
		local kind = if verb == "rally" then "Rally" elseif verb == "ad" then "Media" else "Attack"
		return { kind = kind, state = st, issue = issue }, nil
	elseif verb == "fund" or verb == "poll" then
		if st == nil then
			return nil, `{verb} needs a state, e.g. "{verb} OH"`
		end
		return { kind = if verb == "fund" then "Fundraise" else "Poll", state = st }, nil
	elseif verb == "rpoll" then
		local r = region(w[2])
		if r == nil then
			return nil, `rpoll needs a region; try: {table.concat(Issues.regions, ", ")}`
		end
		return { kind = "RegionPoll", region = r }, nil
	elseif verb == "gotv" then
		local units = tonumber(w[3] or "")
		if st == nil or units == nil then
			return nil, 'gotv needs a state and units, e.g. "gotv OH 2"'
		end
		return { kind = "Gotv", state = st, units = units }, nil
	elseif verb == "pivot" then
		local drop, add = Commands.issue(w[2]), Commands.issue(w[3])
		if drop == nil or add == nil then
			return nil, 'pivot needs two issues, e.g. "pivot Schools Farms"'
		end
		return { kind = "Pivot", drop = drop, add = add }, nil
	end
	return nil, `unknown action "{verb}"`
end

function Commands.parse(text: string): Parsed
	local w = words(text)
	local head = string.lower(w[1] or "")
	if head == "" then
		return err("type a command, or 'help'")
	end
	if head == "host" then
		local arg = string.lower(w[2] or "")
		if arg == "" then
			return { kind = "Request", op = "Host" }
		elseif arg == "noevents" then
			return { kind = "Request", op = "Host", events = false }
		end
		return err('host takes nothing or "noevents"')
	elseif head == "practice" or head == "queue" or head == "leave" or head == "resync" then
		return { kind = "Request", op = string.upper(string.sub(head, 1, 1)) .. string.sub(head, 2) }
	elseif head == "bank" or head == "skip" then
		return { kind = "Request", op = if head == "bank" then "Bank" else "Skip" }
	elseif head == "join" then
		local code = string.upper(w[2] or "")
		if not string.match(code, "^%w%w%w%w%w$") then
			return err('join needs a 5-character code, e.g. "join AB3CD"')
		end
		return { kind = "Request", op = "Join", code = code }
	elseif head == "pick" or head == "select" then
		local pick, message = selection(w)
		if pick == nil then
			return err(message :: string)
		end
		if head == "pick" then
			return { kind = "Request", op = "PrePick", pick = pick }
		end
		return { kind = "Request", op = "Submit", input = pick }
	elseif head == "draft" then
		local choices = {}
		for k = 2, math.min(#w, 3) do
			local st = state(w[k])
			if st == nil then
				return err('draft needs one or two state codes, e.g. "draft OH PA"')
			end
			table.insert(choices, st)
		end
		if #choices == 0 then
			return err('draft needs one or two state codes, e.g. "draft OH PA"')
		end
		return { kind = "Request", op = "Submit", input = { choices = choices } }
	elseif head == "pass" then
		return { kind = "Request", op = "Submit", input = { actions = {} } }
	elseif head == "plan" then
		local rest = string.sub(text, (string.find(text, "%S") :: number) + 4)
		local actions, prep, choice = {}, nil, nil
		for part in string.gmatch(rest, "[^;,]+") do
			local pw = words(part)
			if #pw > 0 then
				if string.lower(pw[1]) == "prep" then
					prep = {}
					for k = 2, #pw do
						table.insert(prep, tonumber(pw[k]) or -1)
					end
				elseif string.lower(pw[1]) == "choice" then
					local word = string.lower(pw[2] or "")
					if word ~= "attack" and word ~= "defend" and word ~= "ignore" then
						return err('choice needs attack, defend or ignore, e.g. "choice defend"')
					end
					choice = string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
				else
					local a, message = action(pw)
					if a == nil then
						return err(message :: string)
					end
					table.insert(actions, a)
				end
			end
		end
		return { kind = "Request", op = "Submit", input = { actions = actions, prep = prep, choice = choice } }
	elseif head == "auto" or head == "help" or head == "rules" then
		return { kind = "Local", action = head }
	elseif head == "autoplay" then
		local arg = string.lower(w[2] or "")
		if arg ~= "on" and arg ~= "off" then
			return err('autoplay needs "on" or "off"')
		end
		return { kind = "Local", action = "autoplay", arg = arg }
	elseif head == "show" then
		local st = state(w[2])
		if st == nil then
			return err('show needs a state code, e.g. "show OH"')
		end
		return { kind = "Local", action = "show", arg = st }
	end
	return err(`unknown command "{head}"; type 'help'`)
end

Commands.HELP = table.concat({
	"Lobby: practice | queue | host [noevents] | join CODE | leave | pick CANDIDATE COLOR ISSUE ISSUE ISSUE",
	"Select: select CANDIDATE COLOR ISSUE ISSUE ISSUE      Draft: draft OH PA",
	"Plan: plan rally OH Jobs; fund PA; ad MI Jobs; attack ad IA Farms; poll OH; rpoll Pacific;",
	"      gotv OH 2; pivot Schools Farms; prep 2 2 2; choice defend (Choice weeks)      pass = empty plan",
	"Any time: auto (bot fills this step) | autoplay on/off | bank | skip | show OH | rules | resync",
	"  show OH = a state's numbers and what each action does there; rules = how everything works",
}, "\n")

return table.freeze(Commands)
