#!/bin/bash
set -e

COMMAND=${1:-shell}

docker compose build

case "$COMMAND" in
  shell)
    docker compose run --rm flutter bash
    ;;
  build)
    docker compose run --rm flutter flutter build apk --debug
    ;;
  *)
    docker compose run --rm flutter "$@"
    ;;
esac
