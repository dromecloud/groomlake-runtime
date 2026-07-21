#!/bin/sh
set -eu

etc_root="${GROOMLAKE_ETC_ROOT:-/etc}"
cat "${etc_root}/groomlake/motd.txt"
