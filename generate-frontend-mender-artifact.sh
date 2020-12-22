#!/bin/bash
#
# Generate a RpI-frontend installation Mender artifact
#

# This has to match what is defined in mender_freewire_config
DEVICE_TYPE="reliagate_20_25"

echo "Version number being used is $2"
version=$2
echo $version

echo "Directory is $3"
directory=$3
echo $directory

if [ -d "/home/mario/BOOST_DIR/frontend_directories" ] 
then
    #delete directory and recreate
    echo "Directory /frontend_directories exists ."
    rm -r /home/mario/BOOST_DIR/frontend_directories
    mkdir /home/mario/BOOST_DIR/frontend_directories
else
    echo "Error:  /frontend_directories does not exists."
    mkdir /home/mario/BOOST_DIR/frontend_directories
fi

cd /home/mario/BOOST_DIR/frontend_directories
git clone https://ACRUNNER2020:f341d9567e63e74deee3f6c09911c458ed2053de@github.com/FreeWireTech/boost-ui.git
cd boost-ui/frontend
pwd
git checkout master
git pull
npm install
npm run build --prod
cd ..
cd ..
pwd
cp -r /home/mario/BOOST_DIR/frontend_directories/boost-ui/frontend/build .
cp -r /home/mario/BOOST_DIR/frontend_directories/boost-ui/lighting-controller .
rm -rf boost-ui




MENDER_OUTPUT_ARTIFACT="$1"
if [ -f "${MENDER_OUTPUT_ARTIFACT}" ]; then
    echo "Output file ${MENDER_OUTPUT_ARTIFACT} already exists. Remove it before running $0"
    exit 0
fi

MENDER_ARTIFACT_NAME="$2"

if [ -n "$3" ] ; then
    FRONTEND_BUILD_DIR="$3"
else
    FRONTEND_BUILD_DIR="$(pwd)"
fi
if [ -z "${MENDER_OUTPUT_ARTIFACT}" ] || [ -z "${MENDER_ARTIFACT_NAME}" ] || [ ! -d "${FRONTEND_BUILD_DIR}/build" ]; then
    echo "Usage: $0 output-artifact-file-name artifact-name [frontend-build-dir]"
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
# Create the Mender artifact
#
wget -Nq -P ${ARTIFACT_DIR} https://raw.githubusercontent.com/mendersoftware/mender/master/support/modules-artifact-gen/directory-artifact-gen
chmod +x ${ARTIFACT_DIR}/directory-artifact-gen
wget -Nq -P ${ARTIFACT_DIR} https://d1b0l86ne08fsf.cloudfront.net/mender-artifact/3.4.0/linux/mender-artifact
chmod +x ${ARTIFACT_DIR}/mender-artifact
PATH=${ARTIFACT_DIR}:${PATH} ${ARTIFACT_DIR}/directory-artifact-gen \
    -n ${MENDER_ARTIFACT_NAME} \
    -t ${DEVICE_TYPE} \
    -d /data/freewire-frontend-code \
    -o ${MENDER_OUTPUT_ARTIFACT} \
    ${FRONTEND_BUILD_DIR}/build \
    -- \
    --script state-scripts/frontend/ArtifactInstall_Enter_00_frontend-remount-rw-and-reboot \
    --script state-scripts/frontend/ArtifactInstall_Leave_00_frontend-remount-ro-and-reboot

#
# Exit and cleanup
#
exit_it

