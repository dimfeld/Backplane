#!/bin/sh
# Update local main from upstream, then rebase and push the current fork branch.
set -eu

jj git fetch --remote upstream
jj b m main -t main@upstream
jj new personal-mac-fork
jj rebase -d main
