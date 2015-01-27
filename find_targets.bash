#!/bin/bash

give_up() {
    echo Cannot identify targets: "$*" >&2
    exit 1
}

mycave() {
    env CAVE_REPO_SUFFIX_${workdir//-/_}=${suffix} cave -L warning -E :jenkins "${@}"
}

workdir=${PWD##*/}
suffix=
if [[ ${workdir} == *@* ]]; then
    suffix=${workdir/#*@/@}
    workdir=${workdir%@*}
fi

[[ ! -e profiles/repo_name ]] && give_up No repo_name
repo=$(<profiles/repo_name)
[[ -z $repo ]] && give_up Empty repo_name
formats=""
while read f; do
    # match exact exheres
    if [[ $f == *.exheres-0 ]]; then
	matching="*/*::${repo}[.EXHERES=${PWD}/${f}]"
    elif [[ $f == *.exlib ]]; then
	exlib=${f##*/}
	if [[ ${f} == exlibs/* ]]; then
	    # match per repo exlib
	    matching="*/*::${repo}[.INHERITED<${exlib%.exlib}]"
	elif [[ ${f} == packages/*/exlibs/*.exlib ]]; then
	    # match per category exlib
	    cat=${f#packages/}
	    cat=${cat%%/*}
	    matching="${cat}/*::${repo}[.INHERITED<${exlib%.exlib}]"
	elif [[ ${f} == packages/*/*/*.exlib ]]; then
	    # match per package exlib
	    pkg=${f#packages/}
	    pkg=${pkg%/*}
	    matching="${pkg}::${repo}[.INHERITED<${exlib%.exlib}]"
	fi
    fi

    # prefer visible but fall back to masked if none are visible
    [[ -z ${matching} ]] && continue
    formats+="$(for mask in none any; do
	pkgs=$(mycave print-ids --format '%W %u\n' --matching  "${matching}" --with-mask ${mask})
	[[ -n ${pkgs} ]] && echo "${pkgs}
" && break
    done)
"
# look at file(s) that were added or modified
done < <(git show $1 --pretty='' --name-status | awk '$1~/^[AMR]/{print $NF}')

[[ -z ${formats} ]] && give_up Found no matching ids

# sort ids and make them unique
formats=$(sort -u <<< "${formats}")

# group ids by slot
declare -A ids
while read format; do
    if [[ -n ${format} ]]; then
	f=${format% *}
	ids[${f}]+=" ${format#* } "
    fi
done <<< "${formats}"

pkgs=()
for slot in "${!ids[@]}"; do
    # for each slot
    match=
    idArray=( ${ids[${slot}]} )
    for mask in none any; do
	ordered=$(mycave print-ids --format '%u\n' --matching "${slot}" --with-mask ${mask})
	if [[ -n ${ordered} ]]; then
	    orderedArray=( ${ordered} )
	    for ((i=${#idArray[@]}-1; i>=0; i--)); do
		for o in "${orderedArray[@]}"; do
	    	    [[ ${o} == ${idArray[i]} ]] && match=${o} && break 3
		done
    	    done
	fi
    done
    pkgs+=( ${match} )
done
pkgs=( $(
    IFS=$'\n'
    echo "${pkgs[*]}" | sort -R | tail -n 5
) )
echo "${pkgs[@]}"

