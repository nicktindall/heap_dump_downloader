set -e

if [ -e env.sh ]; then
    source env.sh
fi

# QA ES_URL=https://overview.es.eu-west-1.aws.qa.cld.elstc.co
# PROD ES_URL=https://overview.elastic-cloud.com

# example QA by document: 
#    ./get_heap_dump.sh -d Uwkt-ZgBzqlaqEDesf7A
# example QA project and time range: 
#    ./get_heap_dump.sh -s '2025-09-01T07:10:00.000Z' -e '2025-09-01T07:31:58.172Z' -p 'c75b948caa2e460ca8162a0ccbf0f853'

if [[ -z "${ES_URL}" || -z "${API_KEY}" ]]; then
    echo "Error: Set ES_URL and API_KEY environment variables before running this"
    exit 1
fi

usage() {
    echo "Usage: $0 [-s START_TIMESTAMP -e END_TIMESTAMP -p PROJECT_ID]"
    echo "Or: $0 [-d DOCUMENT_ID]"
    exit 1
}

while getopts "s:e:p:d:" opt; do
    case "${opt}" in
        s)
            START_TIMESTAMP="${OPTARG}"
            ;;
        e)
            END_TIMESTAMP="${OPTARG}"
            ;;
        p)
            PROJECT_ID="${OPTARG}"
            ;;
        d)
            DOCUMENT_ID="${OPTARG}"
            ;;
        \?) # Unrecognized option
            usage
            ;;
    esac
done

if [[ -n "${DOCUMENT_ID}" ]]; then
    echo "Fetching heap dump for document ${DOCUMENT_ID}"
    RESULT=$(curl -X POST "${ES_URL}/serverless-logging-*:logs-elasticsearch*/_search?pretty=true" \
        -d "{\"query\": {\"ids\": {\"values\":[\"$DOCUMENT_ID\"]}}}" \
        -H "Authorization: ApiKey ${API_KEY}" \
        -H "Content-Type: application/json")
elif [[ -n "${PROJECT_ID}" && -n "${START_TIMESTAMP}" && -n "${END_TIMESTAMP}" ]]; then
    echo "Fetching heap dumps for project ${PROJECT_ID} between ${START_TIMESTAMP} and ${END_TIMESTAMP}"
    RESULT=$(curl -X POST "${ES_URL}/serverless-logging-*:logs-elasticsearch*/_search?pretty=true" \
        -d "{\"query\": {\"bool\": {\"filter\": [ \
                {\"term\": {\"serverless.project.id\": \"$PROJECT_ID\"}}, \
                {\"range\": {\"@timestamp\": {\"gte\": \"${START_TIMESTAMP}\", \"lte\": \"${END_TIMESTAMP}\"}}}, \
                {\"match\": {\"message\": {\"query\": \"(gzip compressed\", \"operator\": \"AND\"}}} \
            ]}}}" \
        -H "Authorization: ApiKey ${API_KEY}" \
        -H "Content-Type: application/json")
else
    usage
fi

COUNT=$(echo $RESULT | jq ".hits.total.value")

if [ "$COUNT" -eq "0" ]; then
    echo "No results found"
    exit 1
else
    echo "Found $COUNT"
fi

HEAP_DUMPS=$(echo $RESULT | jq "[ .hits.hits.[] | { \
                    \"prefix\": ._source.message | split(\" (gzip\")[0], \
                    \"project\": ._source.kubernetes.labels.[\"k8s_elastic_co/project-id\"], \
                    \"node\": ._source.elasticsearch.node.name, \
                    \"ts\": ._source.[\"@timestamp\"], \
                    \"parts\": (._source.message | match(\".*split into (\\\\d+) parts.*\").captures[0].string | tonumber)} ]")
echo "Found: $HEAP_DUMPS"

jq -c '.[]' <<< "$HEAP_DUMPS" | while read -r item; do
    prefix=$(jq -r '.prefix' <<< "$item")
    project=$(jq -r '.project' <<< "$item")
    node=$(jq -r '.node' <<< "$item")
    ts=$(jq -r '.ts' <<< "$item")
    parts=$(jq -r '.parts' <<< "$item")

    limit=$(($parts + 1))

    echo "Processing: $project:$node@$ts - $prefix"
    ONE_DUMP=$(curl -X POST "${ES_URL}/serverless-logging-*:logs-elasticsearch*/_search?pretty=true" \
        -d "{\"query\": {\"bool\": {\"filter\": [{\"term\": {\"serverless.project.id\":\"$project\"}}, \
                                             {\"term\": {\"kubernetes.pod.name\": \"$node\"}}, \
                                             {\"range\": {\"@timestamp\": {\"lte\":\"$ts\", \"gte\":\"$ts||-1m\"}}} \
                                            ], \
                                \"must\": {\"query_string\": {\"query\": \"\\\"$prefix\\\"*\"}} \
                                } \
                    }, \"size\": \"$limit\"}" \
        -H "Authorization: ApiKey ${API_KEY}" \
        -H "Content-Type: application/json")
    # Filter out the summary line
    BASE64_HD=$(echo $ONE_DUMP | jq "[ .hits.hits.[] | select(._source.message | startswith(\"$prefix (gzip\") | not) ]")
    # Pull the part number out and sort on it
    BASE64_HD=$(echo $BASE64_HD | jq "[ .[] | ._source.message | {\"index\": (. | match(\"\\\\[part (\\\\d+)\\\\]\").captures[0].string | tonumber), \"message\": .} ] | sort_by(.index)")
    # Extract the base64 strings and concatenate them
    BASE64_HD=$(echo $BASE64_HD | jq -r ".[] | .message | match(\".*\\\\[part \\\\d+\\\\]:\\\\s(\\\\S*)\").captures[0].string")
    filename="heapdumps/${project}_${node}_$(echo $ts | sed s/://g)_heap_dump.txt"
    echo $BASE64_HD | base64 --decode | gzip --decompress > $filename
    echo "Wrote heap dump to $filename"
    
done