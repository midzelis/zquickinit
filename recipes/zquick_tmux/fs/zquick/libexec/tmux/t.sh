#!/bin/bash
if [[ -z $TMUX ]]; then
    if tmux -2 -u new-session -A -s ZFSBootMenu; then
        exit 0
    fi
    echo "tmux exited with error, starting shell..."
    exec /bin/sh
fi