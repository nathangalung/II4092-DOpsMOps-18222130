#!/usr/bin/env bash
# Bootstrap a portable Claude Code setup on a new machine.
# Run from inside this claude/ directory, OUTSIDE any active Claude Code session
# (Claude recreates ~/.claude mid-session, which breaks fresh symlinks).
#
# What it does:
#   1. Symlinks portable config (settings, CLAUDE.md, skills, commands, agents) into ~/.claude
#   2. Installs RTK (token-saving Bash proxy used by the PreToolUse hook in settings.json)
#   3. Registers plugin marketplaces + installs the curated plugin set
#   4. Registers the token-savior MCP server (user scope)
#
# Requirements: bash, curl, git, claude CLI (logged in for step 3/4), uv (for uvx).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STAMP="$(date +%Y%m%d-%H%M%S)"

mkdir -p "$CLAUDE_DIR"

backup_then_link() {
  local src="$1" dst="$2"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    mv "$dst" "$dst.bak-$STAMP"
    echo "backed up: $dst -> $dst.bak-$STAMP"
  fi
  ln -sfn "$src" "$dst"
  echo "linked: $dst -> $src"
}

echo "== 1/4 Linking config into $CLAUDE_DIR =="
backup_then_link "$HERE/settings.json"          "$CLAUDE_DIR/settings.json"
backup_then_link "$HERE/CLAUDE.md"              "$CLAUDE_DIR/CLAUDE.md"
backup_then_link "$HERE/RTK.md"                 "$CLAUDE_DIR/RTK.md"
backup_then_link "$HERE/statusline-caveman.sh"  "$CLAUDE_DIR/statusline-caveman.sh"
chmod +x "$HERE/statusline-caveman.sh"
for d in skills commands agents; do
  backup_then_link "$HERE/$d" "$CLAUDE_DIR/$d"
done

echo "== 2/4 RTK =="
if command -v rtk >/dev/null 2>&1 && rtk gain >/dev/null 2>&1; then
  echo "rtk present: $(rtk --version)"
else
  # NEVER `cargo install rtk` — that is a different crate (Rust Type Kit).
  curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
  command -v rtk >/dev/null 2>&1 || echo "WARN: rtk not on PATH yet — open a new shell, or install via 'brew install rtk'"
fi
# The PreToolUse hook is already declared in settings.json; no `rtk init -g` needed.

echo "== 3/4 Plugins =="
if ! command -v claude >/dev/null 2>&1; then
  echo "WARN: claude CLI not found — install Claude Code first, then re-run this script."
  exit 1
fi
claude plugin marketplace add anthropics/claude-plugins-official 2>/dev/null || true
claude plugin marketplace add JuliusBrussee/caveman 2>/dev/null || true
PLUGINS=(
  superpowers@claude-plugins-official
  context7@claude-plugins-official
  pr-review-toolkit@claude-plugins-official
  playwright@claude-plugins-official
  ralph-loop@claude-plugins-official
  typescript-lsp@claude-plugins-official
  pyright-lsp@claude-plugins-official
  gopls-lsp@claude-plugins-official
  rust-analyzer-lsp@claude-plugins-official
  jdtls-lsp@claude-plugins-official
  caveman@caveman
)
for p in "${PLUGINS[@]}"; do
  claude plugin install "$p" --scope user 2>/dev/null || echo "note: $p not installed (already present, or needs 'claude' login/trust — run 'claude plugin install $p' manually)"
done

echo "== 4/4 MCP: token-savior (user scope) =="
if command -v uvx >/dev/null 2>&1; then
  claude mcp remove token-savior --scope user >/dev/null 2>&1 || true
  claude mcp add --scope user --transport stdio \
    --env TOKEN_SAVIOR_CLIENT=claude-code \
    --env TOKEN_SAVIOR_PROFILE=optimized \
    token-savior -- uvx token-savior-recall
else
  echo "WARN: uvx not found — install uv (https://docs.astral.sh/uv/), then run:"
  echo "  claude mcp add --scope user --transport stdio --env TOKEN_SAVIOR_CLIENT=claude-code --env TOKEN_SAVIOR_PROFILE=optimized token-savior -- uvx token-savior-recall"
fi

echo
echo "Done. Remaining manual steps:"
echo "  1. Run 'claude' once interactively: /login, trust the workspace, confirm plugins load."
echo "  2. Verify: '/status' in Claude Code; 'rtk gain' in shell; 'claude plugin list'."
echo "  3. LSP servers are separate binaries — install the ones you use, e.g.:"
echo "     npm i -g typescript-language-server pyright; go install golang.org/x/tools/gopls@latest; rustup component add rust-analyzer"
