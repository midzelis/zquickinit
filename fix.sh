#!/bin/bash

find . -not -name .git -type f -name '*.sh' -print0 | xargs -0 sed -i '${/^$/!bnl;};b;:nl a'

