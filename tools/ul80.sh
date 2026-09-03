#!/bin/bash
# ul80.sh — convenience wrapper to invoke ul80 (MACRO-80/LINK-80 compatible
# Z-80/8080 linker) regardless of $PATH quirks. See z80tool.sh for details.
#
# Usage:
#   tools/ul80.sh <args to ul80...>
#
# Examples:
#   tools/ul80.sh -p 0 --sym -x -o forth/camel80.hex forth/camel80.rel
#
# Run `tools/ul80.sh --help` for ul80's own option list.

set -euo pipefail
TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$TOOLS_DIR/z80tool.sh" ul80 "$@"
