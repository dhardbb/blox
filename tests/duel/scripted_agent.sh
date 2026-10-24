#!/usr/bin/env bash
# A dumb scripted agent, used to prove the duel protocol end to end (and as a
# template): selects a fixed candidate, drafts the first two legal states listed,
# then passes every week; a stance step (D-044) and a debate round (D-072) send
# their first "Example:" line.
#   tests/duel/scripted_agent.sh DIR N [candidate] [pass|example]
# In "example" mode each Plan week sends the first "Example:" plan line of the
# screen instead of "pass" (which also checks that the screen's examples are valid).
here="$(cd "$(dirname "$0")" && pwd)"
dir="${1:?usage: scripted_agent.sh DIR N [candidate]}"
n="${2:?usage: scripted_agent.sh DIR N [candidate]}"
# Candidates are unique (D-048): by default player 1 is Okafor, player 2 Hale.
if [ "$n" = 1 ]; then default=okafor; else default=hale; fi
candidate="${3:-$default}"
mode="${4:-pass}"
while true; do
	screen="$("$here/wait.sh" "$dir" "$n")"
	if printf '%s\n' "$screen" | head -1 | grep -q '^MATCH OVER'; then
		echo "p$n: match over"
		exit 0
	fi
	action="$(printf '%s\n' "$screen" | sed -n 's/^ACTION NEEDED: \([^.]*\)\..*/\1/p' | head -1)"
	case "$action" in
	Select*) cmd="select $candidate jobs health schools" ;;
	Draft*)
		states="$(printf '%s\n' "$screen" | awk '/^Your platform:/{f=1;next} f&&/^  [A-Z][A-Z]/{gsub(/\*/,"",$1);print $1} /^$/{f=0}' | head -2 | tr '\n' ' ')"
		cmd="draft $states"
		;;
	*Decision* | *Debate*)
		# A stance step (D-044) or a debate round (D-072): its first example.
		cmd="$(printf '%s\n' "$screen" | sed -n 's/^Example:   //p' | head -1)"
		;;
	*)
		cmd="pass"
		if [ "$mode" = example ]; then
			cmd="$(printf '%s\n' "$screen" | sed -n 's/^Example:   //p' | head -1)"
		fi
		;;
	esac
	echo "p$n [$action] -> $cmd"
	"$here/send.sh" "$dir" "$n" "$cmd" | head -3
done
