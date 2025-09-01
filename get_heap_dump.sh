source env.sh

DOCUMENT_ID=Uwkt-ZgBzqlaqEDesf7A

RESULT=$(curl -X POST "${ES_URL}/serverless-logging-*:logs-elasticsearch*/_search?pretty=true" \
    -d "{\"query\": {\"ids\": {\"values\":[\"$DOCUMENT_ID\"]}}}" \
    -H "Authorization: ApiKey ${API_KEY}" \
    -H "Content-Type: application/json")

COUNT=$(echo $RESULT | jq ".hits.total.value")
echo "Found $COUNT"

HEAP_DUMPS=$(echo $RESULT | jq ".hits.hits.[] | [{ \"prefix\": ._source.message | split(\" (gzip\")[0], \"project\": ._source.kubernetes.labels.[\"k8s_elastic_co/project-id\"], \"node\": ._source.elasticsearch.node.name, "ts": ._source.[\"@timestamp\"] }]")
echo "Found: $HEAP_DUMPS"

jq -c '.[]' <<< "$HEAP_DUMPS" | while read -r item; do
    prefix=$(jq -r '.prefix' <<< "$item")
    project=$(jq -r '.project' <<< "$item")
    node=$(jq -r '.node' <<< "$item")
    ts=$(jq -r '.ts' <<< "$item")

    echo "Processing: $project:$node@$ts - $prefix"
    ONE_DUMP=$(curl -X POST "${ES_URL}/serverless-logging-*:logs-elasticsearch*/_search?pretty=true" \
        -d "{\"query\": {\"bool\": {\"filter\": [{\"term\": {\"serverless.project.id\":\"$project\"}}, \
                                             {\"term\": {\"kubernetes.pod.name\": \"$node\"}}, \
                                             {\"range\": {\"@timestamp\": {\"lte\":\"$ts\", \"gte\":\"$ts||-1m\"}}} \
                                            ], \
                                \"must\": {\"match\": {\"message\": {\"query\": \"$prefix*\", \"operator\": \"AND\"}}} \
                                } \
                    }}" \
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