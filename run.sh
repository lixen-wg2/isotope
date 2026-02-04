#!/bin/bash
# Run Isotope TUI demo
cd "$(dirname "$0")"

# Compile first
rebar3 compile

# Run with erl directly to avoid shell prompt interference
erl -pa _build/default/lib/*/ebin \
    -noshell \
    -eval 'application:ensure_all_started(isotope)' \
    -s isotope start

