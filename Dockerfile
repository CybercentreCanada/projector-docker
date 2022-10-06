#
# Copyright 2019-2020 JetBrains s.r.o.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

ARG containerJdkVersion

FROM debian AS ideDownloader

# prepare tools:
RUN apt-get update
RUN apt-get install wget -y
# download IDE to the /ide dir:
WORKDIR /download
ARG downloadUrl
RUN wget -q $downloadUrl -O - | tar -xz
RUN find . -maxdepth 1 -type d -name * -execdir mv {} /ide \;

FROM amazoncorretto:17 as projectorGradleBuilder

ENV PROJECTOR_DIR /projector

RUN yum update -y
RUN yum install git -y

# projector-server:
RUN git clone https://github.com/JetBrains/projector-server.git $PROJECTOR_DIR/projector-server
WORKDIR $PROJECTOR_DIR/projector-server
ARG buildGradle
RUN if [ "$buildGradle" = "true" ]; then ./gradlew clean; else echo "Skipping gradle build"; fi
RUN if [ "$buildGradle" = "true" ]; then ./gradlew :projector-server:distZip; else echo "Skipping gradle build"; fi
RUN cd projector-server/build/distributions && find . -maxdepth 1 -type f -name projector-server-*.zip -exec mv {} projector-server.zip \;

FROM debian AS projectorStaticFiles

# prepare tools:
RUN apt-get update
RUN apt-get install unzip -y
# create the Projector dir:
ENV PROJECTOR_DIR /projector
RUN mkdir -p $PROJECTOR_DIR
# copy IDE:
COPY --from=ideDownloader /ide $PROJECTOR_DIR/ide
# copy projector files to the container:
ADD static $PROJECTOR_DIR
# copy projector:
COPY --from=projectorGradleBuilder $PROJECTOR_DIR/projector-server/projector-server/build/distributions/projector-server.zip $PROJECTOR_DIR
# prepare IDE - apply projector-server:
RUN unzip $PROJECTOR_DIR/projector-server.zip
RUN rm $PROJECTOR_DIR/projector-server.zip
RUN find . -maxdepth 1 -type d -name projector-server-* -exec mv {} projector-server \;
RUN mv projector-server $PROJECTOR_DIR/ide/projector-server
RUN mv $PROJECTOR_DIR/ide-projector-launcher.sh $PROJECTOR_DIR/ide/bin
RUN chmod 644 $PROJECTOR_DIR/ide/projector-server/lib/*

FROM eclipse-temurin:${containerJdkVersion}-jdk-jammy

# Add custom CA certificates
ARG extraCaCertsDir
ADD ${extraCaCertsDir} /usr/local/share/ca-certificates/

RUN true \
# Any command which returns non-zero exit code will cause this shell script to exit immediately:
    && set -e \
# Activate debugging to show execution details: all commands will be printed before execution
    && set -x \
    && update-ca-certificates \
# install packages:
    && apt-get update \
# packages for awt:
    && apt-get install libxext6 libxrender1 libxtst6 libxi6 libfreetype6 -y \
# packages for user convenience:
    && apt-get install ca-certificates ca-certificates-java git bash-completion vim sudo unzip zip sed -y \
# packages for IDEA (to disable warnings):
    && apt-get install procps -y 

ARG downloadUrl

RUN true \
# Any command which returns non-zero exit code will cause this shell script to exit immediately:
    && set -e \
# Activate debugging to show execution details: all commands will be printed before execution:
    && set -x \
# install specific packages for IDEs:
    && apt-get update \
    && if [ "${downloadUrl#*CLion}" != "$downloadUrl" ]; then apt-get install build-essential clang -y; else echo "Not CLion"; fi \
    && if [ "${downloadUrl#*pycharm}" != "$downloadUrl" ]; then apt-get install python2 python3 python3-distutils python3-pip python3-setuptools -y; else echo "Not pycharm"; fi \
    && if [ "${downloadUrl#*rider}" != "$downloadUrl" ]; then apt install apt-transport-https dirmngr gnupg ca-certificates -y && apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF && echo "deb https://download.mono-project.com/repo/debian stable-buster main" | tee /etc/apt/sources.list.d/mono-official-stable.list && apt update && apt install mono-devel -y && apt install wget -y && wget https://packages.microsoft.com/config/debian/10/packages-microsoft-prod.deb -O packages-microsoft-prod.deb && dpkg -i packages-microsoft-prod.deb && rm packages-microsoft-prod.deb && apt-get update && apt-get install -y apt-transport-https && apt-get update && apt-get install -y dotnet-sdk-3.1 aspnetcore-runtime-3.1; else echo "Not rider"; fi

# copy the Projector dir:
ENV PROJECTOR_DIR /projector
COPY --from=projectorStaticFiles $PROJECTOR_DIR $PROJECTOR_DIR

ENV PROJECTOR_USER_NAME projector-user
ARG PROJECTOR_USER_UID=1000
ARG PROJECTOR_USER_GID=$PROJECTOR_USER_UID

# [Option] Install zsh
ARG INSTALL_ZSH="true"
# [Option] Upgrade OS packages to their latest versions
ARG UPGRADE_PACKAGES="false"
# [Option] Enable non-root Docker access in container
ARG ENABLE_NONROOT_DOCKER="true"
# [Option] Use the OSS Moby CLI instead of the licensed Docker CLI
ARG USE_MOBY="true"

# Setting up Trino environment
RUN true \
# Any command which returns non-zero exit code will cause this shell script to exit immediately:
    && set -e \
# Activate debugging to show execution details: all commands will be printed before execution
    && set -x \
    && apt-get update  && apt-get install -y apt-transport-https \
# Use Docker script from script library to set things up to allow use in ${PROJECTOR_USER_NAME} to run docker commands without sudo
    && /bin/bash /$PROJECTOR_DIR/library-scripts/docker-in-docker-debian.sh "${ENABLE_NONROOT_DOCKER}" "${PROJECTOR_USER_NAME}" "${USE_MOBY}" 

ARG MAVEN_VERSION=""
ARG TRINO_VERSION="395"

RUN true \
# Any command which returns non-zero exit code will cause this shell script to exit immediately:
    && set -e \
# Activate debugging to show execution details: all commands will be printed before execution
    && set -x \
# Create home directory and transfert static files
    && mv $PROJECTOR_DIR/$PROJECTOR_USER_NAME  /home 

RUN true \
# Any command which returns non-zero exit code will cause this shell script to exit immediately:
    && set -e \
# Activate debugging to show execution details: all commands will be printed before execution
    && set -x \
# Move run scipt:
    && mv $PROJECTOR_DIR/run.sh run.sh \
# Change user to non-root (http://pjdietz.com/2016/08/28/nginx-in-docker-without-root.html):
    && useradd -d /home/$PROJECTOR_USER_NAME -s /bin/bash -G sudo $PROJECTOR_USER_NAME \
    && id -u $PROJECTOR_USER_NAME \
# Grant user in $PROJECTOR_USER_NAME SUDO privilege and allow it run any command without authentication.
    && echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers \
    && cat /etc/sudoers \
    && chown -R $PROJECTOR_USER_NAME.$PROJECTOR_USER_NAME /home/$PROJECTOR_USER_NAME \
    && chown -R $PROJECTOR_USER_NAME.$PROJECTOR_USER_NAME $PROJECTOR_DIR/ide/bin \
    && chown $PROJECTOR_USER_NAME.$PROJECTOR_USER_NAME run.sh \
# Trust the GitHub public RSA key
# This key was manually validated by running 'ssh-keygen -lf <key-file>' and comparing the fingerprint to the one found at:
# https://docs.github.com/en/github/authenticating-to-github/githubs-ssh-key-fingerprints
    && mkdir -p /home/${PROJECTOR_USER_NAME}/.ssh \
    && echo "github.com ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLmvU31/yMf+Se8xhHTvKSCZIFImWwoG6mbUoWf9nzpIoaSjB+weqqUUmpaaasXVal72J+UX2B+2RPW3RcT0eOzQgqlJL3RKrTJvdsjE3JEAvGq3lGHSZXy28G3skua2SmVi/w4yCE6gbODqnTWlg7+wC604ydGXA8VJiS5ap43JXiUFFAaQ==" >> /home/${PROJECTOR_USER_NAME}/.ssh/known_hosts \
    && chown -R ${PROJECTOR_USER_NAME} /home/${PROJECTOR_USER_NAME}/.ssh \
    && touch /usr/local/share/bash_history \
    && chown ${PROJECTOR_USER_NAME} /usr/local/share/bash_history

# Install additional OS packages.
    && apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends bash-completion vim \
    && apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/* \
# Install Trino CLI
    && wget https://repo1.maven.org/maven2/io/trino/trino-cli/${TRINO_VERSION}/trino-cli-${TRINO_VERSION}-executable.jar -P /usr/local/bin \
    && chmod +x /usr/local/bin/trino-cli-${TRINO_VERSION}-executable.jar \
    && ln -s /usr/local/bin/trino-cli-${TRINO_VERSION}-executable.jar /usr/local/bin/trino \
# clean apt to reduce image size:
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* $PROJECTOR_DIR/library-scripts/ 

USER $PROJECTOR_USER_NAME:$PROJECTOR_USER_GID
ENV HOME /home/$PROJECTOR_USER_NAME

ARG  SDKMAN_DIR=/home/${PROJECTOR_USER_NAME}/.sdkman

# Install SDKMAN
RUN  true \
# Any command which returns non-zero exit code will cause this shell script to exit immediately:
    && set -e \
# Activate debugging to show execution details: all commands will be printed before execution
    && set -x \
#Install SDKMAN
    && curl -s "https://get.sdkman.io" | bash  \
    && ls -al $SDKMAN_DIR
    
# Install Maven
RUN su ${PROJECTOR_USER_NAME} -c "umask 0002 && . ${SDKMAN_DIR}/bin/sdkman-init.sh && sdk install maven \"${MAVEN_VERSION}\"" \

# Use the Maven cache from the host and persist Bash history
RUN mkdir -p /usr/local/share/m2 \
    && chown -R ${USER_PROJECTOR_USER_UID}:${PROJECTOR_USER_UID} /usr/local/share/m2 \
    && ln -s /usr/local/share/m2 /home/${PROJECTOR_USER_NAME}/.m2


# Add custom CA certificates to Java trust
RUN true \
# Any command which returns non-zero exit code will cause this shell script to exit immediately:
    && set -e \
# Activate debugging to show execution details: all commands will be printed before execution
    &&  set -x \ 
    && for cert in /usr/local/share/ca-certificates/*; do \
        openssl x509 -outform der -in "$cert" -out /tmp/certificate.der; \
        $PROJECTOR_DIR/ide/jbr/bin/keytool -import -alias "$cert" -keystore $PROJECTOR_DIR/ide/jbr/lib/security/cacerts -file /tmp/certificate.der -deststorepass changeit -noprompt; \
    done \
    && rm /tmp/certificate.der


EXPOSE 8887

# Setting the ENTRYPOINT to docker-init.sh will configure non-root access to
# the Docker socket if "overrideCommand": false is set in devcontainer.json.
# The script will also execute CMD if you need to alter startup behaviors.
ENTRYPOINT [ "/usr/local/share/docker-init.sh" ]
CMD ["bash", "-c", "/run.sh"]
