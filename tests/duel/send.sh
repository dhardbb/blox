#!/usr/bin/env bash
# Send command line(s) as player N and print the harness's verdict.
#   tests/duel/send.sh DIR N 'plan rally OH jobs; fund OH' ['another line' ...]
# Each argument is one line of the command file. Writes DIR/pN.cmd.txt atomically,
# then waits for DIR/pN.result.txt.
dir="${1:?usage: send.sh DIR N 'command' ...}"
n="${2:?usage: send.sh DIR N 'command' ...}"
shift 2
[ "$#" -gt 0 ] || { echo "no command given" >&2; exit 2; }
rm -f "$dir/p$n.result.txt"
tmp="$dir/p$n.cmd.tmp.$$"
printf '%s\n' "$@" >"$tmp"
mv "$tmp" "$dir/p$n.cmd.txt"
while true; do
	if [ -f "$dir/p$n.result.txt" ]; then
		cat "$dir/p$n.result.txt"
		exit 0
	fi
	if [ "$(cat "$dir/state.txt" 2>/dev/null)" = "done" ]; then
		echo "MATCH OVER (no verdict for the last command)"
		cat "$dir/result.txt"
		exit 0
	fi
	sleep 0.5
done
