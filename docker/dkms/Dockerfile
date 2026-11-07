# SPDX-License-Identifier: GPL-3.0-or-later
FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential ca-certificates curl debhelper devscripts dh-dkms \
      dh-exec dkms dpkg-dev fakeroot git jq \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
