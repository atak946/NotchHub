#!/bin/sh
# Xcode Behaviors › Build Succeeds › Run script.
exec "$(dirname -- "$0")/xcode-build-finished.sh" succeeded
