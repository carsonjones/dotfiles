#!/bin/sh

if [ -n "$ZELLIJ_PANE_ID" ] && command -v zellij >/dev/null 2>&1; then
  zellij pipe --name "zellij-attention::waiting::$ZELLIJ_PANE_ID"
fi
