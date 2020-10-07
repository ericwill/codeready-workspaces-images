#!/bin/bash -xe
# script to trigger rhpkg - no sources needed here

scratchFlag=""
doRhpkgContainerBuild=1
forceBuild=0
forcePull=0
while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-n'|'--nobuild') doRhpkgContainerBuild=0; shift 0;;
	  '-f'|'--force-build') forceBuild=1; shift 0;;
	  '-p'|'--force-pull') forcePull=1; shift 0;;
    '-s'|'--scratch') scratchFlag="--scratch"; shift 0;;
  esac
  shift 1
done

function log()
{
  if [[ ${verbose} -gt 0 ]]; then
    echo "$1"
  fi
}

# check required versions at https://github.com/redhat-developer/vscode-openshift-tools/releases
# and https://github.com/redhat-developer/vscode-openshift-tools/blob/master/src/tools.json
# note: as of 0.1.5 win/lin/mac binaries are included in the vsix (no plan to include s390x and ppc64le)

# get correct version of odo from upstream
# toolsJson="https://github.com/redhat-developer/vscode-openshift-tools/raw/master/src/tools.json"
# curl -sSL $toolsJson -o - |   jq ".odo.platform.linux.url" -r | sed -r -e "s#.+/clients/odo/v(.+)/odo.+#\1#"
ODO_VERSION="v2.0.0"
KUBECTL_VERSION="v1.18.9" # see https://github.com/kubernetes/kubernetes/releases/ or $(curl -s https://storage.googleapis.googleapis.com/kubernetes-release/release/stable.txt)

# update Dockerfile to record versions we expect
sed Dockerfile \
    -e "s#ODO_VERSION=\"\([^\"]\+\)\"#ODO_VERSION=\"${ODO_VERSION}\"#" \
    -e "s#KUBECTL_VERSION=\"\([^\"]\+\)\"#KUBECTL_VERSION=\"${KUBECTL_VERSION}\"#" \
    > Dockerfile.2

if [[ $(diff -U 0 --suppress-common-lines -b Dockerfile.2 Dockerfile) ]] || [[ ${forcePull} -eq 1 ]]; then
  mv -f Dockerfile.2 Dockerfile
  mkdir x86_64 s390x ppc64le
  curl -sSLo x86_64/odo https://mirror.openshift.com/pub/openshift-v4/clients/odo/${ODO_VERSION}/odo-linux-amd64 && chmod +x x86_64/odo
  # https://v1-16.docs.kubernetes.io/docs/tasks/tools/install-kubectl/#install-kubectl-binary-with-curl-on-linux
  curl -sSLo x86_64/kubectl https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl && chmod +x x86_64/kubectl
  # s390x
  curl -sSLo s390x/odo https://mirror.openshift.com/pub/openshift-v4/clients/odo/${ODO_VERSION}/odo-linux-s390x && chmod +x s390x/odo
  curl -sSLo s390x/kubectl https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/s390x/kubectl && chmod +x s390x/kubectl
  # ppc64le
  curl -sSLo ppc64le/odo https://mirror.openshift.com/pub/openshift-v4/clients/odo/${ODO_VERSION}/odo-linux-ppc64le && chmod +x ppc64le/odo
  curl -sSLo ppc64le/kubectl https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/ppc64le/kubectl && chmod +x ppc64le/kubectl
  tar czf bin.tgz s390x x86_64 ppc64le
  rm -Rf s390x x86_64 ppc64le
	log "[INFO] Upload new sources: bin.tgz"
  rhpkg new-sources bin.tgz
	log "[INFO] Commit new sources"
  COMMIT_MSG="odo ${ODO_VERSION}, kubectl ${KUBECTL_VERSION}"
	if [[ $(git commit -s -m "[get sources] ${COMMIT_MSG}" sources Dockerfile) == *"nothing to commit, working tree clean"* ]]; then 
		log "[INFO] No new sources, so nothing to build."
	elif [[ ${doRhpkgContainerBuild} -eq 1 ]]; then
		log "[INFO] Push change:"
		git pull; git push
  fi
  if [[ ${doRhpkgContainerBuild} -eq 1 ]]; then
    echo "[INFO] Trigger container-build in current branch: rhpkg container-build ${scratchFlag}"
    tmpfile=`mktemp` && rhpkg container-build ${scratchFlag} --nowait | tee 2>&1 $tmpfile
    taskID=$(cat $tmpfile | grep "Created task:" | sed -e "s#Created task:##") && brew watch-logs $taskID | tee 2>&1 $tmpfile
    ERRORS="$(egrep "image build failed" $tmpfile)" && rm -f $tmpfile
    if [[ "$ERRORS" != "" ]]; then echo "Brew build has failed:

$ERRORS

"; exit 1; fi
  fi
else
	if [[ ${forceBuild} -eq 1 ]]; then
    echo "[INFO] Trigger container-build in current branch: rhpkg container-build ${scratchFlag}"
    tmpfile=`mktemp` && rhpkg container-build ${scratchFlag} --nowait | tee 2>&1 $tmpfile
    taskID=$(cat $tmpfile | grep "Created task:" | sed -e "s#Created task:##") && brew watch-logs $taskID | tee 2>&1 $tmpfile
    ERRORS="$(egrep "image build failed" $tmpfile)" && rm -f $tmpfile
    if [[ "$ERRORS" != "" ]]; then echo "Brew build has failed:

$ERRORS

"; exit 1; fi
	else
	  log "[INFO] No new sources, so nothing to build."
  fi
fi

# cleanup
rm -f Dockerfile.2
