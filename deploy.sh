#!/bin/bash

echo -e "\033[0;32mDeploying updates to qimin.me...\033[0m"

#######################################################
# Push source changes to github hugosite.git
#######################################################
git add .

msg="rebuilding site `date`"
if [ $# -eq 1 ]
  then msg="$1"
fi
git commit -m "$msg"

git push origin master

echo -e "\033[0;32mDeploying updates to mooncaker816.github.io...\033[0m"
#######################################################
# deploy mooncaker816.github.io
#######################################################
rm -rf public/*

hugo --config config.toml,config.github.toml

# Go To Public folder
cd public
# Add changes to git.
git add .

# Commit changes.
msg="rebuilding site `date`"
if [ $# -eq 1 ]
  then msg="$1"
fi
git commit -m "$msg"

# Push source and build repos.
git push origin master

cd ..

echo -e "\033[0;32mDeploying updates to mooncaker816.coding.me...\033[0m"

#######################################################
# deploy mooncaker816.coding.me
#######################################################
rm -rf docs/*

hugo --config config.toml,config.coding.toml --destination docs

# go to docs to deploy for coding
cd docs
# Add changes to git.
git add .

# Commit changes.
msg="rebuilding site `date`"
if [ $# -eq 1 ]
  then msg="$1"
fi
git commit -m "$msg"

# Push source and build repos.
git push origin master

