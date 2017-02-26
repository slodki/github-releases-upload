#!/usr/bin/env bash

: ${GITHUB_TOKEN:?Error: GitHub token must be set as env variable.}
: ${1:?Error: repo slug (user/project) must be set as 1st parameter.}
: ${2:?Error: Git tag value for release must be set as 2nd parameter.}
: ${3:?Error: File name to upload must be set as 3rd parameter.}
# $4 (optional) - 'draft' value (default) if created release should be draft, other value if not
# $5 (optional) - target commitish, default branch HEAD if not set (optional)
# $6 (optional) - release name (optional)
# $7 (optional) - release description in markdown (optional)

AUTH="Authorization: token $GITHUB_TOKEN"
API="https://api.github.com/repos/$1/releases"
URL="https://uploads.github.com/repos/$1/releases"

type curl >&/dev/null || { >&2 echo 'Error: curl not found.'; exit 1; }
[[ -r "$3" ]] || { >&2 echo "Error: can't read file '$3'."; exit 2; }

trim() {
  local var="$*"
  var="${var#"${var%%[![:space:]]*}"}"
  echo -n "${var%"${var##*[![:space:]]}"}"
}

read_id_from_json() {
# input: $1 - json response from API (required)
#        $2 - tag name to be searched (required)
#        $3 - tag value to be searched (required)
# output: release id if tag found

  list="$1"
  re='^[^{[]*\[(([^][]*\[[^][]*])*[^][]*)][^]}]*' # get first list elements
  [[ "$list" =~ $re ]] && list="${BASH_REMATCH[1]}"
  list="$(trim "$list")"

  # iterate through all elements
  while [[ "$list" ]]; do

    re1='^[^{]*\{[^}{]*\{' # subsection exists in first element
    re='^([^{]*\{[^}]*)(\{[^}{]*})(.*)' # remove subsections from first element
    while [[ "$list" =~ $re1 && "$list" =~ $re ]]; do
      list="${BASH_REMATCH[1]}${BASH_REMATCH[3]}"
    done

    re='^[^{]*\{([^}]*)}(.*)$' # first element content
    if [[ "$list" =~ $re ]]; then
      first="${BASH_REMATCH[1]}"
      list="$(trim "${BASH_REMATCH[2]}")"
    fi

    re='"'"$2"'"[[:space:]]*:[[:space:]]*"([^"]*)"'
    [[ "$first" =~ $re ]] && tag="${BASH_REMATCH[1]}"

    if [[ "$3" == "$tag" ]]; then
      re='"id"[[:space:]]*:[[:space:]]*([0-9]+)'
      [[ "$first" =~ $re ]] && id="${BASH_REMATCH[1]}"
      echo -n "$id"
      return
    fi
  done
}

find_release_id() {
# input: $1 - tag name (required)
# output: release id if found
  read_id_from_json "$(curl -q -s -H "$AUTH" "$API")" "tag_name" "$1"
}

create_release() {
# input: $1 - tag name (required)
#        $2 - 'draft' value to set release as draft (required)
#        $3 - target commitish, default branch HEAD if not set (optional)
#        $4 - release name (optional)
#        $5 - release description in markdown (optional)
# output: release id if created
  [[ "$2" == "draft" ]] && draft=1
  read_id_from_json "$( echo "{ \"tag_name\": \"$1\"${draft:+, \"draft\": true}${3:+, \"target_commitish\": \"$3\"${4:+, \"name\": \"$4\"${5:+, \"body\": \"$5\"}}} }" | curl -q -s -H "$AUTH" -d @- "$API" )" "tag_name" "$1"
}

find_file_id() {
# input: $1 - release id (required)
#        $2 - filename (required)
# output: asset id if found
  read_id_from_json "$(curl -q -s -H "$AUTH" "$API/$1/assets")" "name" "${2##*/}"
}

delete_file() {
# input: $1 - asset id (required)
# output: none
  curl -q -sS -H "$AUTH" -X DELETE "$API/assets/$1"
}

upload_file() {
# input: $1 - release id (required)
#        $2 - filename (required)
#        $3 - mime-type (optional)
# output: 'uploaded' if success
  mime=${3:-$(file -b --mime-type "$2" 2>/dev/null || echo application/octet-stream)}
  resp="$(curl -q -s -H "$AUTH" -T "$2" -X POST -H "Content-Type: $mime" -G --data-urlencode "name=${2##*/}" "$URL/$1/assets")"
  re='"state"[[:space:]]*:[[:space:]]*"([^"]*)"'
  [[ "$resp" =~ $re ]] && echo -n "${BASH_REMATCH[1]}" ||:
}

id="$(find_release_id "$2")"
[[ "$id" ]] || id="$(create_release "$2" "${4:-draft}" "$5" "$6" "$7")"
fid="$(find_file_id "$id" "$3")"
[[ "$fid" ]] && delete_file "$fid"
[[ "$(upload_file "$id" "$3")" == "uploaded" ]] || exit 3
