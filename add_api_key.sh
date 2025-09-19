if [[ $1 == "qa" || $1 == "prod" ]]; then
    security add-generic-password -a $USER -s hot_threads_downloader_api_key_$1 -U -w
else
    echo "Error: unknown environment: $1"
    echo "Usage ./add_api_key.sh (qa|prod)"
fi
