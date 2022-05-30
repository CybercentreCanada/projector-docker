#!/bin/bash

trinoCloneDir=${1:-~/repositories/trino}

echo "Checking Azure login status"
az account show >/dev/null
AZ_LOGIN_STATUS=$?
if [ ${AZ_LOGIN_STATUS} -eq 0 ]; then
  echo "Already logged in to Azure"
else
  echo "Attempting Azure login"
  az login
  AZ_LOGIN_STATUS=$?
  if [ ${AZ_LOGIN_STATUS} -eq 0 ]; then
    echo "Successfully logged in to Azure"
  else
    echo "Azure login failed"
    exit 1
  fi
fi

echo "Logging in to Azure Container Registry"
#read -r LOGIN_SERVER ACCESS_TOKEN <<< $(az acr login -n uchimera --expose-token --query '[loginServer, accessToken]' -otsv 2>/dev/null)
read -r ACCESS_TOKEN LOGIN_SERVER <<< $(az acr login -n uchimera --expose-token  -otsv 2>/dev/null)
ACR_LOGIN_STATUS=$?
if [ ${ACR_LOGIN_STATUS} -eq 0 ]; then
  echo "Logging in to Docker Registry"
#  docker login ${LOGIN_SERVER} -u 00000000-0000-0000-0000-000000000000 -p ${ACCESS_TOKEN}
  docker login $(echo ${LOGIN_SERVER} | tr -d '\r') -u 00000000-0000-0000-0000-000000000000 -p ${ACCESS_TOKEN}
  DOCKER_LOGIN_STATUS=$?
  if [ ${DOCKER_LOGIN_STATUS} -eq 0 ]; then
    mkdir -p ~/workspaces/trino
    echo "Starting IDE"
    docker run --rm --pull always -p 8887:8887 --mount type=bind,source="${HOME}/workspaces/trino",target=/home/projector-user --mount type=bind,source="${trinoCloneDir}",target=/workspace/trino -it uchimera.azurecr.io/cccs/dev/projector-intellij-ce:trino
  else
  echo "Docker login failed"
  exit 1
  fi
else
  echo "Azure Container Registry login failed"
  exit 1
fi