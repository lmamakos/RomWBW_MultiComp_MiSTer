#!/bin/bash
# quartus_build.sh — wrapper script to invoke Quartus compilation via SSH+Docker on tycho
#
# Usage:
#   ./quartus_build.sh [quartus_sh options]
#
# Examples:
#   ./quartus_build.sh --flow compile MultiComp -c MultiComp
#     (builds the entire project)
#
#   ./quartus_build.sh --flow compile_synthesis MultiComp -c MultiComp
#     (runs only analysis & synthesis, skipping place & route)
#
#   ./quartus_build.sh -t MultiComp
#     (queries current timing for the compiled design)
#
# Environment:
#   - Connects via SSH to the host 'tycho' (assumed to be in ~/.ssh/config or resolvable)
#   - Runs Docker container: ghcr.io/raetro/quartus:17.0
#   - Project root on tycho: Projects/z80fp/RomWBW_MultiComp_MiSTer
#   - Mounts current directory into /build inside the container
#
# Notes:
#   - The working directory for this script should be the project root
#     (where MultiComp.qpf and MultiComp.qsf reside).
#   - All output files are written back to the local project directory
#     after the container exits.
#   - This script requires SSH access to 'tycho' and Docker to be installed/configured there.

set -euo pipefail

# Validate we're in the project root
if [[ ! -f "MultiComp.qpf" || ! -f "MultiComp.qsf" ]]; then
    echo "Error: MultiComp.qpf and MultiComp.qsf not found in current directory."
    echo "Please run this script from the project root directory."
    exit 1
fi

# Build the full command to be executed on tycho
# The script passes all arguments to quartus_sh
cmd="cd Projects/z80fp/RomWBW_MultiComp_MiSTer && docker run -it --rm -v .:/build ghcr.io/raetro/quartus:17.0 quartus_sh $*"

echo "Invoking Quartus on tycho via Docker..."
echo "Command: $cmd"
echo ""

# Execute via SSH
ssh tycho "$cmd"
