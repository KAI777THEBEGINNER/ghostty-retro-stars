# Zellij auto-start: each terminal window gets its own independent session
# Place this snippet at the end of your ~/.zshrc (or source it from there)
#
# Logic:
#   1. Only run for interactive shells ($- contains 'i')
#   2. Only run when stdin is a real TTY ([[ -t 0 ]])
#      — blocks GUI apps that spawn `zsh -l -i -c '...'` to probe PATH
#        (e.g. CodexBar, some IDE shells); without this guard each app
#        launch leaks one orphan zellij --server.
#   3. Only run outside of zellij ($ZELLIJ unset) — avoids recursion
#   4. Honor a sentinel env ($CODEXBAR_PROBE) so cooperating callers
#      can opt out explicitly even when their stdin happens to be a TTY.
#   5. Clean up BOTH dead (EXITED) sessions AND orphan running sessions
#      (running but no client attached — i.e. terminal closed but the
#      zellij --server got reparented to launchd as PPID=1). The old
#      "EXITED-only" cleanup let these orphans pile up indefinitely.
#   6. Create a unique session named gt-<PID> per terminal window
#
# Why not attach to a shared session?
#   - Shared sessions mirror content across all attached terminals.
#   - If you /clear in one window, it clears for all.
#   - Multiple Ghostty windows act as clones, not independent panes.
#   - Independent sessions = true parallel worlds, zero cross-contamination.

if [[ $- == *i* ]] && [[ -t 0 ]] && [[ -z "$ZELLIJ" ]] && [[ -z "$CODEXBAR_PROBE" ]]; then
    # Clean EXITED + orphan running sessions (no client attached).
    # `zellij list-sessions -n` skips ANSI styling so plain string match works.
    # The currently-attached session is marked "(current)" — we leave it alone.
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        name="${line%% *}"
        if [[ "$line" == *EXITED* ]]; then
            zellij delete-session "$name" --force 2>/dev/null
        elif [[ "$line" != *"(current)"* ]]; then
            zellij kill-session "$name" 2>/dev/null
            zellij delete-session "$name" --force 2>/dev/null
        fi
    done < <(zellij list-sessions -n 2>/dev/null)
    # Launch a brand-new session unique to this shell process
    zellij --session "gt-$$"
fi
