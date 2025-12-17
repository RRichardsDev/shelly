#!/bin/bash
#
# Shelly Daemon Installation Script
# Installs shellyd and sets up launchd for auto-start
#

set -e

INSTALL_DIR="/usr/local/bin"
LAUNCHD_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.shelly.daemon.plist"
CONFIG_DIR="$HOME/.shellyd"

echo "🐚 Shelly Daemon Installer"
echo "=========================="
echo ""

# Check if running as root (we don't want that)
if [ "$EUID" -eq 0 ]; then
    echo "❌ Please don't run this script as root."
    echo "   Run it as your regular user."
    exit 1
fi

# Find the shellyd binary
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$PROJECT_DIR/.build/release/shellyd" ]; then
    BINARY="$PROJECT_DIR/.build/release/shellyd"
elif [ -f "$PROJECT_DIR/.build/debug/shellyd" ]; then
    echo "⚠️  Using debug build. Run 'swift build -c release' for production."
    BINARY="$PROJECT_DIR/.build/debug/shellyd"
else
    echo "📦 Building shellyd in release mode..."
    cd "$PROJECT_DIR"
    swift build -c release
    BINARY="$PROJECT_DIR/.build/release/shellyd"
fi

echo "📁 Installing to $INSTALL_DIR..."
sudo cp "$BINARY" "$INSTALL_DIR/shellyd"
sudo chmod +x "$INSTALL_DIR/shellyd"

# Create config directory
echo "⚙️  Creating config directory..."
mkdir -p "$CONFIG_DIR"

# Create default config if it doesn't exist
if [ ! -f "$CONFIG_DIR/config.json" ]; then
    cat > "$CONFIG_DIR/config.json" << 'CONFIG'
{
    "port": 8765,
    "shell": "/bin/zsh",
    "verbose": false
}
CONFIG
    echo "   Created default config at $CONFIG_DIR/config.json"
fi

# Create authorized_keys file if it doesn't exist
if [ ! -f "$CONFIG_DIR/authorized_keys" ]; then
    touch "$CONFIG_DIR/authorized_keys"
    chmod 600 "$CONFIG_DIR/authorized_keys"
    echo "   Created authorized_keys file"
fi

# Create launchd plist
echo "🚀 Setting up auto-start..."
mkdir -p "$LAUNCHD_DIR"

cat > "$LAUNCHD_DIR/$PLIST_NAME" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.shelly.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/shellyd</string>
        <string>start</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/shellyd.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/shellyd.error.log</string>
</dict>
</plist>
PLIST

# Load the launch agent
echo "▶️  Starting daemon..."
launchctl unload "$LAUNCHD_DIR/$PLIST_NAME" 2>/dev/null || true
launchctl load "$LAUNCHD_DIR/$PLIST_NAME"

# Verify it's running
sleep 2
if pgrep -x shellyd >/dev/null; then
    echo ""
    echo "✅ Shelly daemon installed and running!"
    echo ""
    echo "📍 Binary:  $INSTALL_DIR/shellyd"
    echo "⚙️  Config:  $CONFIG_DIR/config.json"
    echo "🔑 Keys:    $CONFIG_DIR/authorized_keys"
    echo "📝 Logs:    ~/Library/Logs/shellyd.log"
    echo ""
    echo "🔗 To pair with iOS app:"
    echo "   shellyd start --pairing"
    echo ""
    echo "🛑 To stop/uninstall:"
    echo "   ./uninstall.sh"
else
    echo ""
    echo "⚠️  Daemon installed but may not be running."
    echo "   Check logs: cat ~/Library/Logs/shellyd.error.log"
fi
