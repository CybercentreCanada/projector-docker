#!/bin/bash

trinoCloneDir=${1:-~/repositories/cccs-work/trino}

echo "Checking Azure login status"
az account show >/dev/null
AZ_LOGIN_STATUS=$?
if [[ ${AZ_LOGIN_STATUS} -eq 0 ]]; then
  echo "Already logged in to Azure"
else
  echo "Attempting Azure login"
  az login
  AZ_LOGIN_STATUS=$?
  if [[ ${AZ_LOGIN_STATUS} -eq 0 ]]; then
    echo "Successfully logged in to Azure"
  else
    echo "Azure login failed"
    exit 1
  fi
fi

echo "Logging in to Azure Container Registry"
read -r LOGIN_SERVER ACCESS_TOKEN < <(az acr login -n uchimera --expose-token --query "join(' ', [loginServer, accessToken])" -otsv 2>/dev/null)
ACR_LOGIN_STATUS=$?
if [[ ${ACR_LOGIN_STATUS} -eq 0 ]]; then
  echo "Logging in to Docker Registry"
  docker login ${LOGIN_SERVER} -u 00000000-0000-0000-0000-000000000000 --password-stdin <<< ${ACCESS_TOKEN}
  DOCKER_LOGIN_STATUS=$?
  if [[ ${DOCKER_LOGIN_STATUS} -eq 0 ]]; then
    mkdir -p ~/workspaces/trino
    echo "Starting IDE"
    docker run --rm --pull always --init --privileged -p 8887:8887 --mount type=bind,source="${HOME}/workspaces/trino",target=/home/projector-user --mount type=bind,source="${trinoCloneDir}",target=/workspace/trino -it uchimera.azurecr.io/cccs/dev/projector-intellij-ce:feature_CLDN-2234
  else
    echo "Docker login failed"
    exit 1
  fi
else
  echo "Azure Container Registry login failed"
  exit 1
fi
