#!/bin/bash

CHROOT=${1}
TMPFILE=${2}
PKG=${3}
DEBUG=${4}
WORKSPACE=${5}
REPO=${6}
BUILD_NUMBER=${7}
NICENESS=${8}

# Nuke potentially disrupting directories (only required for systemd[~217]; systemd[~218] breaks Jenkins)
# galileo runs 216 for now.
#[[ -d /srv/jenkins/amd64_base/amd64/var/db/paludis/gerrit ]] && sudo rmdir /srv/jenkins/amd64_base/amd64/var/db/paludis/gerrit
#[[ -d /srv/jenkins/amd64_base/amd64/var/db/paludis/repositories/pbin ]] && sudo rmdir /srv/jenkins/amd64_base/amd64/var/db/paludis/repositories/pbin

if [[ ${DEBUG} -eq 0 ]]; then
    echo rsync -aHx --exclude="*~" --force --delete --delete-excluded "/srv/jenkins/amd64_base/amd64/*" "${CHROOT}"
    sudo rsync -aHx --exclude="*~" --force --delete --delete-excluded /srv/jenkins/amd64_base/amd64/* "${CHROOT}" || echo "rsync failed"
fi

sudo /usr/bin/systemd-nspawn \
    --bind=/home/jenkins/workspace:/var/db/paludis/gerrit \
    --bind=/srv/www/localhost/htdocs/pbin:/var/db/paludis/repositories/pbin \
    --capability=all \
    -D "${CHROOT}" /usr/local/bin/cave_install.bash \
    ${TMPFILE} "${PKG}" ${DEBUG} ${WORKSPACE} ${REPO} ${BUILD_NUMBER:-0} ${NICENESS}

