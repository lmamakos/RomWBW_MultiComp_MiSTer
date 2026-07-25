#!/bin/bash
# build.sh — convenience wrapper for common Quartus build targets
#
# Usage:
#   ./build.sh [target]
#
# Targets:
#   full       Build the entire project (analysis, synthesis, place & route) [default]
#   synth      Run only analysis & synthesis (skip place & route)
#   help       Display this help message
#   <other>    Pass directly to quartus_build.sh (for custom arguments)
#
# Examples:
#   ./build.sh              # Full compile
#   ./build.sh synth        # Synthesis only
#   ./build.sh help         # Show Quartus help
#
# The output .rbf file will be written to output_files/MultiComp.rbf

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
QUARTUS_BUILD="$PROJECT_ROOT/quartus_build.sh"

# Validate that quartus_build.sh exists
if [[ ! -x "$QUARTUS_BUILD" ]]; then
    echo "Error: $QUARTUS_BUILD not found or not executable."
    echo "Please ensure quartus_build.sh is in the same directory as this script."
    exit 1
fi

# Parse target (default to 'full')
TARGET="${1:-full}"

case "$TARGET" in
    full)
        echo "Building entire project (analysis, synthesis, place & route)..."
        "$QUARTUS_BUILD" --flow compile MultiComp -c MultiComp
        ;;
    synth)
        echo "Running analysis & synthesis only (skipping place & route)..."
        "$QUARTUS_BUILD" --flow compile_synthesis MultiComp -c MultiComp
        ;;
    help)
        echo "Usage: $0 [target]"
        echo ""
        echo "Targets:"
        echo "  full       Build the entire project (analysis, synthesis, place & route) [default]"
        echo "  synth      Run only analysis & synthesis (skip place & route)"
        echo "  help       Display this help message"
        echo "  <other>    Pass directly to quartus_build.sh (for custom arguments)"
        echo ""
        echo "Examples:"
        echo "  $0              # Full compile"
        echo "  $0 synth        # Synthesis only"
        echo "  $0 help         # Show Quartus help"
        exit 0
        ;;
    *)
        # Pass unknown targets directly to quartus_build.sh
        echo "Passing target '$TARGET' directly to quartus_build.sh..."
        "$QUARTUS_BUILD" "$TARGET" "${@:2}"
        ;;
esac
