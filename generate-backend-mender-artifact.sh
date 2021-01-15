#!/bin/bash
#
# Generate a Boost-backend installation Mender artifact
#
# This has to match what is defined in mender_freewire_config
DEVICE_TYPE="reliagate_20_25"

#update dpa.properties
buildNumber=$2
version=$buildNumber'.dp'
scriptPath="/home/mario/BOOST_DIR/"
scriptName="updatedpaProperties.sh"
$scriptPath/$scriptName $2
result=$?
file=dpa.properties

#echo $1
echo $2
echo "Version number being used is $2"
version=$2
#echo $version
JFROG_URL=https://freewiretech.jfrog.io/artifactory/libs-release-local/com/freewire/mobi/

#set file names, add version
bVersion='boost-'$version'.dp'
comVersion='com.freewire.common-'$version'.dp'
canVersion='com.freewire.canconnectorimpl-'$version'.dp'
cloudVersion='com.freewire.cloudpayloaduploader-'$version'.dp'
displayVersion='com.freewire.display-'$version'.dp'
#menderArtifactName=$1


#delete existing files
rm -f /home/mario/BOOST_DIR/boost/build/distributions/*

#pull files from JROG
function get_dp_from_artifactory(){
    FILENAME=$1
#   echo "filename is $FILENAME"
#   echo "artifactory is $2"
#   echo "Getting File from Artifactory: $2"
    URL=$JFROG_URL$1"/"$2"/"$1"-"$2".dp"
    echo $JFROG_URL$1"/"$2"/"$1"-"$2".dp"
    echo $FILENAME
    curl -u freewire-dev:tE11Tlpyl^j -LO $URL
}
#echo "version is $1"
cd /home/mario/BOOST_DIR/boost/build/distributions/
get_dp_from_artifactory boost  $version
get_dp_from_artifactory com.freewire.common $version
get_dp_from_artifactory com.freewire.canconnectorimpl $version
get_dp_from_artifactory com.freewire.cloudpayloaduploader $version
get_dp_from_artifactory com.freewire.display $version

#create artifact
MENDER_OUTPUT_ARTIFACT="$1"
echo MOA $MENDER_OUTPUT_ARTIFACT
if [ -f "${MENDER_OUTPUT_ARTIFACT}" ]; then
    echo "Output file ${MENDER_OUTPUT_ARTIFACT} already exists. Remove it before running $0"
    echo opt1
    exit 0
fi

MENDER_ARTIFACT_NAME="$2"
if [ -n "$3" ] ; then
    BOOST_BUILD_DIR="$3"
    echo MAN $2
    echo BBD $3
    echo opt2
else
    BOOST_BUILD_DIR="$(pwd)"
fi

if [ -z "${MENDER_OUTPUT_ARTIFACT}" ] || [ -z "${MENDER_ARTIFACT_NAME}" ] || [ ! -d "${BOOST_BUILD_DIR}" ]; then
    echo "Usage: $0 output-artifact-file-name artifact-name [boost-build-dir]"
    echo opt3
    exit 0
fi

set -ue

#
# Make sure to cleanup
#
ARTIFACT_DIR=$(mktemp -d)
echo AD $ARTIFACT_DIR
exit_it() {
    echo removing
    rm -rf $ARTIFACT_DIR
}
trap exit_it HUP
trap exit_it INT

#
# Create directory overlay contents
#
echo $DEVICE_TYPE


 

mkdir -p ${ARTIFACT_DIR}/rootfs/opt/eurotech/esf/data/packages
echo AD $ARTIFACT_DIR
cp ${BOOST_BUILD_DIR}/boost/dpa.properties ${ARTIFACT_DIR}/rootfs/opt/eurotech/esf/data/
cp ${BOOST_BUILD_DIR}/boost/build/distributions/$bVersion \
   ${BOOST_BUILD_DIR}/boost/build/distributions/$comVersion \
   ${BOOST_BUILD_DIR}/boost/build/distributions/$canVersion \
   ${BOOST_BUILD_DIR}/boost/build/distributions/$cloudVersion \
   ${BOOST_BUILD_DIR}/boost/build/distributions/$displayVersion \
   ${ARTIFACT_DIR}/rootfs/opt/eurotech/esf/data/packages

#
# Create the Mender artifact
#
#: '
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
    --script /home/mario/BOOST_DIR/state-scripts/backend/ArtifactCommit_Enter_00_restart-service \
    --script /home/mario/BOOST_DIR/state-scripts/backend/ArtifactInstall_Enter_00_verify-status
#'
#
# Exit and cleanup
#
exit_it
