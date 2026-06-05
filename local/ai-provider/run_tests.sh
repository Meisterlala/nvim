#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

nvim --headless --noplugin \
  -u local/ai-provider/tests/minimal_init.lua \
  -c "PlenaryBustedDirectory local/ai-provider/tests/ai_provider { minimal_init = 'local/ai-provider/tests/minimal_init.lua' }"
