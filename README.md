# Hot threads downloader

Downloads hot threads from the observability clusters and assembles and decompresses them

Required environment variables
- `API_KEY`: An API key for the cluster (an ES API key, created with [this endpoint](https://www.elastic.co/docs/api/doc/elasticsearch/operation/operation-security-create-api-key))
- `ES_URL`: The URL for the cluster you're targeting

## Usage

### Get the hot threads for the summary document with the specified ID.

The "summary document" is the log line that says... 
```
... (gzip compressed, base64-encoded, and split into 7 parts on preceding log lines; for details see https://www.elastic.co/docs/deploy-manage/monitor/logging-configuration/elasticsearch-deprecation-logs?version=current)`)
```
Example:
```
./get_hot_threads.sh -d {a-document-id}
```

### Get all hot threads for a project between two timestamps

Example:

```
./get_hot_threads.sh -s {start-timestamp} -e {end-timestamp} -p {project-id}
```

timestamps are anything that will fit into [a `range` query's `gte` and `lte` fields](https://www.elastic.co/docs/reference/query-languages/query-dsl/query-dsl-range-query#ranges-on-dates). e.g. ISO strings (e.g. `2025-09-01T07:10:00.000Z`)
