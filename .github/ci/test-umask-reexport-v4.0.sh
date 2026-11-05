#!/bin/sh
# 4.0 and 4.1 have no umask attribute; report, do not judge.
NOJUDGE=MEASURE V=4.0 exec sh "$(dirname "$0")/test-umask-reexport.sh"
