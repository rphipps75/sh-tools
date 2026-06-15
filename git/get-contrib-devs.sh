#!/bin/bash

GIT_OUTPUT_TXT="contrib-devs.txt"
CONTRIB_DEVS_JSON="contrib-devs.json"
CONTRIB_DEVS_COUNT_JSON="contrib-devs-count.json"

TMP_GIT_OUTPUT="contrib-devs-git.tmp"
#TMP_CONTRIB_DEVS="contrib-devs-2.tmp"

CREATE_GIT_OUTPUT_TXT=0
CREATE_CONTRIB_DEVS_JSON=1

# get list of all developers and their commit count from the last 90 days for repo in current folder.
## git_output=$(git shortlog --all --summary --since "90 days")
git log --since "90 days" --format='%aN%x09%aE' | sort | uniq -c | awk -F'\t' '{print $1 "\t" $2}' > $TMP_GIT_OUTPUT
# format
sed -i 's/^[[:space:]]*\([0-9]\) /\1\t/g' $TMP_GIT_OUTPUT
# sort by column 2 (name) case insensitive
sort -f -k 2 -o $TMP_GIT_OUTPUT $TMP_GIT_OUTPUT

# convert the TAB separated values output from git to JSON. Making sure to escape double quotes for developers name.
json_output=$(cat $TMP_GIT_OUTPUT | awk -F'\t' 'BEGIN {print "["} {print (NR==1 ? "" : ",")} {gsub(/"/, "\\\""); print "{\"author\": \"" $2 "\", \"email\": \"" $3 "\", \"commits\": " int($1) "}" } END {print "]"}')
if [ "$CREATE_CONTRIB_DEVS_JSON" == 1 ]; then
    echo "$json_output" | jq '.' > $CONTRIB_DEVS_JSON
    # echo "$json_output" > $TMP_CONTRIB_DEVS
    # jq '.' $TMP_CONTRIB_DEVS > $CONTRIB_DEVS_JSON
    # rm -f $TMP_CONTRIB_DEVS
fi

if [ "$CREATE_GIT_OUTPUT_TXT" == 1 ]; then
    cp $TMP_GIT_OUTPUT $GIT_OUTPUT_TXT
fi
rm -f $TMP_GIT_OUTPUT

## total_devs=$(echo "$json_output" | jq '{ "totalDevelopers": length }')

# count number of developers
total_devs=$(echo "$json_output" | jq '[.[] | select(.author != "dependabot[bot]" and .author != "GitHub Action")] | { "totalDevelopers": length }')
echo "$total_devs" > $CONTRIB_DEVS_COUNT_JSON