#!/bin/bash

# shellcheck disable=SC1091
. /zquick/libexec/utils.sh

for h in "/zquick/hooks/${1}"/*; do
  [ -x "${h}" ] || continue
  qdebug "Running ${h}"
  unbuffer "${h}"
done

