# get local test repos to patch
source setup-local-dev-repos.sh
source init-tas-vars.sh

if [ $TEST_REPO_ORG == "redhat-appstudio" ]; then
    echo "Cannot do CI testing using the redhat-appstudio org"
    echo "You must create forks in your own org and set up MY_TEST_REPO_ORG (github) and MY_TEST_REPO_GITLAB_ORG"
    exit
fi

function updateGitAndQuayRefs() {
    if [ -f $1 ]; then
        sed -i "s!quay.io/redhat-appstudio!quay.io/$MY_QUAY_USER!g" $1
        sed -i "s!https://github.com/redhat-appstudio!https://github.com/$MY_GITHUB_USER!g" $1
    fi
}

#Jenkins
echo "Update Jenkins file in $BUILD and $GITOPS"
echo "Jenkins is able to reuse the same Github repo as github actions"
GEN_SRC=generated/source-repo
GEN_GITOPS=generated/gitops-template

cp $GEN_SRC/jenkins/Jenkinsfile $BUILD/Jenkinsfile
cp $GEN_GITOPS/jenkins/Jenkinsfile $GITOPS/Jenkinsfile
updateGitAndQuayRefs $BUILD/Jenkinsfile
updateGitAndQuayRefs $GITOPS/Jenkinsfile

function updateBuild() {
    REPO=$1
    GITOPS_REPO_UPDATE=$2
    mkdir -p $REPO/rhtap
    SETUP_ENV=$REPO/rhtap/env.sh
    cp rhtap/env.template.sh $SETUP_ENV
    sed -i "s!\${{ values.image }}!quay.io/$MY_QUAY_USER/bootstrap!g" $SETUP_ENV
    sed -i "s!\${{ values.dockerfile }}!Dockerfile!g" $SETUP_ENV
    sed -i "s!\${{ values.buildContext }}!.!g" $SETUP_ENV
    sed -i "s!\${{ values.repoURL }}!$GITOPS_REPO_UPDATE!g" $SETUP_ENV
    # Update REKOR_HOST and TUF_MIRROR values directly
    sed -i '/export REKOR_HOST=/d' $SETUP_ENV
    sed -i '/export TUF_MIRROR=/d' $SETUP_ENV
    
    echo ""  >> $SETUP_ENV
    echo "export REKOR_HOST=$REKOR_HOST" >> $SETUP_ENV
    echo "export TUF_MIRROR=$TUF_MIRROR" >> $SETUP_ENV
    echo "# Update forced CI test $(date)" >> $SETUP_ENV
    updateGitAndQuayRefs $SETUP_ENV
    cat $SETUP_ENV
}
# Repos on github and gitlab, github reused for Jenkins
# source repos get the name of the corresponding GITOPS REPO
updateBuild $BUILD $TEST_GITOPS_REPO
updateBuild $GITOPS
updateBuild $GITLAB_BUILD $TEST_GITOPS_GITLAB_REPO
updateBuild $GITLAB_GITOPS

# Gitlab CI
echo "Update .gitlab-ci.yml file in $GITLAB_BUILD and $GITLAB_GITOPS"
cp $GEN_SRC/gitlabci/.gitlab-ci.yml $GITLAB_BUILD/.gitlab-ci.yml
cp $GEN_GITOPS/gitlabci/.gitlab-ci.yml $GITLAB_GITOPS/.gitlab-ci.yml
updateGitAndQuayRefs $GITLAB_BUILD/.gitlab-ci.yml
updateGitAndQuayRefs $GITLAB_GITOPS/.gitlab-ci.yml

# Github Actions
echo "Update .github workflows in $BUILD and $GITOPS"
cp -r $GEN_SRC/githubactions/.github $BUILD
cp -r $GEN_GITOPS/githubactions/.github $GITOPS
for wf in $BUILD/.github/workflows/* $GITOPS/.github/workflows/*; do
    updateGitAndQuayRefs $wf
done

function updateRepos() {
    REPO=$1
    echo
    echo "Updating $REPO"
    pushd $REPO
    git add .
    git commit -m "Testing in CI"
    git push
    popd
}

# github
updateRepos $BUILD
updateRepos $GITOPS
# gitlab
updateRepos $GITLAB_BUILD
updateRepos $GITLAB_GITOPS

bash hack/ghub-set-vars $TEST_BUILD_REPO
bash hack/ghub-set-vars $TEST_GITOPS_REPO
bash hack/glab-set-vars $(basename $TEST_BUILD_GITLAB_REPO)
bash hack/glab-set-vars $(basename $TEST_GITOPS_GITLAB_REPO)

echo "Github Build and Gitops Repos"
echo "Build: $TEST_BUILD_REPO"
echo "Gitops: $TEST_GITOPS_REPO"

echo "Gitlab Build and Gitops Repos"
echo "Build: $TEST_BUILD_GITLAB_REPO"
echo "Gitops: $TEST_GITOPS_GITLAB_REPO"
