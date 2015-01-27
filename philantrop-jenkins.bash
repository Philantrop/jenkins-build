# these scripts rely on this script being saved to
# /etc/paludis-jenkins/repositories/philantrop.bash
# and symlinked from every repo in jenkins
#
# it lets a jenkins build export CAVE_REPO_SUFFIX_arbor=@3 in order to use
# arbor@3 workspace, while using non-suffixed repos for everything else etc.
#
# this is used by e.g. find_targets.bash which queries for targets on root

repo=$(basename ${0} .bash)
suffix=CAVE_REPO_SUFFIX_${repo//-/_}
echo location="${ROOT}/home/jenkins/workspace/${repo}${!suffix}"
[[ ${repo} == arbor ]] && echo profiles="\${location}/profiles/amd64"
:
