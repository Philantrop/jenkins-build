#!/bin/bash

chgrp tty /dev/tty
source /etc/profile
stty columns 80 rows 40

# Lower pbin importance
sed -i -e "s:^\(importance =\).*:\1 -100:" /etc/paludis/repositories/pbin.conf

# Turn off tests for the update
sed -i -e "/\*\/\* build_options:/s:\(recommended_tests\):-\1:" /etc/paludis/options.conf

export CAVE_RESOLVE_OPTIONS=

cave -E :base sync

# Update things
PALUDIS_DO_NOTHING_SANDBOXY=y cave -E :base resolve world -c  --recommendations ignore  --suggestions ignore --purge '*/*' -x
rc=$?

# Fix linkage
PALUDIS_DO_NOTHING_SANDBOXY=y cave -E :base fix-linkage -x
rc=$?

# Fix cache
PALUDIS_DO_NOTHING_SANDBOXY=y cave -E :base fix-cache
rc=$?

# Re-enable tests
sed -i -e "/\*\/\* build_options:/s:-\(recommended_tests\):\1:" /etc/paludis/options.conf 

# Raise pbin importance
sed -i -e "s:^\(importance =\).*:\1 0:" /etc/paludis/repositories/pbin.conf

eclectic --no-color config list |
    awk '$1~/^\[[[:digit:]]\]$/{print $2}' |
    while read c; do
        for f in "${c%/*}/._cfg"*"${c##*/}"; do
            mv -v "$f" "$c"
        done
    done

eclectic news read new
eclectic news purge

# Clean up
rm /var/cache/paludis/distfiles/*
rm /var/log/paludis.log
rm /var/log/paludis/*
rm /tmp/manpages-checks*

if [[ rc -gt 0 ]]; then
    exit 1
fi

exit 0
