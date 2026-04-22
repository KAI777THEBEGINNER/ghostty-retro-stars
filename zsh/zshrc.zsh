# Zellij auto-start: each terminal window gets its own independent session
# Place this snippet at the end of your ~/.zshrc (or source it from there)
#
# Logic:
#   1. Only run for interactive shells ($- contains 'i')
#   2. Only run outside of zellij ($ZELLIJ is unset)
#   3. Clean up old EXITED sessions to prevent accumulation
#   4. Create a unique session named gt-<PID> per terminal window
#
# Why not attach to a shared session?
#   - Shared sessions mirror content across all attached terminals.
#   - If you /clear in one window, it clears for all.
#   - Multiple Ghostty windows act as clones, not independent panes.
#   - Independent sessions = true parallel worlds, zero cross-contamination.

if [[ $- == *i* ]] && [[ -z "$ZELLIJ" ]]; then
    # Auto-purge dead sessions to keep the session list clean
    for s in $(zellij list-sessions 2>/dev/null | grep "EXITED" | awk '{print $1}'); do
        zellij delete-session "$s" --force 2>/dev/null
    done
    # Launch a brand-new session unique to this shell process
    zellij --session "gt-$$"
fi
