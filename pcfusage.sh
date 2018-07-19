#!/bin/bash
PREFIX=dev

#set -e

usage_and_exit() {
  cat <<EOF
Usage: pcfusage <PREFIX> <CMD>[ALL|test] <CSV>[yes/NO]
Examples:
  pcfusage dev - defaults to ALL and NO 
EOF
  exit 1
}

###############################################
# CREATE_ARRAY - Create an array of spaces in the system org we used to filter those apps
###############################################
create_array() {

  system_org_guid=`jq ".[].orgs[]? | select(.name == \"$1\") | .org_guid" ${PREFIX}_foundation.json`
  if [ -z "$system_org_guid" ]; then
    printf "\nOrg $1 not found. Skipping...\n"
    return
  fi

  if [ "$#" -gt 1 ]; then
    arr=$arr","
  fi

  printf "\n$1 Org GUID is $system_org_guid \n"

  spaces=$(cat ${PREFIX}_foundation.json | jq ".[].spaces[]? | select(.org == $system_org_guid) | .space_guid")
  printf "\nSpaces in $1 org are: \n'$spaces' \n"

  c=1
  while read -r line; do
      #echo "... $line ..."
      if [ "$c" -gt "1" ]; then
         arr=$arr","
      fi
      arr=${arr}${line}
      c=$((c + 1))
  done <<< "$spaces"

}

################################################
# Creates CSV file with non system applications
################################################
if [ "$CSV" == "YES" ]; then

  printf "Generating CSV file with only non system apps...\n"

  arr="["
  create_array "system"
  create_array "p-dataflow" ","
  create_array "p-spring-cloud-services" ","
  arr=$arr"]"
  printf "\nSpaces from 'system' Orgs: $arr \n"

  # Filter out all app in system org spaces
  apps=$(cat ${PREFIX}_foundation.json | jq -r "$arr as \$system_spaces | {apps: [.[].apps[]? | select(.space as \$in | \$system_spaces | index(\$in) | not)]}")
  echo $apps > ${PREFIX}_final_apps.json

  jq -r ".apps[] | [.name, .memory, .state, .instances, .buildpack, .space, .updated] | @csv" --compact-output ${PREFIX}_final_apps.json > ${PREFIX}_apps.csv
  rm ${PREFIX}_final_apps.json

  printf "\nCreated '${PREFIX}_apps.csv'!"
fi


################################################
# READ_PAGES - Read CF API pages
# Parms: URL, FILE_NAME and JQ FILTER
################################################
read_pages() {

echo "Reading pages... "
# echo "$1 is the URL to call"
# echo "$2 is the file prefix"
# echo "$3 is the ja filter"

local API_URL=$1
local NAME=$2
local FILTER=$3

local next_url="${1}"
echo $next_url

local c=1

while [[ "${next_url}" != "null" ]]; do
  file_json=$(cf curl ${next_url}) 
  next_url=$(echo $file_json | jq -r -c ".next_url")
  file=$(echo $file_json | jq "[.resources[] | $FILTER]")
  echo $file > ${NAME}_page_${c}.json
  c=$((c + 1))
done
files=$(jq -s "{${NAME}: [.[][]]}" ${NAME}_page_*.json)
echo $files > ${PREFIX}_${NAME}.json
rm ${NAME}_page_*.json 
echo "Done. Created file ${PREFIX}_${NAME}.json"
}

###############################################
# CREATE_USERS - List all users into PREFIX_users.json
###############################################
create_users() {

printf "\ncreating ${PREFIX}_users.json file...\n"  
IFS=$'\n' read -r -d '' line <<"EOF"  
select (.entity.username | test("system_*|smoke_tests|admin|MySQL*|push_apps*"; "i") | not)? |
{guid: .metadata.guid, username: .entity.username, spaces: .entity.spaces_url, orgs: .entity.organizations_url}
EOF
#cf curl "/v2/users" | jq "$(echo $line)" | jq -r '.[] | "\(.username) \(.orgs) \(.spaces) "' > ${PREFIX}_users.txt
read_pages "/v2/users?results-per-page=100" "users" "$line"
jq -r '.users[] | "\(.username) \(.orgs) \(.spaces) "' ${PREFIX}_users.json > ${PREFIX}_users.txt

c=1
while read username orgs_url spaces_url
do

  echo "Collecting orgs and spaces for ${username}..."

  #user_orgs=$(cf curl $orgs_url)
  #orgs=$(echo $user_orgs | jq -r "{ \"${username}\" : [.resources[] | .entity.name ]}")
  #echo $orgs > userOrg_${c}.json

  user_spaces=$(cf curl $spaces_url)
  spaces=$(echo $user_spaces | jq -r "{\"${username}\": [.resources[] | {space: .entity.name, space_guid: .metadata.guid, org_guid: .entity.organization_guid} ]}")
  echo $spaces > user_${c}.json

  c=$((c + 1))
done < ${PREFIX}_users.txt

jq -s "{users: [.[]]}" user_*.json > ${PREFIX}_users.json
rm ${PREFIX}_users.txt user_*.json

printf "\nCreated ${PREFIX}_users.json!"

}
 

###############################################
# CREATE_ORGS - List all organizations into PREFIX_orgs.json
###############################################
create_orgs() {
  printf "\ncreating ${PREFIX}_orgs.json file...\n"
  cf curl "/v2/organizations" | jq '{orgs: [.resources[] | {org_guid: .metadata.guid, name: .entity.name }]}' > ${PREFIX}_orgs.json
}

###############################################
# CREATE_SPACES - List all spaces into PREFIX_spaces.json
###############################################
create_spaces() {
printf "\ncreating ${PREFIX}_spaces.json file...\n"
cf curl "/v2/spaces" | jq '{spaces: [.resources[] | {space_guid: .metadata.guid, name: .entity.name, org: .entity.organization_guid }]}' > ${PREFIX}_spaces.json
}

###############################################
# CREATE_SERVICE - List all service brokers
###############################################
create_services() {
  printf "\ncreating ${PREFIX}_services.json file...\n"
  cf curl "/v2/services" | jq '{services: [.resources[] | {service_guid: .metadata.guid, label: .entity.label, service_broker_guid: .entity.service_broker_guid }]}' > ${PREFIX}_services.json
}

###############################################
# CREATE_APPS - List all apps into PREFIX_apps.json
###############################################
create_service_instances() {
printf "\ncreating ${PREFIX}_service_instances.json file...\n"
read_pages "/v2/service_instances?results-per-page=100" "service_instances" "{name: .entity.name, service_guid: .entity.service_guid, space_guid: .entity.space_guid }"
}

###############################################
# CREATE_APPS - List all apps into PREFIX_apps.json
###############################################
create_apps() {
printf "\ncreating ${PREFIX}_apps.json file...\n"
read_pages "/v2/apps?results-per-page=100" "apps" "{name: .entity.name, memory: .entity.memory, state: .entity.state, instances: .entity.instances, buildpack:  (if .entity.buildpack == null then .entity.detected_buildpack else .entity.buildpack end), space: .entity.space_guid, updated: .entity.package_updated_at}"
}

###############################################
# COMBINE_FILES Combine all json files into previx_foundation.json
###############################################
combine_files() {
  jq --slurp . ${PREFIX}_*.json > ${PREFIX}_foundation.bkp
  rm ${PREFIX}_*.json 
  mv ${PREFIX}_foundation.bkp ${PREFIX}_foundation.json

  printf "\nCombined them into ${PREFIX}_foundation.json - I'm happy with this file.\n\n"
}


###############################################
########## RUNNING ###############
###############################################

if [ "$#" -lt 1 ]; then
    usage_and_exit
fi

PREFIX=${1:-}
CMD=${2:-ALL}
CSV=${3:-NO}

CMD=$( tr '[:lower:]' '[:upper:]' <<< "$CMD" )
CSV=$( tr '[:lower:]' '[:upper:]' <<< "$CSV" )
echo "options: PREFIX: $PREFIX, CMD: $CMD, CSV: $CSV"


if [ "$CMD" == "TEST" ]; then
  create_users
  exit 0
elif [ "$CMD" == "ALL" ]; then
  # Created foundation file, needed for CSV step below
  create_orgs
  create_spaces
  create_users
  create_apps
  create_services
  create_service_instances
  combine_files
else 
  echo "Invalid command $CMD"
  exit 1
fi

