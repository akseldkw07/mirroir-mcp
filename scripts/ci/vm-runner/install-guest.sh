#!/bin/bash
# ABOUTME: Runs once inside the image VM (build-image.sh calls it through tart exec): installs the pinned
# ABOUTME: GitHub Actions runner and the login agent that runs one job per boot.

set -euo pipefail

RUNNER_VERSION="2.338.2"
RUNNER_SHA256="25a065af409ffa317ab4d5a3b614dd15fc9c40f2172bc1b35a1b1258e919a388"
RUNNER_TARBALL="actions-runner-osx-arm64-$RUNNER_VERSION.tar.gz"
SETUP_DIR="/Volumes/My Shared Files/setup"
AGENT_LABEL="com.mirroir.vm-runner.guest"

mkdir -p "$HOME/actions-runner" "$HOME/vm-runner" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"

cd "$HOME/actions-runner"
curl -fsSL -o "$RUNNER_TARBALL" \
    "https://github.com/actions/runner/releases/download/v$RUNNER_VERSION/$RUNNER_TARBALL"
echo "$RUNNER_SHA256  $RUNNER_TARBALL" | shasum -a 256 -c -
tar -xzf "$RUNNER_TARBALL"
rm "$RUNNER_TARBALL"

install -m 755 "$SETUP_DIR/guest-agent.sh" "$HOME/vm-runner/guest-agent.sh"

cat > "$HOME/Library/LaunchAgents/$AGENT_LABEL.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$AGENT_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$HOME/vm-runner/guest-agent.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/vm-runner.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/vm-runner.log</string>
</dict>
</plist>
EOF

echo "runner $RUNNER_VERSION and $AGENT_LABEL installed"
