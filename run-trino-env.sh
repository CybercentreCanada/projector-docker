#!/bin/sh

set -e # Any command which returns non-zero exit code will cause this shell script to exit immediately
set -x # Activate debugging to show execution details: all commands will be printed before execution

az account show >/dev/null
AZ_LOGIN_STATUS=$?
if [ $AZ_LOGIN_STATUS -ne 0 ]; then
  az login
fi

az acr login --name uchimera >/dev/null
ACR_LOGIN_STATUS=$?
if [ $ACR_LOGIN_STATUS -eq 0 ]; then
  docker run --rm --pull always -p 8887:8887 -v ~/workspaces/trino:/home/projector-user:cached -v ~/repositories/trino:/workspace/trino:cached -it uchimera.azurecr.io/cccs/dev/projector-intellij-ce:trino
fi
