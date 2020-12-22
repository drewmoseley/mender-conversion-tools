#!/bin/bash
#
# Generate a Boost-backend installation Mender artifact
#
# This has to match what is defined in mender_freewire_config
DEVICE_TYPE="reliagate_20_25"

echo "Version number being used is $2"
version=$2
echo $version
JFROG_URL=https://freewiretech.jfrog.io/freewiretech/libs-release-local/com/freewire/mobi/

#set file names, add version
bVersion='boost-'$version'.dp'
comVersion='com.freewire.common-'$version'.dp'
canVersion='com.freewire.canconnectorimpl-'$version'.dp'
cloudVersion='com.freewire.cloudpayloaduploader-'$version'.dp'
displayVersion='com.freewire.display-'$version'.dp'
echo $bversion

#pull files from JROG
function get_dp_from_artifactory(){
	FILENAME=$1
	echo "Getting File from Artifactory: $0"
	URL=$JFROG_URL$1"/"$2"/"$1"-"$2".dp"
	echo $JFROG_URL$1"/"$2"/"$1"-"$2".dp"
	echo $FILENAME
	curl -u freewire-dev:tE11$Tlpyl^j -o $FILENAME-$version.dp $URL

}

get_dp_from_artifactory /home/mario/BOOST_DIR/boost/build/distributions/boost $1
get_dp_from_artifactory /home/mario/BOOST_DIR/boost/build/distributions/com.freewire.common $1
get_dp_from_artifactory /home/mario/BOOST_DIR/boost/build/distributions/com.freewire.canconnectorimpl $1
get_dp_from_artifactory /home/mario/BOOST_DIR/boost/build/distributions/com.freewire.cloudpayloaduploader $1
get_dp_from_artifactory /home/mario/BOOST_DIR/boost/build/distributions/com.freewire.display $1

#create artifact
MENDER_OUTPUT_ARTIFACT="$1"
if [ -f "${MENDER_OUTPUT_ARTIFACT}" ]; then
    echo "Output file ${MENDER_OUTPUT_ARTIFACT} already exists. Remove it before running $0"
    exit 0
fi

MENDER_ARTIFACT_NAME="$2"
if [ -n "$3" ] ; then
    BOOST_BUILD_DIR="$3"
else
    BOOST_BUILD_DIR="$(pwd)"
fi
if [ -z "${MENDER_OUTPUT_ARTIFACT}" ] || [ -z "${MENDER_ARTIFACT_NAME}" ] || [ ! -d "${BOOST_BUILD_DIR}" ]; then
    echo "Usage: $0 output-artifact-file-name artifact-name [boost-build-dir]"
    exit 0
fi

set -ue

#
# Make sure to cleanup
#
ARTIFACT_DIR=$(mktemp -d)
exit_it() {
    rm -rf $ARTIFACT_DIR
}
trap exit_it HUP
trap exit_it INT

#
# Create directory overlay contents
#
echo $DEVICE_TYPE


 
mkdir -p ${ARTIFACT_DIR}/rootfs/opt/eurotech/esf/kura/packages
cp ${BOOST_BUILD_DIR}/boost/dpa.properties ${ARTIFACT_DIR}/rootfs/opt/eurotech/esf/kura/
cp ${BOOST_BUILD_DIR}/boost/build/distributions/$bVersion \
   ${BOOST_BUILD_DIR}/boost/build/distributions/$comVersion \
   ${BOOST_BUILD_DIR}/boost/build/distributions/$canVersion \
   ${BOOST_BUILD_DIR}/boost/build/distributions/$cloudVersion \
   ${BOOST_BUILD_DIR}/boost/build/distributions/$displayVersion \
   ${ARTIFACT_DIR}/rootfs/opt/eurotech/esf/kura/packages

#
# Create the Mender artifact
#
wget -Nq -P ${ARTIFACT_DIR} https://raw.githubusercontent.com/mendersoftware/mender-update-modules/master/dir-overlay/module-artifact-gen/dir-overlay-artifact-gen
chmod +x ${ARTIFACT_DIR}/dir-overlay-artifact-gen
wget -Nq -P ${ARTIFACT_DIR} https://d1b0l86ne08fsf.cloudfront.net/mender-artifact/3.4.0/linux/mender-artifact
chmod +x ${ARTIFACT_DIR}/mender-artifact
PATH=${ARTIFACT_DIR}:${PATH} ${ARTIFACT_DIR}/dir-overlay-artifact-gen \
    -n ${MENDER_ARTIFACT_NAME} \
    -t ${DEVICE_TYPE} \
    -d / \
    -o ${MENDER_OUTPUT_ARTIFACT} \
    ${ARTIFACT_DIR}/rootfs \
    -- \
    --script state-scripts/backend/ArtifactCommit_Enter_00_restart-service \
    --script state-scripts/backend/ArtifactInstall_Enter_00_verify-status

#
# Exit and cleanup
#
exit_it
