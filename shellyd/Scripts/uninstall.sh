#!/bin/bash
#
# Shelly Daemon Uninstall Script
#

INSTALL_DIR="/usr/local/bin"
LAUNCHD_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.shelly.daemon.plist"

echo "🐚 Shelly Daemon Uninstaller"
echo "============================"
echo ""

# Stop the daemon
echo "🛑 Stopping daemon..."
launchctl unload "$LAUNCHD_DIR/$PLIST_NAME" 2>/dev/null || true
pkill -x shellyd 2>/dev/null || true

# Remove launchd plist
if [ -f "$LAUNCHD_DIR/$PLIST_NAME" ]; then
    rm "$LAUNCHD_DIR/$PLIST_NAME"
    echo "   Removed launchd plist"
fi

# Remove binary
if [ -f "$INSTALL_DIR/shellyd" ]; then
    sudo rm "$INSTALL_DIR/shellyd"
    echo "   Removed binary"
fi

echo ""
echo "✅ Shelly daemon uninstalled!"
echo ""
echo "📝 Note: Config and keys at ~/.shellyd/ were NOT removed."
echo "   Delete manually if needed: rm -rf ~/.shellyd"
