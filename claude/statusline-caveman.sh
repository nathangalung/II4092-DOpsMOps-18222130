#!/usr/bin/env bash
# Caveman statusline wrapper.
# The plugin's cache path contains a content hash that changes on every plugin
# update, so settings.json points here instead of at the cache directly.
s=$(find "$HOME/.claude/plugins/cache/caveman" -name 'caveman-statusline.sh' 2>/dev/null | head -1)
if [ -n "$s" ]; then
  exec bash "$s"
fi
# Plugin not installed yet — empty statusline, no error spam.
exit 0
