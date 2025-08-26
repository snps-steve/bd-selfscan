# BD SelfScan Scanner Container Image
FROM ubuntu:22.04

# Metadata
LABEL maintainer="your-team@company.com"
LABEL description="BD SelfScan Container Scanner with BDSC support"
LABEL version="1.0.0"

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    jq \
    bash \
    coreutils \
    ca-certificates \
    gnupg2 \
    software-properties-common \
    unzip \
    tar \
    gzip \
    && rm -rf /var/lib/apt/lists/*

# Install Java 17 (required for Synopsys Detect)
RUN apt-get update && apt-get install -y openjdk-17-jre \
    && rm -rf /var/lib/apt/lists/*

# Verify Java installation
RUN java -version

# Install kubectl (latest stable)
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl \
    && rm kubectl \
    && kubectl version --client

# Install yq (latest)
RUN wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 \
    && chmod +x /usr/local/bin/yq \
    && yq --version

# Install skopeo for container image handling
RUN apt-get update && apt-get install -y skopeo \
    && rm -rf /var/lib/apt/lists/* \
    && skopeo --version

# Pre-download Synopsys Detect script (optimization)
RUN mkdir -p /opt/detect \
    && curl -L -o /opt/detect/detect.sh https://detect.synopsys.com/detect7.sh \
    && chmod +x /opt/detect/detect.sh \
    && echo "Detect script cached at /opt/detect/detect.sh"

# Create application directories FIRST
RUN mkdir -p /scripts \
    && mkdir -p /tmp/bd-selfscan \
    && mkdir -p /config

# Create non-root user for security BEFORE setting ownership
RUN useradd -m -s /bin/bash -u 1000 scanner \
    && usermod -aG root scanner

# Copy scanner scripts into the container (AFTER creating directories)
COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh

# Set proper ownership AFTER user creation and file copying
RUN chown -R scanner:scanner /scripts \
    && chown -R scanner:scanner /tmp/bd-selfscan \
    && chmod -R 755 /scripts

# Set working directory
WORKDIR /tmp/bd-selfscan

# Environment variables
ENV PATH="/scripts:$PATH"
ENV JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"

# Remove invalid health check (this is a batch job, not a web service)
# HEALTHCHECK removed

# Default to running as root for Black Duck scanning operations
# (Kubernetes can override this if needed)
USER root

# Default command
CMD ["/bin/bash"]