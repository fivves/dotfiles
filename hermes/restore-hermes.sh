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
    sudo mount -t cifs //192.168.1.44/FVVS\\ CLOUD /mnt/CLOUD -o username=eddie,uid=1000,gid=1000
fi

# 2. Create Hermes home
mkdir -p "$HERMES_HOME"

# 3. Restore secrets + memories from NAS
echo "🔑 Restoring secrets..."
cp "$NAS/.env" "$HERMES_HOME/.env"
cp "$NAS/auth.json" "$HERMES_HOME/auth.json"
chmod 600 "$HERMES_HOME/.env" "$HERMES_HOME/auth.json"

echo "🧠 Restoring memories..."
mkdir -p "$HERMES_HOME/memories"
cp "$NAS/MEMORY.md" "$HERMES_HOME/memories/MEMORY.md"
cp "$NAS/USER.md" "$HERMES_HOME/memories/USER.md"

# 4. Restore sessions database
echo "💬 Restoring sessions..."
cp "$NAS/state.db" "$HERMES_HOME/state.db"

# 5. Restore scripts
echo "📜 Restoring scripts..."
mkdir -p "$HERMES_HOME/scripts"
cp -r "$NAS/scripts/"* "$HERMES_HOME/scripts/"

# 6. Restore skills (all 27 skill directories)
echo "🎯 Restoring skills..."
mkdir -p "$HERMES_HOME/skills"
cp -r "$NAS/skills/"* "$HERMES_HOME/skills/"

# 7. Restore game state
echo "🎮 Restoring game state..."
mkdir -p "$HERMES_HOME/game-state"
cp -r "$NAS/game-state/"* "$HERMES_HOME/game-state/" 2>/dev/null || true

# 8. Symlink configs from dotfiles
echo "⚙️  Linking configs..."
ln -sf "$DOTFILES/hermes/config.yaml" "$HERMES_HOME/config.yaml"
ln -sf "$DOTFILES/hermes/honcho.json" "$HERMES_HOME/honcho.json"
ln -sf "$DOTFILES/hermes/SOUL.md" "$HERMES_HOME/SOUL.md"

# 9. Install Hermes if not already installed
if ! command -v hermes &>/dev/null; then
    echo "📦 Installing Hermes..."
    curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
fi

# 10. Restore cron jobs
echo "⏰ Restoring cron jobs..."
mkdir -p "$HERMES_HOME/cron"
cp "$NAS/cron-jobs.json" "$HERMES_HOME/cron/jobs.json"
# 10. Restart gateway
echo "🚀 Starting gateway..."
hermes gateway install
systemctl --user enable --now hermes-gateway hermes-dashboard

echo ""
echo "✅ Hermes restored! Scripts, skills, memories, sessions, game state — everything."
echo "   Cron jobs may need to be recreated if they don't survive the state.db restore."
