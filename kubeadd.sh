#!/bin/sh
# kubeadd is now implemented in kubeadd.py so it also runs on Windows.
# This wrapper keeps existing aliases and symlinks to kubeadd.sh working.
script=$0
while [ -L "$script" ]; do
    link=$(readlink "$script")
    case $link in
        /*) script=$link ;;
        *) script=$(dirname "$script")/$link ;;
    esac
done
dir=$(CDPATH= cd -- "$(dirname -- "$script")" && pwd)
exec python3 "$dir/kubeadd.py" "$@"
