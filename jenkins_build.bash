#!/bin/bash

source /srv/tomcat/bin/data

#USER=""
#PASS=""
#SERVER=""
#URI=""
#SSH_USER=""
DEBUG=0
TMPFILE=$(mktemp -uq)
JENKINS_HOME="http://${USER}:${PASS}@${URI}"
PAGER=""
NICENESS=0

give_up() {
    echo "$*" >&2
    exit 1
}

# Nuke potentially disrupting directories (only required for systemd[~217]; systemd[~218] breaks Jenkins)
# galileo runs 216 for now.
#[[ -d /srv/jenkins/amd64_base/amd64/var/db/paludis/gerrit ]] && sudo rmdir /srv/jenkins/amd64_base/amd64/var/db/paludis/gerrit
#[[ -d /srv/jenkins/amd64_base/amd64/var/db/paludis/repositories/pbin ]] && sudo rmdir /srv/jenkins/amd64_base/amd64/var/db/paludis/repositories/pbin

let CHROOT_NUM=1
let CHROOT_MAX=20

if [[ -n $1 ]] && [[ -d $1 ]]; then
    CHROOT="$1"
else
    CHROOT="/srv/jenkins/amd64_$(( ( RANDOM % 20 )  + 1 ))"
fi

sleep $(( ( RANDOM % 5 )  + 1 ))

while [[ $(ps ax | grep -c "[s]ystemd-nspawn .* ${CHROOT}") -ge 1 ]] && [[ ${CHROOT_NUM} -le ${CHROOT_MAX} ]]; do
    CHROOT="/srv/jenkins/amd64_${CHROOT_NUM}"
    let CHROOT_NUM+=1
done

#if [[ $(ps ax | grep -c "[s]ystemd-nspawn .* ${CHROOT}") -ge 1 ]]; then
#    CHROOT="/srv/jenkins/amd64_2"
#fi

unset PKG

pushd /home/jenkins/workspace &>/dev/null
for repo in $(ls); do
    pushd "${x}" &>/dev/null
    git pull &>/dev/null
    popd &>/dev/null
done
popd &>/dev/null

[[ ${DEBUG} -eq 0 ]] && sudo rsync -aHx --exclude="*~" --force --delete --delete-excluded /srv/jenkins/amd64_base/amd64/* "${CHROOT}" || echo "rsync failed"

if [[ -z ${WORKSPACE} ]]; then
    WORKSPACE=/home/jenkins/workspace/$(/usr/bin/ssh -x -p ${PORT} ${SSH_USER}@${SERVER} -- gerrit query ${GERRIT_CHANGE_NUMBER} | awk '$1~/project:/{print $NF}')
fi

PROJECT_TO_REPO=(
    exherbo-cn:exhereses-cn
    Playground:playground
    AelMalinka:malinka
    SuperHeron:SuperHeron-misc
    lipidity-exheres:lipidity
    Bruners:bruners
)

pushd ${WORKSPACE}
[[ ! -e profiles/repo_name ]] && give_up No repo_name
REPO=$(<profiles/repo_name)
[[ -z $REPO ]] && give_up Empty repo_name

if [[ -n ${GERRIT_CHANGE_NUMBER} ]]; then
    CHANGEID=$(/usr/bin/ssh -x -p ${PORT} ${SSH_USER}@${SERVER} -- gerrit query ${GERRIT_CHANGE_NUMBER} | awk '$1~/^id:$/{print $NF}')
    GITCHANGEID=$(git show --pretty='%b' -s | awk '$1~/^Change-Id:/{print $NF}')
    [[ ${CHANGEID} == ${GITCHANGEID} ]] && PKG=$(bash -x ${0%/*}/find_targets.bash 2> find_targets_build.log)
    if [[ -z ${PKG} ]]; then
        PKG=$(/usr/bin/ssh -x -p ${PORT} ${SSH_USER}@${SERVER} -- gerrit query --files --current-patch-set change:${GERRIT_CHANGE_NUMBER} | awk -F/ '$1~/project:/{repo=$0};$1~/file:\ packages/{print $2"/"$3"::"repo}' | sed -e 's/::  project: \(.*\)$/::\1/' | sort -u | xargs)
        if [[ -z ${PKG} ]]; then
            EXLIB=$(/usr/bin/ssh -x -p ${PORT} ${SSH_USER}@${SERVER} -- gerrit query --files --current-patch-set change:${GERRIT_CHANGE_NUMBER} | awk -F/ '$1~/file: exlibs/{print $2}' | sort -u | xargs)
            if [[ -n ${EXLIB} ]]; then
                echo "Change ${GERRIT_CHANGE_NUMBER} is for ${EXLIB}. Not sure what to do. Exiting."
                exit 0
            else
                echo "No package to build. No exlib recognised. Don't know what to do. Exiting."
                exit 0
            fi
        fi

        PKGSPECS=
        for PKGSPEC in ${PKG}; do
            for P2R in "${PROJECT_TO_REPO[@]}"; do
                if [[ ${PKG} == *::${P2R%:*} ]]; then
                    PKGSPECS+=" ${PKG/%::${P2R%:*}/::${P2R#*:}}" && continue
                fi
            done
            PKGSPECS+=" ${PKG}"
        done
        PKG=${PKGSPECS}

        unset P2R PKGSPEC PKGSPECS
    fi

fi

if [[ -z ${GERRIT_CHANGE_NUMBER} ]]; then
    if [[ -n $2 ]]; then
        GERRIT_CHANGE_NUMBER=$2
    elif [[ -n ${Package_to_build} ]]; then
        if [[ ${Package_to_build} == */* ]]; then
            PKG=${Package_to_build}
        elif [[ ${Package_to_build} == "everything" ]]; then
            PKG="everything"
        fi
    else
        PKG=$(bash -x ${0%/*}/find_targets.bash 2> find_targets_build.log)
        if [[ -z ${PKG} ]]; then
            PKG=$(git show --pretty=format:"" --name-only --no-color HEAD | grep -v "^$" | awk -F/ '$1~/packages/{print $2"/"$3}' | sort -u | xargs)
            if [[ -n ${PKG} ]]; then PKG+="::${REPO}"; fi
        fi
        if [[ -z ${PKG} ]]; then
            EXLIB=$(git show --pretty=format:"" --name-only --no-color HEAD | grep -v "^$" | awk -F/ '$1~/exlibs/{print $2}' | sort -u | xargs)
            if [[ -n ${EXLIB} ]]; then
                echo "git HEAD is for ${EXLIB}. Not sure what to do. Exiting."
                exit 0
            else
                echo "No package to build. No exlib recognised. Don't know what to do. Exiting."
                exit 0
            fi
        fi
        popd
    fi
fi

[[ ${PKG} == *::ocaml-unofficial* ]] && NICENESS=10

set -e

sudo /usr/bin/systemd-nspawn \
    --bind=/home/jenkins/workspace:/var/db/paludis/gerrit \
    --bind=/srv/www/localhost/htdocs/pbin:/var/db/paludis/repositories/pbin \
    --capability=CAP_MKNOD \
    -D "${CHROOT}" /usr/local/bin/cave_install.bash \
    ${TMPFILE} "${PKG}" ${DEBUG} ${WORKSPACE} ${REPO} ${BUILD_NUMBER:-0} ${NICENESS}

set +e

unset JENKINS_HOME
