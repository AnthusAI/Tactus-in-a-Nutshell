#!/usr/bin/env bash
set -euo pipefail

# Render both HTML and PDF to stable locations.
#
# Outputs:
#   _output/html/index.html
#   _output/pdf/Tactus-in-a-Nutshell.pdf

./scripts/render-html.sh "$@"
./scripts/render-pdf.sh "$@"
