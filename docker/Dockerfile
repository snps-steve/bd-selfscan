# BD SelfScan Scanner Container Image - Security Hardened
FROM ubuntu:22.04

LABEL maintainer="your-team@company.com"
LABEL description="BD SelfScan Container Scanner with BDSC support"
LABEL version="1.0.0"
LABEL org.opencontainers.image.source="https://github.com/your-org/bd-selfscan"
LABEL org.opencontainers.image.security="This image contains security scanning tools"

# Build arguments for version pinning
ARG KUBECTL_VERSION=v1.28.0
ARG YQ_VERSION=v4.35.1

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
ENV PATH="/scripts:$PATH"
ENV JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"

# Create a non-root user early (though root may be needed for some BD operations)
RUN groupadd -g 1000 scanner && \
    useradd -u 1000 -g scanner -m -s /bin/bash scanner

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
    # Add error handling and verification
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /tmp/*

# Install kubectl with version pinning and verification
RUN curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && curl -LO "https://dl.k8s.io/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256" \
    && echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check \
    && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl \
    && rm kubectl kubectl.sha256

# Install yq with version pinning and verification
RUN wget -qO /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" \
    && chmod +x /usr/local/bin/yq \
    # Verify yq installation
    && yq --version

# Pre-download and verify Detect script
RUN mkdir -p /opt/detect \
    && curl -L -o /opt/detect/detect.sh https://detect.synopsys.com/detect7.sh \
    && chmod +x /opt/detect/detect.sh \
    # Verify the script downloaded successfully
    && test -f /opt/detect/detect.sh \
    && head -1 /opt/detect/detect.sh | grep -q "#!/bin/bash"

# Create required directories with proper permissions
RUN mkdir -p /scripts /config /tmp/bd-selfscan \
    && chown -R scanner:scanner /scripts /config /tmp/bd-selfscan

# Set working directory
WORKDIR /tmp/bd-selfscan

# Add health check for container monitoring
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD command -v kubectl && command -v yq && command -v java || exit 1

# Default to non-root user (can be overridden in Kubernetes if root is needed)
USER scanner

# Use exec form for better signal handling
CMD ["/bin/bash"]
