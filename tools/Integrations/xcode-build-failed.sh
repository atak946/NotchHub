#!/bin/sh
# Xcode Behaviors › Build Fails › Run script.
exec "$(dirname -- "$0")/xcode-build-finished.sh" failed
