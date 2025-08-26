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

# Create application directories
RUN mkdir -p /app/scripts \
    && mkdir -p /tmp/bd-selfscan \
    && mkdir -p /config

# Copy scanner scripts into the container
COPY scripts/ /app/scripts/
RUN chmod +x /app/scripts/*.sh

# Create non-root user for security (but allow root when needed)
RUN useradd -m -s /bin/bash -u 1000 scanner \
    && usermod -aG root scanner

# Set proper ownership
RUN chown -R scanner:scanner /app \
    && chown -R scanner:scanner /tmp/bd-selfscan \
    && chmod -R 755 /app/scripts

# Set working directory
WORKDIR /app

# Environment variables
ENV PATH="/app/scripts:$PATH"
ENV JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"

# Health check (optional)
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Default to running as scanner user, but allow override
USER scanner

# Default command
CMD ["/bin/bash"]

# Document exposed ports (if any)
# EXPOSE 8080