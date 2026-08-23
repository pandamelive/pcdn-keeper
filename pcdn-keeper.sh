#!/bin/sh
set -e

# pcdn-keeper placeholder entrypoint
# - This file was added to fix the Docker build error where the Dockerfile expects /app/pcdn-keeper.sh
# - Replace this placeholder with the real application logic when available.

if [ "$#" -gt 0 ]; then
  exec "$@"
else
  echo "pcdn-keeper placeholder: no command provided, keeping container alive"
  exec tail -f /dev/null
fi
