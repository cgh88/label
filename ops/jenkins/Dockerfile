FROM jenkins/jenkins:lts-jdk21

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git openssh-client \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm --version \
    && node --version \
    && rm -rf /var/lib/apt/lists/*

USER jenkins
