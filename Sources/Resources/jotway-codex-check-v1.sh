#!/bin/bash
# Read-only installation probe. Never invoke Codex or read its credentials/configuration.
set -u
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
codex_executable=$(command -v codex 2>/dev/null) || codex_executable=''
if [ -n "$codex_executable" ] && [ -f "$codex_executable" ] && [ -x "$codex_executable" ]; then
    printf '%s\n' 'jotway-codex-check-v1 present'
else
    printf '%s\n' 'jotway-codex-check-v1 missing'
fi
