#!/bin/bash
# Forwards Claude Code hook events to the tmux-claude plugin (smilovanovic/tmux-claude).
# No-op when the plugin is not installed, so settings.json works on any machine.

HOOK="${TMUX_CLAUDE_HOOK:-$HOME/.tmux/plugins/tmux-claude/scripts/hook.sh}"

if [ -x "$HOOK" ]; then
    exec "$HOOK" "$@"
fi

# Drain the event payload so Claude Code never sees a broken pipe.
cat >/dev/null
exit 0
