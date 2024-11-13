echo "Configure the repos for Innerloop dev"

TEST_REPO_ORG="${MY_TEST_REPO_ORG:-redhat-appstudio}"
TEST_REPO_GITLAB_ORG="${MY_TEST_REPO_GITLAB_ORG:-redhat-appstudio}"

if [ $TEST_REPO_ORG == "redhat-appstudio" ]; then
    echo "Build can use redhat-appstudio directly, gitops needs a forked repo."
    echo "Set up a github and gitlab fork in github and gitlab "
    echo "Pass org names in MY_TEST_REPO_ORG and MY_TEST_REPO_GITLAB_ORG"
fi
if [ $TEST_REPO_GITLAB_ORG == "redhat-appstudio" ]; then
    echo "WARNING: Gitops may not use redhat-appstudio, gitops needs a forked repo."
    echo "Set up a github and gitlab fork in github and gitlab "
    echo "Pass org names in MY_TEST_REPO_ORG and MY_TEST_REPO_GITLAB_ORG"
fi

# this will be copied into a temp directory
# pipelines will be pushed into it for local test
# build and gitops on gitlab
TEST_BUILD_REPO=https://github.com/$TEST_REPO_ORG/devfile-sample-nodejs-dance

# These repos are all optional, if they don't exist, the build can continue
TEST_GITOPS_REPO=https://github.com/$TEST_REPO_ORG/tssc-dev-gitops

TEST_BUILD_GITLAB_REPO=https://gitlab.com/$TEST_REPO_GITLAB_ORG/devfile-sample-nodejs-dance
TEST_GITOPS_GITLAB_REPO=https://gitlab.com/$TEST_REPO_GITLAB_ORG/tssc-dev-gitops

TEST_BUILD_JENKINS_REPO=https://github.com/$TEST_REPO_ORG/tssc-dev-source-jenkins
TEST_GITOPS_JENKINS_REPO=https://github.com/$TEST_REPO_ORG/tssc-dev-gitops-jenkins

# If you prefer to use ssh git urls
if [ -n "$USE_SSH_GIT_URLS" ]; then
    TEST_BUILD_REPO_SSH=git@github.com:$TEST_REPO_ORG/devfile-sample-nodejs-dance.git
    TEST_GITOPS_REPO_SSH=git@github.com:$TEST_REPO_ORG/tssc-dev-gitops.git
    TEST_BUILD_GITLAB_REPO_SSH=git@gitlab.com:$TEST_REPO_GITLAB_ORG/devfile-sample-nodejs-dance.git
    TEST_GITOPS_GITLAB_REPO_SSH=git@gitlab.com:$TEST_REPO_GITLAB_ORG/tssc-dev-gitops.git
    TEST_BUILD_JENKINS_REPO_SSH=git@github.com:$TEST_REPO_ORG/tssc-dev-source-jenkins.git
    TEST_GITOPS_JENKINS_REPO_SSH=git@github.com:$TEST_REPO_ORG/tssc-dev-gitops-jenkins.git
fi

function cloneIfRepoExists() {
    REPO=$1
    REPO_HTTPS=$2
    # $REPO and $REPO_HTTPS are the same unless $USE_SSH_GIT_URLS is set
    DEST=$3
    echo "Test repo $REPO and clone into $DEST"

    REPO_EXISTS=$(curl -s -o /dev/null -I -w "%{http_code}" $REPO_HTTPS)
    # 200 == exists
    # 404 == does not exist
    if [ $REPO_EXISTS == 200 ]; then
        echo "Clone source: $REPO into : $DEST"
        git clone --quiet $REPO $DEST > /dev/null
    else
        echo "Wadning No Repo $REPO to initialize $DEST"
    fi
}

# clone if repos exist, disable gitops
# Github in build/gitops
# Gitlab in gitlab-build, gitlab-gitops

TMP_REPOS=tmp
rm -rf $TMP_REPOS/*
BUILD=$TMP_REPOS/build
GITOPS=$TMP_REPOS/gitops
GITLAB_BUILD=$TMP_REPOS/gitlab-build
GITLAB_GITOPS=$TMP_REPOS/gitlab-gitops
JENKINS_BUILD=$TMP_REPOS/jenkins-build
JENKINS_GITOPS=$TMP_REPOS/jenkins-gitops

cloneIfRepoExists ${TEST_BUILD_REPO_SSH:-$TEST_BUILD_REPO} $TEST_BUILD_REPO $BUILD
cloneIfRepoExists ${TEST_GITOPS_REPO_SSH:-$TEST_GITOPS_REPO} $TEST_GITOPS_REPO $GITOPS
cloneIfRepoExists ${TEST_BUILD_GITLAB_REPO_SSH:-$TEST_BUILD_GITLAB_REPO} $TEST_BUILD_GITLAB_REPO $GITLAB_BUILD
cloneIfRepoExists ${TEST_GITOPS_GITLAB_REPO_SSH:-$TEST_GITOPS_GITLAB_REPO} $TEST_GITOPS_GITLAB_REPO $GITLAB_GITOPS
cloneIfRepoExists ${TEST_BUILD_JENKINS_REPO_SSH:-$TEST_BUILD_JENKINS_REPO} $TEST_BUILD_JENKINS_REPO $JENKINS_BUILD
cloneIfRepoExists ${TEST_GITOPS_JENKINS_REPO_SSH:-$TEST_GITOPS_JENKINS_REPO} $TEST_GITOPS_JENKINS_REPO $JENKINS_GITOPS

# WARNING - if GITOPS_REPO_URL is set, update deployment will try to update
# the gitops repo. Disable this here if the gitops repo is NOT a fork
if [ $TEST_REPO_ORG == "redhat-appstudio" ]; then
    echo "------------- INFO-------------"
    echo "DISABLING GITOPS REPO UPDATE for the "redhat-appstudio" org"
    echo "This prevents random accidental updates to the shared repo by dev team members with access"
    export DISABLE_GITOPS_UPDATE=true
    echo "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
    echo
fi
