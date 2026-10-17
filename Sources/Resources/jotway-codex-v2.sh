#!/bin/bash
# Jotway Codex helper v2 — installed by the user in Application Scripts.
set -u
umask 077

task_directory=${1:-}
if [ "$#" -ne 1 ] || [[ "$task_directory" != /* ]] || [ ! -d "$task_directory" ]; then
    exit 64
fi
if [ -e "$task_directory/cancel" ]; then
    exit 130
fi

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
codex_executable=$(command -v codex) || exit 69
cd -- "$task_directory" || exit 73

# The app exchanges JSON-RPC on these pipes. EOF shuts down the server after one turn.
exec 3<&0
"$codex_executable" app-server --listen stdio:// \
    -c 'approval_policy="never"' -c 'sandbox_mode="workspace-write"' <&3 &
codex_pid=$!
exec 3<&-

trap 'kill -TERM "$codex_pid" 2>/dev/null || true' TERM INT HUP
(
    while kill -0 "$codex_pid" 2>/dev/null; do
        if [ -e "$task_directory/cancel" ]; then
            kill -TERM "$codex_pid" 2>/dev/null || true
            exit
        fi
        sleep 1
    done
) &
watcher_pid=$!

wait "$codex_pid"
task_status=$?
kill "$watcher_pid" 2>/dev/null || true
wait "$watcher_pid" 2>/dev/null || true
exit "$task_status"
