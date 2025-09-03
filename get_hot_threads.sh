set -e

# example QA by document: 
#    ./get_hot_threads.sh -n qa e-d Uwkt-ZgBzqlaqEDesf7A
# example QA project and time range: 
#    ./get_hot_threads.sh -n qa -s '2025-09-01T07:10:00.000Z' -e '2025-09-01T07:31:58.172Z' -p 'c75b948caa2e460ca8162a0ccbf0f853'

usage() {
    echo "Usage: $0 [-n (qa|prod)] [-s START_TIMESTAMP -e END_TIMESTAMP -p PROJECT_ID]"
    echo "Or: $0 [-n (qa|prod)] [-d DOCUMENT_ID]"
    exit 1
}

# Default env to prod
ENV="prod"
while getopts "n:s:e:p:d:" opt; do
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
        n)
            if [[ "${OPTARG}" == "qa" || "${OPTARG}" == "prod" ]]; then
                ENV="${OPTARG}"
            else
                usage
            fi
            ;;
        \?) # Unrecognized option
            usage
            ;;
    esac
done

# Get the API key
API_KEY=$(security find-generic-password -a $USER -s "hot_threads_downloader_api_key_$ENV" -w)

echo "Using API_KEY=$API_KEY"

# Set the endpoint for the environment
if [[ $ENV == "prod" ]]; then
    # TODO: not sure if this is right, or how to create API keys here
    ES_URL=https://overview-elastic-cloud-com.es.us-east-1.aws.found.io
elif [[ $ENV == "qa" ]]; then
    ES_URL=https://overview.es.eu-west-1.aws.qa.cld.elstc.co
fi

# Fetch the summary line(s)
if [[ -n "${DOCUMENT_ID}" ]]; then
    echo "Fetching hot threads for document ${DOCUMENT_ID}"
    RESULT=$(curl -X POST "${ES_URL}/serverless-logging-*:logs-elasticsearch*/_search?pretty=true" \
        -d "{\"query\": {\"ids\": {\"values\":[\"$DOCUMENT_ID\"]}}, \
             \"_source\": [\"message\", \"kubernetes.labels.k8s_elastic_co/project-id\", \"@timestamp\", \"elasticsearch.node.name\"] \
            }" \
        -H "Authorization: ApiKey ${API_KEY}" \
        -H "Content-Type: application/json")
elif [[ -n "${PROJECT_ID}" && -n "${START_TIMESTAMP}" && -n "${END_TIMESTAMP}" ]]; then
    echo "Fetching hot threads for project ${PROJECT_ID} between ${START_TIMESTAMP} and ${END_TIMESTAMP}"
    RESULT=$(curl -X POST "${ES_URL}/serverless-logging-*:logs-elasticsearch*/_search?pretty=true" \
        -d "{\"query\": {\"bool\": {\"filter\": [ \
                {\"term\": {\"serverless.project.id\": \"$PROJECT_ID\"}}, \
                {\"range\": {\"@timestamp\": {\"gte\": \"${START_TIMESTAMP}\", \"lte\": \"${END_TIMESTAMP}\"}}}, \
                {\"match\": {\"message\": {\"query\": \"(gzip compressed\", \"operator\": \"AND\"}}} \
            ]}}, \"_source\": [\"message\", \"kubernetes.labels.k8s_elastic_co/project-id\", \"@timestamp\", \"elasticsearch.node.name\"]}" \
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

# Pull out relevant info
HOT_THREADS=$(echo $RESULT | jq "[ .hits.hits.[] | { \
                    \"prefix\": ._source.message | split(\" (gzip\")[0], \
                    \"project\": ._source.kubernetes.labels.[\"k8s_elastic_co/project-id\"], \
                    \"node\": ._source.elasticsearch.node.name, \
                    \"ts\": ._source.[\"@timestamp\"], \
                    \"parts\": (._source.message | match(\".*split into (\\\\d+) parts.*\").captures[0].string | tonumber)} ]")
echo "Found: $HOT_THREADS"

# Fetch each hot threads
jq -c '.[]' <<< "$HOT_THREADS" | while read -r item; do
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
                    }, 
                \"size\": \"$limit\", \
                \"_source\": [\"message\"] \
            }" \
        -H "Authorization: ApiKey ${API_KEY}" \
        -H "Content-Type: application/json")
    # Filter out the summary line
    BASE64_HD=$(echo $ONE_DUMP | jq "[ .hits.hits.[] | select(._source.message | startswith(\"$prefix (gzip\") | not) ]")
    # Pull the part number out and sort on it
    BASE64_HD=$(echo $BASE64_HD | jq "[ .[] | ._source.message | {\"index\": (. | match(\"\\\\[part (\\\\d+)\\\\]\").captures[0].string | tonumber), \"message\": .} ] | sort_by(.index)")
    # Extract the base64 strings and concatenate them
    BASE64_HD=$(echo $BASE64_HD | jq -r ".[] | .message | match(\".*\\\\[part \\\\d+\\\\]:\\\\s(\\\\S*)\").captures[0].string")
    filename="hotthreads/${project}_${node}_$(echo $ts | sed s/://g)_hot_threads.txt"
    mkdir -p hotthreads
    echo $BASE64_HD | base64 --decode | gzip --decompress > $filename
    echo "Wrote hot threads to $filename"
    
done
