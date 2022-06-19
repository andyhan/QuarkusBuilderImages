#syntax=docker/dockerfile:1.4
# see https://github.com/moby/buildkit/blob/master/frontend/dockerfile/docs/syntax.md
# see https://docs.docker.com/engine/reference/builder/#syntax
#
# Copyright 2020-2021 by Vegard IT GmbH, Germany, https://vegardit.com
# SPDX-License-Identifier: Apache-2.0
#
# Author: Sebastian Thomschke, Vegard IT GmbH
#
# https://github.com/vegardit/docker-graalvm-maven
#

# https://hub.docker.com/_/debian?tab=tags&name=stable-slim
ARG BASE_IMAGE=debian:stable-slim

FROM ${BASE_IMAGE}

LABEL maintainer="Vegard IT GmbH (vegardit.com)"

USER root

SHELL ["/bin/bash", "-c"]

ARG DEBIAN_FRONTEND=noninteractive
ARG LC_ALL=C

ARG BASE_LAYER_CACHE_KEY

RUN --mount=type=bind,source=.shared,target=/mnt/shared <<EOF

  set -eu
  /mnt/shared/cmd/debian-install-os-updates.sh

  echo "#################################################"
  echo "Installing tools..."
  echo "#################################################"
  apt-get install --no-install-recommends -y bc ca-certificates curl git htop jq less mc procps vim xz-utils
  echo -e "set ignorecase
set showmatch
set novisualbell
set noerrorbells
syntax enable
set mouse-=a" > ~/.vimrc

  echo "#################################################"
  echo "Installing packages required by GraalVM..."
  echo "#################################################"
  apt-get install --no-install-recommends -y gcc libstdc++-10-dev libz-dev

  /mnt/shared/cmd/debian-cleanup.sh

EOF

ARG GRAALVM_DOWNLOAD_URL=https://github.com/graalvm/mandrel/releases/download/mandrel-22.1.0.0-Final/mandrel-java11-linux-amd64-22.1.0.0-Final.tar.gz
ARG JAVA_MAJOR_VERSION=11
ARG UPX_COMPRESS=true

ARG BUILD_DATE
ARG GIT_BRANCH
ARG GIT_COMMIT_HASH
ARG GIT_COMMIT_DATE
ARG GIT_REPO_URL

LABEL \
 org.label-schema.schema-version="1.0" \
 org.label-schema.build-date=$BUILD_DATE \
 org.label-schema.vcs-ref=$GIT_COMMIT_HASH \
 org.label-schema.vcs-url=$GIT_REPO_URL

RUN <<EOF

  set -eu -o pipefail

  echo "#################################################"
  echo "Installing latest UPX..."
  echo "#################################################"
  mkdir /opt/upx
  upx_download_url=$(curl -fsSL https://api.github.com/repos/upx/upx/releases/latest | grep browser_download_url | grep amd64_linux.tar.xz | cut "-d\"" -f4)
  echo "Downloading [$upx_download_url]..."
  curl -fL $upx_download_url | tar Jxv -C /opt/upx --strip-components=1

  echo "#################################################"
  echo "Installing GraalVM..."
  echo "#################################################"
  mkdir /opt/mandrel
  echo "Downloading [$GRAALVM_DOWNLOAD_URL]..."
  curl -fL "$GRAALVM_DOWNLOAD_URL" | \
     tar zxv -C /opt/mandrel --strip-components=1 \
        --exclude=*/bin/jvisualvm \
        --exclude=*/lib/src.zip \
        --exclude=*/lib/visualvm

  #/opt/mandrel/bin/gu install native-image

  strip --strip-unneeded \
     /opt/mandrel/bin/unpack200 \
     #/opt/mandrel/languages/js/bin/js \
     #/opt/mandrel/languages/llvm/bin/lli \
     #/opt/mandrel/languages/llvm/native/bin/graalvm-native-* \
     #/opt/mandrel/lib/installer/bin/gu \
     /opt/mandrel/lib/svm/bin/native-image

  if [[ $UPX_COMPRESS == "true" ]]; then
     /opt/upx/upx -9 \
        #/opt/mandrel/languages/llvm/bin/lli \
        #/opt/mandrel/languages/llvm/native/bin/graalvm-native-* \
        #/opt/mandrel/lib/installer/bin/gu \
        /opt/mandrel/lib/svm/bin/native-image
        #/opt/mandrel/bin/unpack200 \
        #/opt/mandrel/languages/js/bin/js \
  fi

  export JAVA_VERSION=$(java -fullversion 2>&1 | sed -E -n 's/.* version "([^.-]*).*"/\1/p')

  echo "#################################################"
  echo "Installing latest Docker client..."
  echo "#################################################"
  docker_cli_package=$(curl -fLsS https://download.docker.com/linux/static/stable/x86_64/ | grep -oP '(?<=>)docker-\d+.\d+.\d+.tgz(?=</a>)' | tail -1)
  docker_cli_download_url=https://download.docker.com/linux/static/stable/x86_64/$docker_cli_package
  echo "Downloading [$docker_cli_download_url]..."
  curl -fL $docker_cli_download_url | tar zxv -C /usr/bin --strip-components=1 docker/docker
  # this also installs docker app and docker buildx:
  #docker_cli_package=$(curl -fsSL https://download.docker.com/linux/debian/dists/bullseye/pool/stable/amd64/ | grep docker-ce-cli | grep buster_amd64 | tail -1 | grep -oP '(?<=deb">).*(?=</a>)')
  #docker_cli_download_url=https://download.docker.com/linux/debian/dists/bullseye/pool/stable/amd64/$docker_cli_package
  #echo "Downloading [$docker_cli_download_url]..."
  #curl -fL $docker_cli_download_url -o /tmp/docker-cli.deb
  #dpkg -i /tmp/docker-cli.deb
  #rm /tmp/docker-cli.deb
  strip --strip-unneeded /usr/bin/docker
  if [[ $UPX_COMPRESS == "true" ]]; then
     /opt/upx/upx -9 /usr/bin/docker
  fi

  echo "#################################################"
  echo "Installing latest Apache Maven..."
  echo "#################################################"
  mkdir /opt/maven
  maven_version=$(curl -fsSL https://repo1.maven.org/maven2/org/apache/maven/apache-maven/maven-metadata.xml | grep -oP '(?<=latest>).*(?=</latest)')
  maven_download_url="https://repo1.maven.org/maven2/org/apache/maven/apache-maven/$maven_version/apache-maven-${maven_version}-bin.tar.gz"
  echo "Downloading [$maven_download_url]..."
  curl -fL $maven_download_url | tar zxv -C /opt/maven --strip-components=1

  echo "#################################################"
  echo "Installing bash-funk..."
  echo "#################################################"
  git clone https://github.com/vegardit/bash-funk --depth 1 --branch master --single-branch /opt/bash-funk
  echo "BASH_FUNK_PROMPT_PREFIX='\033[45;30m GRAALVM '" >> ~/.bashrc
  echo "source /opt/bash-funk/bash-funk.sh" >> ~/.bashrc

  echo "#################################################"
  echo "Writing build_info..."
  echo "#################################################"
  echo -e "
GIT_REPO:    $GIT_REPO_URL
GIT_BRANCH:  $GIT_BRANCH
GIT_COMMIT:  $GIT_COMMIT_HASH @ $GIT_COMMIT_DATE
IMAGE_BUILD: $BUILD_DATE" >/opt/build_info
  cat /opt/build_info

EOF

COPY settings.xml /root/.m2/settings.xml
COPY toolchains.xml /root/.m2/toolchains.xml

ENV \
  PATH="/opt/mandrel/bin:/opt/maven/bin:/opt/upx:${PATH}" \
  JAVA_HOME=/opt/mandrel \
  GRAALVM_HOME=/opt/mandrel \
  JAVA_MAJOR_VERSION=${JAVA_MAJOR_VERSION} \
  MAVEN_HOME=/opt/maven \
  M2_HOME=/opt/maven \
  MAVEN_CONFIG="/root/.m2" \
  MAVEN_OPTS="-Xmx1024m -Djava.awt.headless=true -Djava.net.preferIPv4Stack=true -Dfile.encoding=UTF-8"

CMD "/bin/sh" "-c" "cat /opt/build_info && java --version && echo && mvn --version"

VOLUME "/root/.m2/repository"
