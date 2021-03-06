#!/bin/bash -e

PRODUCT=scylla
DIR=$(dirname $(readlink -f $0))

print_usage() {
    echo "build_ami.sh --localrpm --repo [URL] --target [distribution]"
    echo "  --localrpm  deploy locally built rpms"
    echo "  --repo  repository for both install and update, specify .repo/.list file URL"
    echo "  --repo-for-install  repository for install, specify .repo/.list file URL"
    echo "  --repo-for-update  repository for update, specify .repo/.list file URL"
    echo "  --product          scylla or scylla-enterprise"
    exit 1
}
LOCALRPM=0
REPO_FOR_INSTALL=
while [ $# -gt 0 ]; do
    case "$1" in
        "--localrpm")
            LOCALRPM=1
            shift 1
            ;;
        "--repo")
            REPO_FOR_INSTALL=$2
            INSTALL_ARGS="$INSTALL_ARGS --repo $2"
            shift 2
            ;;
        "--repo-for-install")
            REPO_FOR_INSTALL=$2
            INSTALL_ARGS="$INSTALL_ARGS --repo-for-install $2"
            shift 2
            ;;
        "--repo-for-update")
            INSTALL_ARGS="$INSTALL_ARGS --repo-for-update $2"
            shift 2
            ;;
        "--product")
            PRODUCT=$2
            shift 2
            ;;
        *)
            print_usage
            ;;
    esac
done

get_version_from_rpm () {
    RPM=$1
    RELEASE=$(rpm -qi $RPM | awk '/Release/ { print $3 }' )
    VERSION=$(rpm -qi $RPM | awk '/Version/ { print $3 }' )
    echo "$VERSION-$RELEASE"
}

check_rpm_exists () {
    BASE_DIR=$1
    rpm_files="$BASE_DIR/$PRODUCT-server*.x86_64.rpm $BASE_DIR/$PRODUCT-cloud-image*.noarch.rpm $BASE_DIR/$PRODUCT-jmx*.noarch.rpm $BASE_DIR/$PRODUCT-tools-*.noarch.rpm $BASE_DIR/$PRODUCT-python3*.x86_64.rpm"
    for rpm in $rpm_files
    do
        if [[ ! -f "$rpm" ]]; then
            echo "ERROR: Matching RPM file not found [$rpm]"
        exit 1
        fi
    done
}
AMI=ami-ae7bfdb8
REGION=us-east-1
SSH_USERNAME=centos

if [ $LOCALRPM -eq 1 ]; then
    # TODO move to new repo
    # REPO=`./scripts/scylla_current_repo --target centos`
    INSTALL_ARGS="$INSTALL_ARGS --localrpm"

    check_rpm_exists $DIR/files

    SCYLLA_VERSION=$(get_version_from_rpm $DIR/files/$PRODUCT-server*.x86_64.rpm)
    SCYLLA_CLOUD_IMAGE_VERSION=$(get_version_from_rpm $DIR/files/$PRODUCT-cloud-image*.noarch.rpm)
    SCYLLA_JMX_VERSION=$(get_version_from_rpm $DIR/files/$PRODUCT-jmx*.noarch.rpm)
    SCYLLA_TOOLS_VERSION=$(get_version_from_rpm $DIR/files/$PRODUCT-tools-*.noarch.rpm)
    SCYLLA_PYTHON3_VERSION=$(get_version_from_rpm $DIR/files/$PRODUCT-python3*.x86_64.rpm)
else
    if [ -z "$REPO_FOR_INSTALL" ]; then
        print_usage
        exit 1
    fi

    TMPREPO=$(mktemp -u -p /etc/yum.repos.d/ --suffix .repo)
    sudo curl -o $TMPREPO $REPO_FOR_INSTALL
    rm -rf build/ami_packages
    mkdir -p build/ami_packages
    cd build/ami_packages/
    yumdownloader $RELVER_HACK $PRODUCT $PRODUCT-kernel-conf $PRODUCT-conf $PRODUCT-server $PRODUCT-debuginfo $PRODUCT-ami $PRODUCT-jmx $PRODUCT-tools-core $PRODUCT-tools $PRODUCT-python3
    sudo rm -f $TMPREPO

    check_rpm_exists build/ami_packages

    SCYLLA_VERSION=$(get_version_from_rpm build/ami_packages/$PRODUCT-server*.x86_64.rpm)
    SCYLLA_CLOUD_IMAGE_VERSION=$(get_version_from_rpm build/ami_packages/$PRODUCT-cloud-image*.noarch.rpm)
    SCYLLA_JMX_VERSION=$(get_version_from_rpm build/ami_packages/$PRODUCT-jmx*.noarch.rpm)
    SCYLLA_TOOLS_VERSION=$(get_version_from_rpm build/ami_packages/$PRODUCT-tools-*.noarch.rpm)
    SCYLLA_PYTHON3_VERSION=$(get_version_from_rpm build/ami_packages/$PRODUCT-python3*.x86_64.rpm)

    cd -
fi

SCYLLA_AMI_DESCRIPTION="scylla-$SCYLLA_VERSION scylla-cloud-image-$SCYLLA_CLOUD_IMAGE_VERSION scylla-jmx-$SCYLLA_JMX_VERSION scylla-tools-$SCYLLA_TOOLS_VERSION scylla-python3-$SCYLLA_PYTHON3_VERSION"

if [ ! -f variables.json ]; then
    echo "create variables.json before start building AMI"
    echo "see wiki page: https://github.com/scylladb/scylla/wiki/Building-CentOS-AMI"
    exit 1
fi

cd $DIR
mkdir -p build

export PACKER_LOG=1
export PACKER_LOG_PATH=build/ami.log

/usr/bin/packer build -var-file=variables.json -var install_args="$INSTALL_ARGS" -var region="$REGION" -var source_ami="$AMI" -var ssh_username="$SSH_USERNAME" -var scylla_version="$SCYLLA_VERSION" -var scylla_cloud_image_version="$SCYLLA_CLOUD_IMAGE_VERSION" -var scylla_jmx_version="$SCYLLA_JMX_VERSION" -var scylla_tools_version="$SCYLLA_TOOLS_VERSION" -var scylla_python3_version="$SCYLLA_PYTHON3_VERSION" -var scylla_ami_description="${SCYLLA_AMI_DESCRIPTION:0:255}" scylla.json
