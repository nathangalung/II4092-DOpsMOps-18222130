#!/usr/bin/env bash
# =============================================================================
# nuke-vps.sh — return VPS to fresh state.
# =============================================================================
# DESTRUCTIVE. Removes:
#   - k3s (binaries + /var/lib/rancher + /etc/rancher + /var/lib/kubelet)
#   - Docker + containerd (packages + /var/lib/docker + /var/lib/containerd)
#   - Lang toolchains (~/.cargo, ~/.rustup, ~/.bun, ~/.npm, ~/go)
#   - Pkg caches (~/.cache/{uv,coursier,go-build,node-gyp,mill,matplotlib})
#   - ~/.local/share/{uv,xmake,nvim}
#   - Tarballs in $HOME (go*.tar.gz, nvim*.tar.gz)
#   - Stale logs (/var/log/*.gz, /var/log/*.1, /var/log/*.old)
#   - /tmp/* + journald (vacuum to 100M)
#   - Apt cache + autoremove
#
# PRESERVED:
#   - ~/.claude, ~/.local/share/claude, ~/.cache/claude*, ~/claude-backup.tar.gz
#   - ~/.local/bin/rtk
#   - ~/documents (project)
#   - System packages required for Claude Code
#
# Usage:
#   FORCE=1 bash scripts/nuke-vps.sh    # skip confirmation
# =============================================================================
set -euo pipefail

if [[ "${FORCE:-0}" != "1" ]]; then
  echo "WARNING: VPS reset — removes k3s, Docker, lang toolchains, caches."
  echo "PRESERVED: ~/.claude, ~/.local/bin/rtk, ~/documents, ~/claude-backup.tar.gz"
  read -r -p "Type 'NUKE-VPS' to continue: " confirm
  [[ "$confirm" == "NUKE-VPS" ]] || { echo "Aborted."; exit 1; }
fi

echo ""
echo "==> Step 1: stop services"
sudo systemctl stop docker docker.socket containerd 2>/dev/null || true
sudo systemctl disable docker docker.socket containerd 2>/dev/null || true
if [[ -x /usr/local/bin/k3s-killall.sh ]]; then
  sudo /usr/local/bin/k3s-killall.sh 2>/dev/null || true
fi

echo ""
echo "==> Step 2: uninstall k3s"
if [[ -x /usr/local/bin/k3s-uninstall.sh ]]; then
  sudo /usr/local/bin/k3s-uninstall.sh 2>&1 | tail -5
else
  echo "    k3s already gone"
fi
sudo rm -rf /etc/rancher /var/lib/rancher /var/lib/kubelet /run/k3s 2>/dev/null || true

echo ""
echo "==> Step 3: purge Docker + containerd packages"
sudo apt-get purge -y "docker*" "containerd*" 2>&1 | tail -3 || true
sudo rm -rf /etc/docker /etc/containerd /var/lib/docker /var/lib/containerd \
            /var/lib/longhorn-migration 2>/dev/null || true

echo ""
echo "==> Step 4: remove lang toolchains + caches"
# Use sudo because ~/go module cache has read-only perms
sudo rm -rf \
  "$HOME/.cargo" "$HOME/.rustup" "$HOME/.bun" "$HOME/.npm" "$HOME/go" \
  "$HOME/.cache/uv" "$HOME/.cache/coursier" "$HOME/.cache/go-build" \
  "$HOME/.cache/node-gyp" "$HOME/.cache/mill" "$HOME/.cache/matplotlib" \
  "$HOME/.local/share/uv" "$HOME/.local/share/xmake" "$HOME/.local/share/nvim" \
  "$HOME/.kube" "$HOME/.docker" "$HOME/.serena" \
  2>/dev/null || true

echo ""
echo "==> Step 5: remove installer tarballs"
rm -f "$HOME"/go*.tar.gz "$HOME"/nvim*.tar.gz "$HOME"/kubectl* 2>/dev/null || true

echo ""
echo "==> Step 6: vacuum journald + truncate big logs"
sudo journalctl --vacuum-size=100M 2>&1 | tail -3 || true
sudo find /var/log -type f \( -name "*.gz" -o -name "*.1" -o -name "*.old" \) -delete 2>/dev/null || true
sudo find /var/log -type f -name "*.log" -size +50M -exec truncate -s 0 {} + 2>/dev/null || true

echo ""
echo "==> Step 7: clear /tmp"
sudo find /tmp -mindepth 1 -maxdepth 1 ! -name 'claude*' ! -name '.X*' -exec rm -rf {} + 2>/dev/null || true

echo ""
echo "==> Step 8: apt cleanup"
sudo apt-get autoremove -y 2>&1 | tail -3 || true
sudo apt-get clean 2>&1 || true

echo ""
echo "==> Step 9: remove kernel-pinned configs"
sudo rm -f /etc/sysctl.d/99-k3s-platform.conf \
           /etc/systemd/resolved.conf.d/dns.conf 2>/dev/null || true

echo ""
echo "==> Done. Final state:"
df -h / | tail -1
echo ""
echo "Preserved (claude + project):"
du -sh "$HOME/.claude" "$HOME/.local/share/claude" "$HOME/.local/bin/rtk" \
       "$HOME/claude-backup.tar.gz" "$HOME/documents" 2>/dev/null | sed 's/^/  /'
echo ""
echo "Reinstall path:  cd ~/documents/ta && make install-k3s"
