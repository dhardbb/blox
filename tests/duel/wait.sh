#!/usr/bin/env bash
# Block until player N has a NEW screen (or the match is over), then print it.
#   tests/duel/wait.sh DIR N
# "New" means its "TURN: k" line differs from the last one this script printed for
# that player (remembered in DIR/.pN.seen). After a match ends it prints result.txt.
# `cat DIR/pN.screen.txt` re-reads the current screen without waiting.
dir="${1:?usage: wait.sh DIR N}"
n="${2:?usage: wait.sh DIR N}"
seen="$dir/.p$n.seen"
last="$(cat "$seen" 2>/dev/null || echo 0)"
while true; do
	if [ "$(cat "$dir/state.txt" 2>/dev/null)" = "done" ] && [ -f "$dir/result.txt" ]; then
		echo "MATCH OVER"
		cat "$dir/result.txt"
		exit 0
	fi
	if text="$(cat "$dir/p$n.screen.txt" 2>/dev/null)" && [ -n "$text" ]; then
		turn="$(printf '%s\n' "$text" | sed -n 's/^TURN: //p' | head -1)"
		if [ -n "$turn" ] && [ "$turn" != "$last" ]; then
			echo "$turn" >"$seen"
			printf '%s\n' "$text"
			exit 0
		fi
	fi
	sleep 1
done
