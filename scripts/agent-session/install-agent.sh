#!/bin/zsh
# Run this once, logged in as the agent user, in Terminal:
#   zsh /Users/Shared/backseat/install-agent.sh <uid of the main user>
# It makes backseat listen in this session for the main user's Claude.
set -e
allow=${1:?pass the main user's uid (run: id -u, as the main user)}
mkdir -p ~/Library/LaunchAgents
sed "s/__ALLOW_UID__/$allow/" /Users/Shared/backseat/dev.backseat.agent.plist > ~/Library/LaunchAgents/dev.backseat.agent.plist
launchctl bootout gui/$(id -u)/dev.backseat.agent 2>/dev/null || true
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/dev.backseat.agent.plist
sleep 1
ls -l /Users/Shared/backseat/agent.sock && echo "backseat is listening for uid $allow."
echo "Now grant /Users/Shared/backseat/backseat Accessibility and Screen Recording in System Settings > Privacy & Security (in this user)."
