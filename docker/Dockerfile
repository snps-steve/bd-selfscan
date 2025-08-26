# BD SelfScan Scanner Container Image
FROM ubuntu:22.04

LABEL maintainer="your-team@company.com"
LABEL description="BD SelfScan Container Scanner with BDSC support"
LABEL version="1.0.0"

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install all dependencies in one layer for efficiency
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    jq \
    bash \
    coreutils \
    ca-certificates \
    openjdk-17-jre \
    skopeo \
    && rm -rf /var/lib/apt/lists/*

# Install kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl \
    && rm kubectl

# Install yq
RUN wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 \
    && chmod +x /usr/local/bin/yq

# Pre-download Detect script
RUN mkdir -p /opt/detect \
    && curl -L -o /opt/detect/detect.sh https://detect.synopsys.com/detect7.sh \
    && chmod +x /opt/detect/detect.sh

# Create required directories (scripts will be mounted from ConfigMaps)
RUN mkdir -p /scripts /config /tmp/bd-selfscan

# Set environment
ENV PATH="/scripts:$PATH"
ENV JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"

WORKDIR /tmp/bd-selfscan

# Run as root (required for Black Duck operations)
USER root

CMD ["/bin/bash"]