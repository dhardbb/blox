#!/usr/bin/env bash
# Installs the pinned toolchain from rokit.toml.
# Prefers rokit (fast, GitHub releases). If GitHub release downloads are
# blocked (as in some cloud sandboxes), builds the same versions from
# crates.io with cargo instead. luau-lsp is not on crates.io; CI runs it.
set -euo pipefail
cd "$(dirname "$0")/.."

if command -v rokit >/dev/null 2>&1 && rokit install --no-trust-check; then
	echo "Toolchain installed with rokit."
	exit 0
fi

version_of() {
	sed -n "s/^$1 = \".*@\(.*\)\"/\1/p" rokit.toml
}

if ! command -v cargo >/dev/null 2>&1; then
	echo "Neither rokit nor cargo is available. Install rokit: https://github.com/rojo-rbx/rokit" >&2
	exit 1
fi

for tool in rojo lune stylua selene; do
	want="$(version_of "$tool")"
	if command -v "$tool" >/dev/null 2>&1 && "$tool" --version | grep -q "$want" \
		&& { [ "$tool" != stylua ] || stylua --help | grep -q Luau; }; then
		echo "$tool $want already installed."
	else
		echo "Building $tool $want from crates.io..."
		if [ "$tool" = stylua ]; then
			# Release binaries include Luau syntax; the crates.io default build does not.
			cargo install --locked --force "$tool@$want" --features luau
		else
			cargo install --locked "$tool@$want"
		fi
	fi
done
echo "Toolchain ready (luau-lsp runs in CI only)."
