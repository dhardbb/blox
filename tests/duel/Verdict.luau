--!strict
-- The duel harness's verdict rules, pure so tests/duel/Verdict.spec.luau can pin
-- them: which command lines are info only, what a command file that locked
-- nothing is called, and which state a refreshed screen previews.

local Commands = require("@shared/DebugUI/Commands")

export type Kind = "Info" | "Blocked" | "Move"

export type Outcome = {
	status: string, -- the STATUS line of pN.result.txt
	usesAttempt: boolean, -- counts against --attempts
	refresh: boolean, -- true: same TURN, REFRESH grows; false: a new TURN
}

local Verdict = {}

-- Lines that only print something (or are harmless no-ops in a duel). They never
-- lock you in and never use an attempt, at any stage, even when the server or the
-- parser turns them down ("show" without a state, "bank" at Select).
Verdict.INFO = table.freeze({
	show = true,
	help = true,
	rules = true,
	bank = true,
	resync = true,
	skip = true,
})

-- Lobby commands that would leave or break the match.
Verdict.BLOCKED = table.freeze({
	practice = true,
	queue = true,
	host = true,
	join = true,
	leave = true,
	pick = true,
	autoplay = true,
})

local function head(command: string): string
	return string.lower(string.match(command, "^%s*(%S+)") or "")
end

function Verdict.kind(command: string): Kind
	local word = head(command)
	if Verdict.INFO[word] then
		return "Info"
	elseif Verdict.BLOCKED[word] then
		return "Blocked"
	end
	return "Move"
end

-- The verdict on a command file that locked nothing. `rejectedAny` is true when a
-- move (not an info line) in it was turned down.
function Verdict.outcome(rejectedAny: boolean): Outcome
	if rejectedAny then
		return { status = "REJECTED: nothing locked", usesAttempt = true, refresh = false }
	end
	return {
		status = "INFO: not locked in yet, no attempt used (info only: same TURN, the screen was refreshed with the output)",
		usesAttempt = false,
		refresh = true,
	}
end

-- The state of the last valid "show ST" in a command file, or nil.
function Verdict.focus(commands: { string }): string?
	local found: string? = nil
	for _, command in commands do
		local parsed = Commands.parse(command)
		if parsed.kind == "Local" and parsed.action == "show" then
			found = parsed.arg
		end
	end
	return found
end

return table.freeze(Verdict)
