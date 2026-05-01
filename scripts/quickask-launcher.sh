#!/bin/sh
set -eu

if [ -z "${GEMINI_API_KEY:-}" ]; then
  if [ -f "$HOME/.quickask.env" ]; then
    set -a
    . "$HOME/.quickask.env"
    set +a
  fi
fi

exec "$(dirname "$0")/QuickAsk"
