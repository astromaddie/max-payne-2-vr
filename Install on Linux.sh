#!/bin/sh
set -eu
if ! command -v python3 >/dev/null 2>&1; then
    printf '%s\n' 'Python 3 is required. Install it through your distribution, then retry.' >&2
    exit 1
fi
package_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec python3 "$package_dir/setup-files/tools/linux_setup.py" "$@"
