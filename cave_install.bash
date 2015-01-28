#!/bin/bash

TMPFILE=$1
PKG=$2
DEBUG=$3
WORKSPACE=$4
REPO=$5
BUILDNO=$6
NICENESS=$7

hostname localhost

chgrp tty /dev/tty
source /etc/profile
stty columns 80 rows 40

[[ ${DEBUG} -eq 1 ]] && ls /
[[ ${DEBUG} -eq 1 ]] && echo "TMPFILE: ${TMPFILE}"

echo > ${TMPFILE}
[[ ${DEBUG} -eq 1 ]] && ls -l ${TMPFILE}

PROJ=$(basename ${WORKSPACE//@*})
if [[ ${WORKSPACE} == *@* ]]; then
    export CAVE_REPO_SUFFIX_${PROJ//-/_}=${WORKSPACE/#*@/@}
fi

if [[ ${PKG} == everything ]]; then
    PKG="$(cave print-ids --matching "*/*::${REPO}" --format '%c/%p%:%s::%r\n')"
fi

echo "**************************************************************"
echo "Mounts:"
mount
echo "**************************************************************"

echo "cave show -c ${PKG} &> cave-show_dependencies.txt"
cave show -c ${PKG} &> /var/db/paludis/gerrit/${WORKSPACE##*/}/${BUILDNO}_cave-show_dependencies.txt

echo cave resolve ${PKG} --display-resolution-program "cave print-resolution-required-confirmations > ${TMPFILE}"
nice -n${NICENESS} cave resolve ${PKG} --display-resolution-program "cave print-resolution-required-confirmations > ${TMPFILE}"

[[ ${DEBUG} -eq 1 ]] && ls -l ${TMPFILE}
[[ ${DEBUG} -eq 1 ]] && ls -l /usr/local/bin/handle_confirmations

ARGS=$(bash -x /usr/local/bin/handle_confirmations < ${TMPFILE} 2> /var/db/paludis/gerrit/${WORKSPACE##*/}/${BUILDNO}_handle_confirmations_build.log)
if [[ "${ARGS}" == *unknown\ confirmation:* ]]; then
    echo "***** I FAILED! ***********************************************"
    cat ${TMPFILE}
    echo "*************** COMMITTING SUICIDE NOW! ***********************"
    exit 1
fi

[[ ${DEBUG} -eq 1 ]] && echo ARGS: ${ARGS}

echo cave resolve -z --promote-binaries if-same --skip-phase test --change-phases-for \!targets ${PKG} ${ARGS} &> /var/db/paludis/gerrit/${WORKSPACE##*/}/${BUILDNO}_cave-resolve.txt
echo >> /var/db/paludis/gerrit/${WORKSPACE##*/}/${BUILDNO}_cave-resolve.txt
cave resolve -z --promote-binaries if-same --skip-phase test --change-phases-for \!targets ${PKG} ${ARGS} &>> /var/db/paludis/gerrit/${WORKSPACE##*/}/${BUILDNO}_cave-resolve.txt
echo >> /var/db/paludis/gerrit/${WORKSPACE##*/}/${BUILDNO}_cave-resolve.txt

echo "**************************************************************"
echo "cave resolve command"
echo cave resolve -zx --promote-binaries if-same --skip-phase test --change-phases-for \!targets ${PKG} ${ARGS}
echo cave resolve -zx --promote-binaries if-same --skip-phase test --change-phases-for \!targets ${PKG} ${ARGS} &>> /var/db/paludis/gerrit/${WORKSPACE##*/}/${BUILDNO}_cave-resolve.txt
[[ ${DEBUG} -eq 0 ]] && cave resolve -zx --promote-binaries if-same --skip-phase test --change-phases-for \!targets ${PKG} ${ARGS}
rc=$?

if [[ ${rc} -gt 0 ]]; then
    PKG=${PKG/*\/}
    find /var/tmp/paludis/build/*${PKG/::*}* -name "config.log" -exec cp {} /var/db/paludis/gerrit/${WORKSPACE##*/}/${BUILDNO}_config.log \;
    find /var/log/paludis -name "*${PKG/::*}*.out" -exec cp {} /var/db/paludis/gerrit/${WORKSPACE##*/}/${BUILDNO}_build.log \;

#    if [[ -n ${PKG} ]]; then
#	find /var/db/paludis/repositories/pbin -iname "*${PKG/::*}*" -delete
#    fi
else
    echo "**************************************************************"
    echo "Dependencies I believe to have found (excluding system):"
    #mscan ${PKG/::*}
    /usr/bin/mscan2.rb -i system ${PKG/::*} 2>&1 | tee /var/db/paludis/gerrit/${WORKSPACE##*/}/${BUILDNO}_dependencies.txt
    echo "**************************************************************"
fi

exit ${rc}
