#!/bin/bash

if [[ -z $TMUX ]]; then
    tmux -u -2 a
    exit 0
fi
