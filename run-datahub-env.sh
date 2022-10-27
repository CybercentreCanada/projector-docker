#!/bin/bash

sourceDir=${1:-~/repositories/cccs-work/datahub}

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
    containerHome="${HOME}/workspaces/datahub"
    mkdir -p "${containerHome}"
    cp "${HOME}/.gitconfig" "${containerHome}/"

    scratchDir="${HOME}/scratch"
    mkdir -p "${scratchDir}"

    echo "Setting up GPG and SSH sockets"
    mkdir -p "${containerHome}/.gnupg"
    gpgHomeDir=$(gpgconf --list-dir homedir)
    gpgExtraSocket=$(gpgconf --list-dir agent-extra-socket)
    cp "${gpgHomeDir}/pubring.kbx" "${gpgHomeDir}/trustdb.gpg" "${containerHome}/.gnupg"
    echo "%Assuan%" >"${containerHome}/.gnupg/S.gpg-agent"
    echo "socket=/usr/local/share/S.gpg-agent" >>"${containerHome}/.gnupg/S.gpg-agent"

    echo "Starting IDE"
    docker run --rm -it --pull always \
      --init --privileged \
      -p 8887:8887 \
      -p 9002:9002 \
      --env SSH_AUTH_SOCK=/usr/local/share/ssh-agent.sock \
      --mount type=bind,source="${containerHome}",target=/home/projector-user \
      --mount type=bind,source="${gpgExtraSocket}",target=/usr/local/share/S.gpg-agent \
      --mount type=bind,source="${HOME}/.ssh/agent.sock",target=/usr/local/share/ssh-agent.sock \
      --mount type=bind,source="${sourceDir}",target=/workspace/datahub \
      --mount type=volume,source=datahub-dind-var-lib-docker,target=/var/lib/docker \
      --mount type=bind,source="${scratchDir}",target=/workspace/scratch \
      uchimera.azurecr.io/cccs/dev/projector-intellij-ce:datahub
  else
    echo "Docker login failed"
    exit 1
  fi
else
  echo "Azure Container Registry login failed"
  exit 1
fi
