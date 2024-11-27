#!/bin/bash
SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd)"

# summary
source $SCRIPTDIR/common.sh

function appstudio-summary() {
    echo "Running $TASK_NAME:appstudio-summary"
    #!/usr/bin/env bash
    echo
    echo "Build Summary:"
    echo
    echo "Build repository: $GIT_URL"
    BUILD_TASK_STATUS=$(cat $BASE_RESULTS/buildah-rhtap/STATUS)
    if [ "$BUILD_TASK_STATUS" == "Succeeded" ]; then
        echo "Generated Image is in : $IMAGE_URL"
    fi
    if [ -e "$SOURCE_BUILD_RESULT_FILE" ]; then
        url=$(jq -r ".image_url" < "$SOURCE_BUILD_RESULT_FILE")
        echo "Generated Source Image is in : $url"
    fi
    echo
    echo End Summary

}
# missing tree command
function showTree() {
    find $1 | sed -e "s/[^-][^\/]*\// ├─/g" -e "s/|\([^ ]\)/|─\1/"
}
function cosignTree() {
    URL=$1
    image_registry="${URL/\/*/}"
    # If the repo is not publicly accessible we need to authenticate so ec can access it
    prepare-registry-user-pass $image_registry
    echo "cosign login to registry $image_registry"
    cosign login --username="$IMAGE_REGISTRY_USER" --password="$IMAGE_REGISTRY_PASSWORD" $image_registry
    cosign tree $URL
}

# Task Steps
appstudio-summary
showTree $BASE_RESULTS
cosignTree $IMAGE_URL
exit_with_success_result
