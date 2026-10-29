#!/bin/sh
# xcode-build-finished.sh - notch alert from Xcode Behaviors.
#
# Xcode › Settings › Behaviors:
#   Build › Succeeds  › Run script: xcode-build-succeeded.sh
#   Build › Fails     › Run script: xcode-build-failed.sh
# (Xcode cannot pass arguments, so the two wrappers call this script with succeeded / failed.)
#
# The variant comes from $1 or, failing that, from this script's file name.

set -u

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
notchhub="$script_dir/notchhub"

variant=${1:-}
if [ -z "$variant" ]; then
    case ${0##*/} in
        *fail*) variant=failed ;;
        *succe*) variant=succeeded ;;
    esac
fi

# Xcode exports the workspace/project path to behavior scripts on recent versions; fall back gracefully.
project_path=${XcodeWorkspacePath:-${XcodeProjectPath:-}}
project_name=${project_path##*/}
project_name=${project_name%.*}
subtitle=${project_name:+"$project_name · "}Xcode

case $variant in
    succeeded | success | succeeds)
        exec "$notchhub" --quiet --title "✓ Build succeeded" --subtitle "$subtitle" \
            --style success --icon hammer.fill --key xcode.build ;;
    failed | fail | fails)
        exec "$notchhub" --quiet --title "✗ Build failed" --subtitle "$subtitle" \
            --style urgent --icon hammer.fill --key xcode.build --duration 0 ;;
    *)
        printf 'usage: %s succeeded|failed\n' "${0##*/}" >&2
        exit 2 ;;
esac
