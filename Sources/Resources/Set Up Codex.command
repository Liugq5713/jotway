#!/bin/bash
set -eu
umask 077

source_directory=$(cd -- "$(dirname -- "$0")" && pwd)
source_helper="$source_directory/jotway-codex-v2.sh"
account_home=$(/usr/bin/dscl . -read "/Users/$(/usr/bin/id -un)" NFSHomeDirectory | /usr/bin/sed 's/^NFSHomeDirectory: //')
[ -n "$account_home" ] || { echo "Cannot resolve account home." >&2; exit 1; }
target_directory="$account_home/Library/Application Scripts/com.liuguangqi.jotway"
target_helper="$target_directory/jotway-codex-v2.sh"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

source_probe="$source_directory/jotway-codex-check-v1.sh"
target_probe="$target_directory/jotway-codex-check-v1.sh"
mkdir -p -- "$target_directory"
# Check both destinations before changing either script; never replace different content.
for name in jotway-codex-check-v1.sh jotway-codex-v2.sh; do
    if { [ -e "$target_directory/$name" ] || [ -L "$target_directory/$name" ]; } && { [ -L "$target_directory/$name" ] || ! cmp -s -- "$source_directory/$name" "$target_directory/$name"; }; then
        printf '%s\n' 'A different Codex script already exists. It was left unchanged:' "$target_directory/$name"
        exit 1
    fi
done
if [ ! -e "$target_probe" ]; then
    cp -- "$source_probe" "$target_probe"
fi
chmod 700 "$target_probe"

codex_executable=$(command -v codex) || codex_executable=''
if [ -z "$codex_executable" ] || [ ! -f "$codex_executable" ] || [ ! -x "$codex_executable" ]; then
    printf '%s\n' 'The read-only check is installed. Install Codex CLI first, then run this setup again.'
    exit 1
fi
if ! "$codex_executable" login status >/dev/null 2>&1; then
    printf '%s\n' 'The read-only check is installed. Sign in with codex login, then run this setup again.'
    exit 1
fi
if [ ! -e "$target_helper" ]; then
    cp -- "$source_helper" "$target_helper"
fi
chmod 700 "$target_helper"
printf '%s\n' 'Codex scripts are installed. Return to Jotway and check setup, then choose Run with Codex from the target menu, write a task, and press Enter.'
