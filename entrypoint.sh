#!/bin/sh -l
# Inspired by https://github.com/cpina/github-action-push-to-another-repository

set -e  # if a command fails it stops the execution
set -u  # script fails if trying to access to an undefined variable
set -x

echo "[+] Action start"
USER_NAME="${1}"
USER_EMAIL="${2}"
GITHUB_SERVER="${3}"
SOURCE_DIRECTORY="${4}"
DESTINATION_GITHUB_USERNAME="${5}"
DESTINATION_REPOSITORY_USERNAME="${6}"
DESTINATION_REPOSITORY_NAME="${7}"
TARGET_BRANCH="${8}"
BASE_BRANCH="${9}"
TARGET_DIRECTORY="${10}"
COMMIT_MESSAGE="${11}"
PR_TITLE="${12}"


# -z flag causes test to check whether a string is empty - return true if string is empty 
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

if [ -z "$PR_TITLE"]
then 
	PR_TITLE="PR-for-$WORKING_BRANCH"
fi 

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

elif [ -n "${GH_TOKEN:=}" ]
then
	echo "[+] Using GH_TOKEN"
	GIT_CMD_REPOSITORY="https://$DESTINATION_REPOSITORY_USERNAME:$GH_TOKEN@$GITHUB_SERVER/$DESTINATION_REPOSITORY_USERNAME/$DESTINATION_REPOSITORY_NAME.git"
else
	echo "::error::GH_TOKEN and SSH_DEPLOY_KEY are empty. Please fill one (recommended the SSH_DEPLOY_KEY)"
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
	echo "::error::Please verify that the target repository exist and is accesible by the GH_TOKEN OR SSH_DEPLOY_KEY"
	exit 1
}
ls -la "$CLONE_DIR_PUSH"

TEMP_DIR=$(mktemp -d)

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
git config --global --add safe.directory "$CLONE_DIR_PUSH"

echo "[+] List branches"
git pull --all
git branch -a

echo "[+] Checking if $TARGET_BRANCH exist"
if git checkout $TARGET_BRANCH
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
gh pr create --title "$PR_TITLE" \
            --body "$COMMIT_MESSAGE" \
            --base $BASE_BRANCH \
            --head $WORKING_BRANCH \
			--draft
