#!/bin/bash
# um80.sh — convenience wrapper to invoke um80 (MACRO-80 compatible Z-80/8080
# assembler) regardless of $PATH quirks. See z80tool.sh for details.
#
# Usage:
#   tools/um80.sh <args to um80...>
#
# Examples:
#   tools/um80.sh forth/camel80.azm -g -l forth/camel80.prn
#   tools/um80.sh forth/camel80.azm -D CPM -o /tmp/camel80cpm.rel -l /tmp/camel80cpm.prn
#
# Run `tools/um80.sh --help` for um80's own option list.

set -euo pipefail
TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$TOOLS_DIR/z80tool.sh" um80 "$@"
