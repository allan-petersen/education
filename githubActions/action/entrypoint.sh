#!/bin/bash
set -e

# if keyword is found
if echo "$*" | grep -i -q FIXED
then
   # do somethng
   echo "Found keyword"
# otherwise
else
  # exit gracefully
  echo "Nothing to process"	 
fi 


URL="https://api.github.com/repos/${GIT_HUB_REPOSITORY}/releases?access_token=${GITHUB_TOKEN}"

echo $DATA | post $URL | jq