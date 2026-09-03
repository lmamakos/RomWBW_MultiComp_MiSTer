#!/bin/bash
# z80asm.sh — assemble + link + flatten a MACRO-80 style (.azm/.mac) Z-80
# source file into a plain binary image, in one step.
#
# This is the same three-step recipe forth/Makefile uses to build
# camel80.bin (um80 -> ul80 -> objcopy), generalized as a standalone tool so
# it can be used for one-off/exploratory builds (e.g. `-D` variants for
# testing) without editing a Makefile.
#
# Usage:
#   tools/z80asm.sh [-D SYM[=VAL]]... [-o OUTBASE] [-k] <input.azm>
#
# Options:
#   -D SYM[=VAL]   Define a symbol for um80 (repeatable), e.g. -D CPM
#   -o OUTBASE     Base path/name for output files (default: <input> minus
#                  its extension, e.g. forth/camel80.azm -> forth/camel80)
#   -k, --keep     Keep the intermediate .rel and .hex files (default: they
#                  are removed after use, matching forth/Makefile's recipe)
#
# Always produced:
#   <OUTBASE>.prn   assembly listing (with -g, so ul80's symbol file below
#                   includes every symbol, not just PUBLICs)
#   <OUTBASE>.sym   "ADDR NAME" symbol table (one per line)
#   <OUTBASE>.bin   flat binary image, linked at address 0 (-p 0)
#
# Examples:
#   tools/z80asm.sh forth/camel80.azm
#   tools/z80asm.sh -D CPM -o /tmp/camel80cpm forth/camel80.azm
#
# See also: tools/um80.sh, tools/ul80.sh (thin wrappers for direct,
# lower-level invocation), tools/z80tool.sh (toolchain locator).

set -euo pipefail

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UM80=("$TOOLS_DIR/z80tool.sh" um80)
UL80=("$TOOLS_DIR/z80tool.sh" ul80)

DEFINES=()
OUTBASE=""
KEEP=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -D)
            DEFINES+=(-D "$2")
            shift 2
            ;;
        -o)
            OUTBASE="$2"
            shift 2
            ;;
        -k|--keep)
            KEEP=1
            shift
            ;;
        -h|--help)
            sed -n '2,31p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "Error: unknown option '$1'" >&2
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 [-D SYM[=VAL]]... [-o OUTBASE] [-k] <input.azm>" >&2
    exit 1
fi

INPUT="$1"
if [[ ! -f "$INPUT" ]]; then
    echo "Error: input file '$INPUT' not found" >&2
    exit 1
fi

if [[ -z "$OUTBASE" ]]; then
    OUTBASE="${INPUT%.*}"
fi

REL="$OUTBASE.rel"
PRN="$OUTBASE.prn"
HEX="$OUTBASE.hex"
SYM="$OUTBASE.sym"
BIN="$OUTBASE.bin"

echo "Assembling $INPUT -> $REL (listing: $PRN)"
"${UM80[@]}" "$INPUT" "${DEFINES[@]}" -g -o "$REL" -l "$PRN"

echo "Linking $REL -> $HEX (symbols: $SYM)"
"${UL80[@]}" -p 0 --sym -x -o "$HEX" "$REL"

echo "Flattening $HEX -> $BIN"
objcopy -I ihex -O binary "$HEX" "$BIN"

if [[ "$KEEP" -eq 0 ]]; then
    rm -f "$REL" "$HEX"
else
    echo "Keeping intermediates: $REL $HEX"
fi

echo "Done: $PRN $SYM $BIN"
