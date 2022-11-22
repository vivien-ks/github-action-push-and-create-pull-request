#!/bin/sh -l

set -e  # if a command fails it stops the execution
set -u  # script fails if trying to access to an undefined variable
set -x

echo "[+] Action start"
SOURCE_BEFORE_DIRECTORY="${1}"
SOURCE_DIRECTORY="${2}"
DESTINATION_GITHUB_USERNAME="${3}"
DESTINATION_REPOSITORY_NAME="${4}"
GITHUB_SERVER="${5}"
USER_EMAIL="${6}"
USER_NAME="${7}"
DESTINATION_REPOSITORY_USERNAME="${8}"
TARGET_BRANCH="${9}"
COMMIT_MESSAGE="${10}"
TARGET_DIRECTORY="${11}"
BASE_BRANCH="${12}"
PULL_REQUEST_REVIEWERS="${13}"

if [ -z "$DESTINATION_REPOSITORY_USERNAME" ]
then
	DESTINATION_REPOSITORY_USERNAME="$DESTINATION_GITHUB_USERNAME"
fi

if [ -z "$USER_NAME" ]
then
	USER_NAME="$DESTINATION_GITHUB_USERNAME"
fi

if [ $TARGET_BRANCH == "main" ] || [ $TARGET_BRANCH == "master"]
then
  echo "target-branch cannot be 'main' nor 'master'"
  return -1
fi

# if [ -z "$PULL_REQUEST_REVIEWERS" ]
# then
#   PULL_REQUEST_REVIEWERS_LIST=$PULL_REQUEST_REVIEWERS
# else
#   PULL_REQUEST_REVIEWERS_LIST='-r '$PULL_REQUEST_REVIEWERS
# fi

# Verify that there (potentially) some access to the destination repository
# and set up git (with GIT_CMD variable) and GIT_CMD_REPOSITORY
if [ -n "${SSH_DEPLOY_KEY:=}" ]
then
	echo "[+] Using SSH_DEPLOY_KEY"

	# Inspired by https://github.com/leigholiver/commit-with-deploy-key/blob/main/entrypoint.sh , thanks!
	mkdir --parents "$HOME/.ssh"
	DEPLOY_KEY_FILE="$HOME/.ssh/deploy_key"
	echo "${SSH_DEPLOY_KEY}" > "$DEPLOY_KEY_FILE"
	chmod 600 "$DEPLOY_KEY_FILE"

	SSH_KNOWN_HOSTS_FILE="$HOME/.ssh/known_hosts"
	ssh-keyscan -H "$GITHUB_SERVER" > "$SSH_KNOWN_HOSTS_FILE"

	export GIT_SSH_COMMAND="ssh -i "$DEPLOY_KEY_FILE" -o UserKnownHostsFile=$SSH_KNOWN_HOSTS_FILE"

	GIT_CMD_REPOSITORY="git@$GITHUB_SERVER:$DESTINATION_REPOSITORY_USERNAME/$DESTINATION_REPOSITORY_NAME.git"

elif [ -n "${API_TOKEN_GITHUB:=}" ]
then
	echo "[+] Using API_TOKEN_GITHUB"
	GIT_CMD_REPOSITORY="https://$DESTINATION_REPOSITORY_USERNAME:$API_TOKEN_GITHUB@$GITHUB_SERVER/$DESTINATION_REPOSITORY_USERNAME/$DESTINATION_REPOSITORY_NAME.git"
else
	echo "::error::API_TOKEN_GITHUB and SSH_DEPLOY_KEY are empty. Please fill one (recommended the SSH_DEPLOY_KEY)"
	exit 1
fi

CLONE_DIR_PUSH=$(mktemp -d)

echo "[+] Git version"
git --version

echo "[+] Cloning destination git repository $DESTINATION_REPOSITORY_NAME"
# Setup git
git config --global user.email "$USER_EMAIL"
git config --global user.name "$USER_NAME"
git config --global --add safe.directory '*'

{
	git clone "$GIT_CMD_REPOSITORY" "$CLONE_DIR_PUSH"
} || {
	echo "::error::Could not clone the destination repository. Command:"
	echo "::error::git clone "$GIT_CMD_REPOSITORY" "$CLONE_DIR_PUSH""
	echo "::error::(Note that if they exist USER_NAME and API_TOKEN is redacted by GitHub)"
	echo "::error::Please verify that the target repository exist and is accesible by the API_TOKEN_GITHUB OR SSH_DEPLOY_KEY"
	exit 1
}
ls -la "$CLONE_DIR_PUSH"

TEMP_DIR=$(mktemp -d)
# This mv has been the easier way to be able to remove files that were there
# but not anymore. Otherwise we had to remove the files from "$CLONE_DIR_PUSH",
# including "." and with the exception of ".git/"
mv "$CLONE_DIR_PUSH/.git" "$TEMP_DIR/.git"

# $TARGET_DIRECTORY is '' by default
ABSOLUTE_TARGET_DIRECTORY="$CLONE_DIR_PUSH/$TARGET_DIRECTORY/"

echo "[+] Deleting $ABSOLUTE_TARGET_DIRECTORY"
rm -rf "$ABSOLUTE_TARGET_DIRECTORY"

echo "[+] Creating (now empty) $ABSOLUTE_TARGET_DIRECTORY"
mkdir -p "$ABSOLUTE_TARGET_DIRECTORY"

echo "[+] Listing Current Directory Location"
ls -al

echo "[+] Listing root Location"
ls -al /

mv "$TEMP_DIR/.git" "$CLONE_DIR_PUSH/.git"

echo "[+] List contents of $SOURCE_DIRECTORY"
ls "$SOURCE_DIRECTORY"

echo "[+] Checking if local $SOURCE_DIRECTORY exist"
if [ ! -d "$SOURCE_DIRECTORY" ]
then
	echo "ERROR: $SOURCE_DIRECTORY does not exist"
	echo "This directory needs to exist when push-to-another-repository is executed"
	echo
	exit 1
fi

echo "[+] Copying contents of source repository folder $SOURCE_DIRECTORY to folder $TARGET_DIRECTORY in git repo $DESTINATION_REPOSITORY_NAME"
cp -ra "$SOURCE_DIRECTORY"/. "$CLONE_DIR_PUSH/$TARGET_DIRECTORY"
cd "$CLONE_DIR_PUSH"

echo "[+] Files that will be pushed"
ls -la

ORIGIN_COMMIT="https://$GITHUB_SERVER/$GITHUB_REPOSITORY/commit/$GITHUB_SHA"
COMMIT_MESSAGE="${COMMIT_MESSAGE/ORIGIN_COMMIT/$ORIGIN_COMMIT}"
COMMIT_MESSAGE="${COMMIT_MESSAGE/\$GITHUB_REF/$GITHUB_REF}"

echo "[+] Set directory is safe ($CLONE_DIR_PUSH)"
# Related to https://github.com/cpina/github-action-push-to-another-repository/issues/64 and https://github.com/cpina/github-action-push-to-another-repository/issues/64
# TODO: review before releasing it as a version
git config --global --add safe.directory "$CLONE_DIR_PUSH"

echo "[+] List branches"
git pull --all
git branch -a

echo "[+] Checking if $TARGET_BRANCH exist"
if git checkout -b $TARGET_BRANCH
then 
	echo "$TARGET_BRANCH exist"
	WORKING_BRANCH="$TARGET_BRANCH-2" 
else 
	echo " - $TARGET_BRANCH does not exist"
    WORKING_BRANCH=$TARGET_BRANCH
fi

echo "[+] Creating new branch: $WORKING_BRANCH"
git checkout -b "$WORKING_BRANCH"
git push --set-upstream origin "$WORKING_BRANCH"

echo "[+] Adding git commit"
git add .

echo "[+] git status:"
git status

echo "[+] git diff-index:"
# git diff-index : to avoid doing the git commit failing if there are no changes to be commit
git diff-index --quiet HEAD || git commit --message "$COMMIT_MESSAGE"

echo "[+] Checking branches"
git branch 

echo "[+] Pushing git commit"
# --set-upstream: sets de branch when pushing to a branch that does not exist
git push "$GIT_CMD_REPOSITORY" --set-upstream "$WORKING_BRANCH"

echo "[+] Creating a pull request"
# CLONE_DIR_PR=$(mktemp -d)

# export GITHUB_TOKEN=$GH_ACCESS_TOKEN
# git config --global user.email "$USER_EMAIL"
# git config --global user.name "$USER_NAME"

# git clone --branch $TARGET_BRANCH "https://$GITHUB_TOKEN@github.com/$DESTINATION_REPOSITORY_USERNAME/$DESTINATION_REPOSITORY_NAME.git" "$CLONE_DIR_PR"
# cd "$CLONE_DIR_PR"

PR_TITLE="PR-for-$WORKING_BRANCH"

gh pr create --title $PR_TITLE \
            --body $COMMIT_MESSAGE \
            --base $BASE_BRANCH \
            --head $WORKING_BRANCH 
            #    $PULL_REQUEST_REVIEWERS_LIST



# gh config set prompt disabled
# gh config set git_protocol ssh --host github.com
# gh ssh-key add $DEPLOY_KEY_FILE
# Error creating pull request: Not Found (HTTP 404)
# Not Found
# github.com username: github.com password for  (never stored): 

# gh config set git_protocol ssh 
# gh pr create --fill

# export GITHUB_TOKEN=$API_TOKEN_GITHUB
# git config --global user.email "$USER_EMAIL"
# git config --global user.name "$USER_NAME"

# CLONE_DIR_PUSH2=$(mktemp -d)
# git clone "https://$API_TOKEN_GITHUB@github.com/$DESTINATION_GITHUB_USERNAME/$DESTINATION_REPOSITORY_NAME.git" "$CLONE_DIR_PUSH2"
# git checkout -b "$TARGET_BRANCH"

# gh repo clone https://github.com/vivien-ks/repoB.git #(git@github.com:vivien-ks/repoB.git) # need to change this to a variable if it works 
# gh repo clone vivien-ks/repoB #404 - this happens because its authroized and github does not want to leak secret information 
# gh pr create --title $TARGET_BRANCH \
#             --body $TARGET_BRANCH \
#             --base $BASE_BRANCH \
#             --head $TARGET_BRANCH \
#                $PULL_REQUEST_REVIEWERS_LIST


# hub pull-request --no-edit
# 				 -m "$COMMIT_MESSAGE" 
# 				 -h $TARGET_BRANCH
# 				 -b $BASE_BRANCH

# gh config set git_protocol ssh
# gh auth login --git-protocol ssh --with-token < $DEPLOY_KEY_FILE
# gh ssh-key add $DEPLOY_KEY_FILE
# # To use GitHub CLI in a GitHub Actions workflow, set the GH_TOKEN environment variable.
# gh pr create -t $TARGET_BRANCH \
#             -b $TARGET_BRANCH \
#             -B $BASE_BRANCH \
#             -H $TARGET_BRANCH \
#                $PULL_REQUEST_REVIEWERS_LIST