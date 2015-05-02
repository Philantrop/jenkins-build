#!/bin/bash

CHROOT=${1}
WORKSPACE=${2}
JOB_NAME=${3}
DEBUG=${4:-0}
if [[ $# -gt 4 ]]; then
    shift 4
    NSPAWN_ARGS="$@"
fi

EXECUTE=$(cat)

[[ ${DEBUG} -eq 0 ]] && sudo rsync -aHx --exclude="*~" --force --delete --delete-excluded /srv/jenkins/amd64_base/amd64/* "${CHROOT}" || echo "rsync failed"

sudo /usr/bin/systemd-nspawn \
    "${NSPAWN_ARGS[@]}" \
    --bind=/srv/www/localhost/htdocs/pbin:/var/db/paludis/repositories/pbin \
    --bind=/home/jenkins/workspace:/var/db/paludis/gerrit \
    --bind="${WORKSPACE}":/var/db/paludis/gerrit/${JOB_NAME} \
    -D "${CHROOT}" /bin/bash -c "${EXECUTE}"

