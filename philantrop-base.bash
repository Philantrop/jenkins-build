# these scripts rely on this script being saved to
# /srv/jenkins/amd64_base/amd64/etc/paludis/repositories/philantrop.bash
# and symlinked from every repo in jenkins
#
# it lets a jenkins build export CAVE_REPO_SUFFIX_arbor=@3 in order to use
# arbor@3 workspace, while using non-suffixed repos for everything else etc.
#
# this is used by e.g. cave_install.bash which builds targets in the chroot

repo=$(basename ${0} .bash)
suffix=CAVE_REPO_SUFFIX_${repo//-/_}
echo location="${ROOT}/var/db/paludis/gerrit/${repo}${!suffix}"
[[ ${repo} == arbor ]] && echo profiles="\${location}/profiles/amd64"
:
