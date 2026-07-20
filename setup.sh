#!/usr/bin/env bash
#
# Scheduled — one-shot setup: verify toolchain, build the .app bundle,
# optionally store the OpenRouter key, install a `scheduled` CLI shim, and
# launch the app so macOS prompts for Calendar/Reminders permissions.
#
set -euo pipefail

BOLD="$(tput bold 2>/dev/null || true)"; RESET="$(tput sgr0 2>/dev/null || true)"
say() { echo "${BOLD}==>${RESET} $*"; }

cd "$(dirname "$0")"

# 1. Toolchain check ---------------------------------------------------------
if ! command -v swift >/dev/null 2>&1; then
  echo "Swift not found. Install the Xcode Command Line Tools:  xcode-select --install"
  exit 1
fi
say "Swift: $(swift --version 2>/dev/null | head -1)"

# 2. Build -------------------------------------------------------------------
say "Building release bundle…"
make bundle

APP="dist/Scheduled.app"
BIN="$APP/Contents/MacOS/Scheduled"

# 3. API key (optional) ------------------------------------------------------
if [ -n "${OPENROUTER_API_KEY:-}" ]; then
  say "Storing OPENROUTER_API_KEY from environment into the login Keychain…"
  security add-generic-password \
    -a "OPENROUTER_API_KEY" -s "com.scheduled.app" \
    -w "$OPENROUTER_API_KEY" -U >/dev/null 2>&1 || true
else
  echo "  (No OPENROUTER_API_KEY in env — set it later in the app's Settings."
  echo "   Or: export OPENROUTER_API_KEY=sk-or-... before running.)"
fi

# 4. CLI shim ----------------------------------------------------------------
SHIM_DIR="$HOME/.local/bin"
mkdir -p "$SHIM_DIR"
SHIM="$SHIM_DIR/scheduled"
cat > "$SHIM" <<EOF
#!/usr/bin/env bash
exec "$(pwd)/$BIN" "\$@"
EOF
chmod +x "$SHIM"
say "Installed CLI shim: $SHIM"
case ":$PATH:" in
  *":$SHIM_DIR:"*) : ;;
  *) echo "  Add to PATH:  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

# 5. Launch ------------------------------------------------------------------
say "Launching Scheduled (grant Calendar + Reminders when prompted)…"
open "$APP"

cat <<EOF

${BOLD}Done.${RESET}
  • Menu-bar icon (calendar) → click to capture, right-click for menu.
  • Global hotkey: ⌘⌥Space
  • CLI:  scheduled "gym everyday at 6am"
  • Settings → paste your OpenRouter API key if you didn't set the env var.
EOF
