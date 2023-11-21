#!/bin/bash

for h in "/zquick/hooks/${1}"/*; do
  [ -x "${h}" ] || continue
  "${h}" 
done