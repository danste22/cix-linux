# SPDX-License-Identifier: GPL-3.0-or-later
FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive

RUN printf '%s\n' \
      'deb http://deb.debian.org/debian trixie main non-free-firmware' \
      'deb http://deb.debian.org/debian trixie-backports main non-free-firmware' \
      'deb-src http://deb.debian.org/debian trixie-backports main non-free-firmware' \
      > /etc/apt/sources.list.d/o6n.sources.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential ca-certificates curl debhelper devscripts dpkg-dev \
      fakeroot git gnupg linux-base quilt rsync \
 && apt-get build-dep -y -t trixie-backports linux \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
