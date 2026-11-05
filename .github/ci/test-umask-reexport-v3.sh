#!/bin/sh
# The same checks over NFSv3, which carries no umask attribute.
V=3 exec sh "$(dirname "$0")/test-umask-reexport.sh"
