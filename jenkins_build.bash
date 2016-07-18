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

unset PKG

pushd /home/jenkins/workspace &>/dev/null
for repo in $(ls); do
    pushd "${x}" &>/dev/null
    git pull &>/dev/null
    popd &>/dev/null
done
popd &>/dev/null

diff -q /srv/jenkins/amd64_base/amd64/usr/local/bin/cave_install.bash ${0%/*}/cave_install.bash || sudo cp -av ${0%/*}/cave_install.bash /srv/jenkins/amd64_base/amd64/usr/local/bin/cave_install.bash

if [[ -z ${WORKSPACE} ]]; then
    WORKSPACE=/home/jenkins/workspace/$(/usr/bin/ssh -x -p ${PORT} ${SSH_USER}@${SERVER} -- gerrit query ${GERRIT_CHANGE_NUMBER} | /usr/bin/awk '$1~/project:/{print $NF}')
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
sudo chmod -R a+r *
[[ ! -e profiles/repo_name ]] && give_up No repo_name
REPO=$(<profiles/repo_name)
[[ -z $REPO ]] && give_up Empty repo_name

if [[ -n ${GERRIT_CHANGE_NUMBER} ]]; then
    CHANGEID=$(/usr/bin/ssh -x -p ${PORT} ${SSH_USER}@${SERVER} -- gerrit query ${GERRIT_CHANGE_NUMBER} | /usr/bin/awk '$1~/^id:$/{print $NF}')
    GITCHANGEID=$(git show --pretty='%b' -s | /usr/bin/awk '$1~/^Change-Id:/{print $NF}')
    [[ ${CHANGEID} == ${GITCHANGEID} ]] && PKG=$(bash -x ${0%/*}/find_targets.bash 2> ${BUILD_NUMBER:-0}_find_targets_build.log)
    if [[ -z ${PKG} ]]; then
        PKG=$(/usr/bin/ssh -x -p ${PORT} ${SSH_USER}@${SERVER} -- gerrit query --files --current-patch-set change:${GERRIT_CHANGE_NUMBER} | /usr/bin/awk -F/ '$1~/project:/{repo=$0};$1~/file:\ packages/{print $2"/"$3"::"repo}' | sed -e 's/::  project: \(.*\)$/::\1/' | sort -u | xargs)
        if [[ -z ${PKG} ]]; then
            EXLIB=$(/usr/bin/ssh -x -p ${PORT} ${SSH_USER}@${SERVER} -- gerrit query --files --current-patch-set change:${GERRIT_CHANGE_NUMBER} | /usr/bin/awk -F/ '$1~/file: exlibs/{print $2}' | sort -u | xargs)
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
        PKG=$(bash -x ${0%/*}/find_targets.bash 2> ${BUILD_NUMBER:-0}_find_targets_build.log)
        if [[ -z ${PKG} ]]; then
            PKG=$(git show --pretty=format:"" --name-only --no-color HEAD | grep -v "^$" | /usr/bin/awk -F/ '$1~/packages/{print $2"/"$3}' | sort -u | xargs)
            if [[ -n ${PKG} ]]; then PKG+="::${REPO}"; fi
        fi
        if [[ -z ${PKG} ]]; then
            EXLIB=$(git show --pretty=format:"" --name-only --no-color HEAD | grep -v "^$" | /usr/bin/awk -F/ '$1~/exlibs/{print $2}' | sort -u | xargs)
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

let CHROOT_NUM=1
let CHROOT_MAX=20
let FLOCKERR=126
JENKINS_CHROOT_ARGS=(
    "${TMPFILE}" "${PKG}" "${DEBUG}" "${WORKSPACE}" "${REPO}" "${BUILD_NUMBER:-0}" "${NICENESS}"
)

set -x
if [[ -n $1 ]] && [[ -d $1 ]]; then
    CHROOT="$1"

    flock -n -E ${FLOCKERR} "/srv/jenkins/locks/${CHROOT//\//-}" \
        ${0%/*}/jenkins_chroot.bash "${CHROOT}" "${JENKINS_CHROOT_ARGS[@]}"
    ret=$?
    [[ $ret -eq ${FLOCKERR} ]] && echo "Could not acquire lock on ${CHROOT}" >&2
else
    until [[ ${LOCK_ACQUIRED} == true ]]; do
        NUM=$(( ( RANDOM % CHROOT_MAX ) + 1 ))
        CHROOT="/srv/jenkins/amd64_${NUM}"

        CHROOT_TEST=$(flock -n -E ${FLOCKERR} /srv/jenkins/locks/${NUM} sudo /usr/bin/systemd-nspawn -D "${CHROOT}" busybox echo)
        testret=$?
        if [[ $testret -eq 0 ]]; then
            echo "Test systemd-nspawn chroot succeeded"
            flock -n -E ${FLOCKERR} /srv/jenkins/locks/${NUM} \
                ${0%/*}/jenkins_chroot.bash "${CHROOT}" "${JENKINS_CHROOT_ARGS[@]}"
            ret=$?
        else
            if [[ $testret -eq ${FLOCKERR} ]]; then
                continue
            elif echo "${CHROOT_TEST}" | grep -q "Failed to register machine: Unit .* already exists."; then
                echo "$testret - $(date) - ${CHROOT_TEST}" >> /tmp/jenkins_chroot_test.log
                echo "Left over scope detected - err $testret"
                echo "${CHROOT_TEST}"
                continue
            elif echo "${CHROOT_TEST}" | grep -q "Directory tree /srv/jenkins/.* is currently busy."; then
                echo "$testret - $(date) - ${CHROOT_TEST}" >> /tmp/jenkins_chroot_test.log
                echo "Something is missing a lock on ${CHROOT} - err $testret"
                echo "${CHROOT_TEST}"
                continue
            fi
        fi
        [[ $ret -eq ${FLOCKERR} ]] || LOCK_ACQUIRED=true
    done
fi
set +x

unset JENKINS_HOME

exit $ret

