#!/usr/bin/env bash
set -euo pipefail

# Stable Quarto preview URL (no random port churn).
#
# Usage:
#   ./scripts/preview-book.sh
#
# Then open:
#   http://127.0.0.1:4444

quarto preview --port 4444 --no-browser "$@"

