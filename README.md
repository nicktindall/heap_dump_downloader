# Hot threads downloader

Downloads hot threads from the observability clusters and assembles and decompresses them

## Usage

### You need to store your API keys in the keychain first
```
./add_api_key.sh (prod|qa)
```

Will prompt you for the API key to add and write it to the keychain, this will be used by the tool subsequently

### Get the hot threads for the summary document with the specified ID.

The "summary document" is the log line that says... 
```
... (gzip compressed, base64-encoded, and split into 7 parts on preceding log lines; for details see https://www.elastic.co/docs/deploy-manage/monitor/logging-configuration/elasticsearch-deprecation-logs?version=current)
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

### Other options

```
    -n (prod|qa)     Specify the environment to connect to, defaults to prod
```

timestamps are anything that will fit into [a `range` query's `gte` and `lte` fields](https://www.elastic.co/docs/reference/query-languages/query-dsl/query-dsl-range-query#ranges-on-dates). e.g. ISO strings (e.g. `2025-09-01T07:10:00.000Z`)
