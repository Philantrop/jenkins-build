#!/bin/bash

TMPFILE=$1
PKG=$2
DEBUG=$3
WORKSPACE=$4
BUILDNO=$5
NICENESS=$6

hostname localhost

chgrp tty /dev/tty
source /etc/profile
stty columns 80 rows 40

[[ ${DEBUG} -eq 1 ]] && ls /
[[ ${DEBUG} -eq 1 ]] && echo "TMPFILE: ${TMPFILE}"

echo > ${TMPFILE}
[[ ${DEBUG} -eq 1 ]] && ls -l ${TMPFILE}

WORKSPACE=${WORKSPACE//@*}

if [[ ${PKG} == everything ]]; then
    PKG="$(cave print-ids --matching "*/*::$(basename ${WORKSPACE})" --format '%c/%p%:%s::%r\n')"
fi

echo "**************************************************************"
echo "Mounts:"
mount
echo "**************************************************************"

echo cave resolve ${PKG} --display-resolution-program "cave print-resolution-required-confirmations > ${TMPFILE}"
nice -n${NICENESS} cave resolve ${PKG} --display-resolution-program "cave print-resolution-required-confirmations > ${TMPFILE}"

[[ ${DEBUG} -eq 1 ]] && ls -l ${TMPFILE}
[[ ${DEBUG} -eq 1 ]] && ls -l /usr/local/bin/handle_confirmations

ARGS=$(/usr/local/bin/handle_confirmations < ${TMPFILE})
if [[ "${ARGS}" == *unknown\ confirmation:* ]]; then
    echo "***** I FAILED! ***********************************************"
    cat ${TMPFILE}
    echo "*************** COMMITTING SUICIDE NOW! ***********************"
    exit 1
fi

[[ ${DEBUG} -eq 1 ]] && echo ARGS: ${ARGS}

echo "**************************************************************"
echo "cave resolve command"
echo cave resolve -zx --promote-binaries if-same --skip-phase test --change-phases-for \!targets ${PKG} ${ARGS} 
echo cave resolve -zx --promote-binaries if-same --skip-phase test --change-phases-for \!targets ${PKG} ${ARGS} &> cave-resolve.txt
[[ ${DEBUG} -eq 0 ]] && cave resolve -zx --promote-binaries if-same --skip-phase test --change-phases-for \!targets ${PKG} ${ARGS}
rc=$?

if [[ ${rc} -gt 0 ]]; then
    PKG=${PKG/*\/}
    find /var/tmp/paludis/build/*${PKG/::*}* -name "config.log" -exec cp {} /var/db/paludis/gerrit/$(basename ${WORKSPACE})/${BUILDNO}_config.log \;
    find /var/log/paludis -name "*${PKG/::*}*.out" -exec cp {} /var/db/paludis/gerrit/$(basename ${WORKSPACE})/${BUILDNO}_build.log \;

#    if [[ -n ${PKG} ]]; then
#	find /var/db/paludis/repositories/pbin -iname "*${PKG/::*}*" -delete
#    fi
else
    echo "**************************************************************"
    echo "Dependencies I believe to have found (excluding system):"
    #mscan ${PKG/::*}
    /usr/bin/mscan2.rb -i system ${PKG/::*} 2>&1 | tee dependencies.txt
    echo "**************************************************************"
fi

cp cave-resolve.txt /var/db/paludis/gerrit/$(basename ${WORKSPACE})/${BUILDNO}_cave-resolve.txt
[[ -f dependencies.txt ]] && cp dependencies.txt /var/db/paludis/gerrit/$(basename ${WORKSPACE})/${BUILDNO}_dependencies.txt

exit ${rc}
