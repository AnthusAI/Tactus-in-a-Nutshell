#!/usr/bin/env bash
set -euo pipefail

# Render HTML to a stable location you can open directly.
#
# Output:
#   _output/html/index.html

quarto render --to html --output-dir _output/html "$@"

