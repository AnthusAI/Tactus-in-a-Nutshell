#!/usr/bin/env bash
set -euo pipefail

# Render PDF to a stable location (doesn't wipe HTML output).
#
# Output:
#   _output/pdf/Tactus-in-a-Nutshell.pdf

quarto render --to pdf --output-dir _output/pdf "$@"

