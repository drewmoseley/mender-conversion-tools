#!/bin/sh
#
# Generate a Boost-backend installation Mender artifact
#

# This has to match what is defined in mender_freewire_config
DEVICE_TYPE="reliagate_20_25"

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
if [ ! -d "${BOOST_BUILD_DIR}" ]; then
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
mkdir -p ${ARTIFACT_DIR}/rootfs/opt/eurotech/esf/kura/packages
cp ${BOOST_BUILD_DIR}/boost.dpa.properties ${ARTIFACT_DIR}/rootfs/opt/eurotech/esf/kura/
cp ${BOOST_BUILD_DIR}/boost/build/distributions/boost-1.1.0.dp \
   ${BOOST_BUILD_DIR}/com.freewire.common/build/distributions/com.freewire.common-1.1.0.dp \
   ${BOOST_BUILD_DIR}/com.freewire.canconnectorimpl/build/distributions/com.freewire.canconnectorimpl-1.1.0.dp \
   ${BOOST_BUILD_DIR}/com.freewire.cloudpayloaduploader/build/distributions/com.freewire.cloudpayloaduploader-1.1.0.dp \
   ${BOOST_BUILD_DIR}/com.freewire.display/build/distributions/com.freewire.display-1.1.0.dp \
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
