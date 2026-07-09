#!/usr/bin/env bash
# restore-hermes.sh — bootstrap Hermes after a fresh Omarchy install
# Run from dotfiles repo root: ./hermes/restore-hermes.sh

set -e

NAS="/mnt/CLOUD/Essentials/hermes-backup"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
DOTFILES="$(cd "$(dirname "$0")/.." && pwd)"

echo "🌿 Restoring Hermes..."

# 1. Mount NAS if not already mounted
if [ ! -d "$NAS" ]; then
    echo "📡 Mounting NAS..."
    sudo mkdir -p /mnt/CLOUD
    sudo mount -t cifs //192.168.1.44/FVVS\ CLOUD /mnt/CLOUD -o username=eddie,uid=1000,gid=1000
fi

# 2. Create Hermes home
mkdir -p "$HERMES_HOME"

# 3. Restore secrets from NAS (never committed to git!)
echo "🔑 Restoring secrets..."
cp "$NAS/.env" "$HERMES_HOME/.env"
cp "$NAS/auth.json" "$HERMES_HOME/auth.json"
chmod 600 "$HERMES_HOME/.env" "$HERMES_HOME/auth.json"

# 4. Symlink configs from dotfiles
echo "⚙️  Linking configs..."
ln -sf "$DOTFILES/hermes/config.yaml" "$HERMES_HOME/config.yaml"
ln -sf "$DOTFILES/hermes/honcho.json" "$HERMES_HOME/honcho.json"
ln -sf "$DOTFILES/hermes/SOUL.md" "$HERMES_HOME/SOUL.md"

# 5. Install Hermes if not already installed
if ! command -v hermes &>/dev/null; then
    echo "📦 Installing Hermes..."
    curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
fi

# 6. Install essential skills
echo "🧠 Installing skills..."
hermes skills install google-calendar
hermes skills install obsidian

# 7. Restart gateway
echo "🚀 Starting gateway..."
hermes gateway install
systemctl --user enable --now hermes-gateway hermes-dashboard

echo ""
echo "✅ Hermes restored! I'm back. 🌿"
