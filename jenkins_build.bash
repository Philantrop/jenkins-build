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

[[ DEBUG -eq 0 ]] && sudo rsync --progress --human-readable -aHx --exclude="*~" --force --delete --delete-excluded /srv/jenkins/amd64_base/amd64/* "${CHROOT}"

if [[ -n ${GERRIT_CHANGE_NUMBER} ]]; then
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
	pushd "${WORKSPACE}"
	PKG=$(git show --pretty=format:"" --name-only --no-color HEAD | grep -v "^$" | awk -F/ '$1~/packages/{print $2"/"$3}' | sort -u | xargs)
	if [[ -n ${PKG} ]]; then PKG+="::$(basename ${WORKSPACE//@*})"; fi
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

case "${PKG}" in
     *::exherbo-cn*)
	PKG=${PKG//::exherbo-cn/::exhereses-cn}
     ;;
     *::Playground*)
	PKG=${PKG//::Playground/::playground}
     ;;
     *::AelMalinka*)
	PKG=${PKG//::AelMalinka/::malinka}
     ;;
     *::SuperHeron*)
	PKG=${PKG//::SuperHeron/::SuperHeron-misc}
     ;;
     *::lipidity-exheres*)
	PKG=${PKG//::lipidity-exheres/::lipidity}
     ;;
     *::Bruners*)
	PKG=${PKG//::Bruners/::bruners}
     ;;
     *::ocaml-unofficial*)
	NICENESS=10
     ;;
esac

set -e

sudo /usr/bin/systemd-nspawn \
    --bind=/home/jenkins/workspace:/var/db/paludis/gerrit \
    --bind=/srv/www/localhost/htdocs/pbin:/var/db/paludis/repositories/pbin \
    --capability=CAP_MKNOD \
    -D "${CHROOT}" /usr/local/bin/cave_install.bash \
    ${TMPFILE} "${PKG}" ${DEBUG} ${WORKSPACE} ${BUILD_NUMBER} ${NICENESS}

set +e

unset JENKINS_HOME
