#!/bin/bash
SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd)"

GITHUB_REPO=https://github.com/$MY_GITHUB_USER/tssc-dev-gitops
GITLAB_REPO=https://gitlab.com/$MY_GITLAB_USER/tssc-dev-gitops
JENKINS_REPO=https://github.com/$MY_GITHUB_USER/tssc-dev-gitops-jenkins

GH_RAW=https://raw.githubusercontent.com/$MY_GITHUB_USER/tssc-dev-gitops/refs/heads/main/components/tssc-dev/overlays/development/deployment-patch.yaml
GL_RAW=https://gitlab.com/$MY_GITLAB_USER/tssc-dev-gitops/-/raw/main/components/tssc-dev/overlays/development/deployment-patch.yaml
J_RAW=https://raw.githubusercontent.com/$MY_GITHUB_USER/tssc-dev-gitops-jenkins/refs/heads/main/components/tssc-dev/overlays/development/deployment-patch.yaml

function getImage() {
    curl -sL $1 | yq .spec.template.spec.containers[0].image
}

# Note, the env var name PREV_IMAGE_ENV_NAME is passed so it can be updated
function promoteIfUpdated() {
    PREV_IMAGE_ENV_NAME=$1
    CURRENT_IMAGE=$2
    REPO=$3

    echo "$REPO"
    echo "P: ${!PREV_IMAGE_ENV_NAME}"
    echo "C: $CURRENT_IMAGE"

    if [[ "${!PREV_IMAGE_ENV_NAME}" != "$CURRENT_IMAGE" ]]; then
        echo "$REPO being updated from ${!PREV_IMAGE_ENV_NAME} to $CURRENT_IMAGE"
        bash $SCRIPTDIR/rhtap-promote --repo $REPO
        eval "$PREV_IMAGE_ENV_NAME"="$CURRENT_IMAGE"
    fi
}
function pushIfUpdated() {
    PREV_IMAGE_ENV_NAME=$1
    CURRENT_IMAGE=$2
    REPO=$3

    echo "$REPO"
    echo "P: ${!PREV_IMAGE_ENV_NAME}"
    echo "C: $CURRENT_IMAGE"

    if [[ "${!PREV_IMAGE_ENV_NAME}" != "$CURRENT_IMAGE" ]]; then
        echo "$REPO  being updated from ${!PREV_IMAGE_ENV_NAME} to $CURRENT_IMAGE"
        bash $SCRIPTDIR/rhtap-push-dev --repo $REPO
        eval "$PREV_IMAGE_ENV_NAME"="$CURRENT_IMAGE"
    fi
}

GH_PREV=$(getImage $GH_RAW)
GL_PREV=$(getImage $GL_RAW)
J_PREV=$(getImage $J_RAW)
# count down and reprint the messages
COUNT=0
while true; do
    if [[ $COUNT == 0 ]]; then
        COUNT=10
        echo
        echo "Github Repo: $GITHUB_REPO"
        echo "Waiting for Github image $GH_PREV to be updated"
        echo
        echo "Gitlab Repo: $GITLAB_REPO"
        echo "Waiting for Gitlab image $GL_PREV to be updated"
        echo
        echo "Jenkins Repo: $JENKINS_REPO"
        echo "Waiting for Jenkins image $J_PREV to be updated"
    fi
    let COUNT--

    echo "Checking repo contents ..."
    # pass the var name to hold the previus value so it can be updated
    GH_CURRENT=$(getImage $GH_RAW)
    promoteIfUpdated GH_PREV $GH_CURRENT $GITHUB_REPO
    GL_CURRENT=$(getImage $GL_RAW)
    promoteIfUpdated GL_PREV $GL_CURRENT $GITLAB_REPO
    J_CURRENT=$(getImage $J_RAW)
    pushIfUpdated J_PREV $J_CURRENT $JENKINS_REPO
    SLEEP=10
    echo "Sleep..."
    while [[ $SLEEP != 0 ]]; do
        sleep 1
        echo -n "$SLEEP."
        let SLEEP--
    done

done
