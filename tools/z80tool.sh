#!/bin/bash
# z80tool.sh — locate and invoke a tool from the um80_and_friends Z-80/8080
# assembler toolchain (um80, ul80, ud80, ux80, ulib80, ucref80), regardless
# of whether it happens to be first on $PATH.
#
# Usage:
#   tools/z80tool.sh <tool-name> [args...]
#
# Examples:
#   tools/z80tool.sh um80 camel80.azm -D CPM -g -o camel80.rel -l camel80.prn
#   tools/z80tool.sh ul80 -p 0 --sym -x -o camel80.hex camel80.rel
#   tools/z80tool.sh ud80 camel80.bin
#
# Why this exists:
#   `pip install --user um80` (or an editable checkout of
#   https://github.com/avwohl/um80_and_friends) can leave a *broken* shim in
#   ~/.local/bin (e.g. "ModuleNotFoundError: No module named 'um80'") ahead of
#   a working copy elsewhere on $PATH, such as a venv at
#   ~/um80_and_friends/bin. This script searches a list of candidate
#   locations, actually *runs* each candidate (`--version`) to confirm it
#   works rather than trusting $PATH order, and uses the first one that does.
#
# You normally don't need to call this script directly -- see um80.sh and
# ul80.sh for thin wrappers around the two most commonly used tools.

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <tool-name> [args...]" >&2
    echo "  tool-name: um80, ul80, ud80, ux80, ulib80, ucref80, ..." >&2
    exit 1
fi

TOOL="$1"
shift

# Candidate directories to search, in priority order, ahead of a plain
# `command -v` (PATH) lookup.
CANDIDATE_DIRS=(
    "${Z80TOOLS_BIN:-}"
    "$HOME/um80_and_friends/bin"
)

find_working_tool() {
    local name="$1" dir candidate

    for dir in "${CANDIDATE_DIRS[@]}"; do
        [[ -n "$dir" ]] || continue
        candidate="$dir/$name"
        if [[ -x "$candidate" ]] && "$candidate" --version >/dev/null 2>&1; then
            echo "$candidate"
            return 0
        fi
    done

    # Fall back to whatever's on $PATH, but only if it actually runs.
    if candidate=$(command -v "$name" 2>/dev/null) && \
       "$candidate" --version >/dev/null 2>&1; then
        echo "$candidate"
        return 0
    fi

    return 1
}

if TOOL_PATH=$(find_working_tool "$TOOL"); then
    exec "$TOOL_PATH" "$@"
fi

cat >&2 <<EOF
Error: could not find a working '$TOOL' from the um80_and_friends toolchain.

Checked:
  - \$Z80TOOLS_BIN/$TOOL  (if Z80TOOLS_BIN is set; currently: '${Z80TOOLS_BIN:-<unset>}')
  - $HOME/um80_and_friends/bin/$TOOL
  - '$TOOL' on \$PATH

Note: a stale/broken shim (e.g. from an old 'pip install --user um80') can
shadow a working copy on \$PATH -- this script runs '$TOOL --version' to
verify each candidate rather than trusting whichever comes first.

To install: pip install --break-system-packages um80
  (or clone https://github.com/avwohl/um80_and_friends and set up its venv;
  set Z80TOOLS_BIN to its bin/ directory if it's not at ~/um80_and_friends).
EOF
exit 1
