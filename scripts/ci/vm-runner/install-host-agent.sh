#!/usr/bin/env bash
# ABOUTME: Installs (or with --uninstall removes) a launchd agent per slot that keeps host-loop.sh running,
# ABOUTME: so the Mac serves CI jobs whenever it is awake and logged in.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LABEL_PREFIX="com.mirroir.vm-runner.slot"
AGENTS="$HOME/Library/LaunchAgents"
SLOTS="${VM_RUNNER_SLOTS:-1}"

if [[ "${1:-}" == "--uninstall" ]]; then
    for plist in "$AGENTS/$LABEL_PREFIX".*.plist; do
        [[ -e "$plist" ]] || continue
        launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || true
        rm "$plist"
        echo "removed $(basename "$plist")"
    done
    exit 0
fi

: "${VM_RUNNER_REPO:?set VM_RUNNER_REPO to owner/repo}"
# launchd starts agents with a bare PATH; tart, gh and jq must be found.
for tool in tart gh jq; do
    command -v "$tool" >/dev/null || { echo "$tool is not on PATH" >&2; exit 1; }
done
TOOL_PATH="$(dirname "$(command -v tart)"):$(dirname "$(command -v gh)"):$(dirname "$(command -v jq)"):/usr/bin:/bin:/usr/sbin:/sbin"

mkdir -p "$AGENTS" "$HOME/Library/Logs"
for slot in $(seq 1 "$SLOTS"); do
    label="$LABEL_PREFIX.$slot"
    plist="$AGENTS/$label.plist"
    cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$HERE/host-loop.sh</string>
        <string>--slot</string>
        <string>$slot</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$TOOL_PATH</string>
        <key>VM_RUNNER_REPO</key>
        <string>$VM_RUNNER_REPO</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/mirroir-vm-runner.$slot.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/mirroir-vm-runner.$slot.log</string>
</dict>
</plist>
EOF
    launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$plist"
    echo "started $label (log: ~/Library/Logs/mirroir-vm-runner.$slot.log)"
done
