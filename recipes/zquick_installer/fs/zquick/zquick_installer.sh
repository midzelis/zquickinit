#!/bin/bash

: "${DEBUG:=}"
: "${INSTALLER_DIR:=/zquick/libexec/installer}"

envs=( DEBUG="${DEBUG}" INSTALLER_DIR="${INSTALLER_DIR}" )

env "${envs[@]}" "${INSTALLER_DIR}"/installer.sh "$@"
