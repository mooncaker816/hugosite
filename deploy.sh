#!/bin/bash

echo -e "\033[0;32mDeploying updates to GitHub & Coding...\033[0m"

# Build the project.
hugo # if using a theme, replace with `hugo -t <YOURTHEME>`

# copy build pages to docs folder for coding
cp -r public/* docs/

#######################################################
# deploy mooncaker816.github.io
#######################################################
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

#######################################################
# deploy mooncaker816.coding.me
#######################################################

# go to docs to deploy for coding
cd ../docs
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

#######################################################
# Push source changes to github hugosite.git
#######################################################
cd ..

git add .

msg="rebuilding site `date`"
if [ $# -eq 1 ]
  then msg="$1"
fi
git commit -m "$msg"

git push origin master