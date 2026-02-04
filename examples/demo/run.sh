#!/bin/bash
cd "$(dirname "$0")"

# Cleanup function to restore terminal state
cleanup() {
    # Disable mouse tracking (SGR extended mode)
    printf '\e[?1006l\e[?1000l'
    # Show cursor
    printf '\e[?25h'
    # Exit alternate screen
    printf '\e[?1049l'
    # Reset attributes
    printf '\e[0m'
}

# Set trap to run cleanup on exit (catches Ctrl+C, etc.)
trap cleanup EXIT

rebar3 compile && erl -noshell -pa _build/default/lib/*/ebin -pa _build/default/checkouts/*/ebin -eval "application:ensure_all_started(demo)" -eval "receive stop -> ok end"

