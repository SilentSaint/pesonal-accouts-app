FROM public.ecr.aws/ubuntu/ubuntu:22.04

ARG JAVA_VERSION=21
ARG NODE_VERSION=20.20.2
ARG FLUTTER_VERSION=3.44.0
ARG TERRAFORM_VERSION=1.5.7
ARG PLAYWRIGHT_VERSION=1.47.2

ENV FLUTTER_HOME=/opt/flutter \
    TERRAFORM_HOME=/opt/terraform \
    NODE_PATH=/usr/local/lib/node_modules \
    PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright \
    PATH=/opt/flutter/bin:/opt/terraform:/usr/local/bin:$PATH

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      apt-transport-https \
      ca-certificates \
      curl \
      file \
      git \
      gnupg \
      jq \
      python3 \
      tar \
      unzip \
      xz-utils; \
    curl --fail --silent --show-error --location https://apt.corretto.aws/corretto.key | gpg --dearmor -o /usr/share/keyrings/corretto-keyring.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/corretto-keyring.gpg] https://apt.corretto.aws stable main" > /etc/apt/sources.list.d/corretto.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends "java-${JAVA_VERSION}-amazon-corretto-jdk"; \
    rm -rf /var/lib/apt/lists/*; \
    node_url="https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz"; \
    curl --fail --silent --show-error --location "$node_url" --output /tmp/node.tar.xz; \
    tar -xJf /tmp/node.tar.xz --strip-components=1 -C /usr/local; \
    rm -f /tmp/node.tar.xz; \
    mkdir -p /opt/terraform /opt/ms-playwright; \
    terraform_url="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"; \
    curl --fail --silent --show-error --location "$terraform_url" --output /tmp/terraform.zip; \
    unzip -oq /tmp/terraform.zip -d /opt/terraform; \
    rm -f /tmp/terraform.zip; \
    flutter_url="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"; \
    curl --fail --silent --show-error --location "$flutter_url" --output /tmp/flutter.tar.xz; \
    tar -xJf /tmp/flutter.tar.xz -C /opt; \
    rm -f /tmp/flutter.tar.xz; \
    git config --global --add safe.directory /opt/flutter; \
    flutter config --no-analytics; \
    flutter precache --web; \
    npm install --global "playwright@${PLAYWRIGHT_VERSION}"; \
    playwright install --with-deps chromium; \
    java -version; \
    terraform version; \
    flutter --version; \
    chmod -R a+rwX /opt/flutter/packages/flutter_tools /opt/flutter/bin/cache; \
    node --version; \
    playwright --version
