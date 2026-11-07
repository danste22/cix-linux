# SPDX-License-Identifier: GPL-3.0-or-later
FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends apt-utils dpkg-dev gnupg \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
