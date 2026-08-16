FROM debian:bullseye-slim

LABEL author="SairiDev" maintainer="sairidev@gmail.com"

ENV DEBIAN_FRONTEND=noninteractive \
    USER=container \
    HOME=/home/container \
    NODE_INSTALL_DIR=/home/container/node \
    BUN_INSTALL=/usr/local/bun \
    PLAYWRIGHT_BROWSERS_PATH=/usr/local/share/playwright \
    GO_VERSION=1.24.0 \
    PYTHON_VERSION=3.13.0 \
    PHP_VERSION=8.3 \
    JAVA_VERSION=21

ENV PATH="$NODE_INSTALL_DIR/bin:$BUN_INSTALL/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl wget git zip unzip tar gzip bzip2 p7zip-full zstd \
        jq nano vim sudo ca-certificates gnupg lsb-release figlet \
        net-tools iputils-ping dnsutils procps \
        build-essential make gcc g++ libssl-dev zlib1g-dev \
        libbz2-dev libreadline-dev libsqlite3-dev \
        libncursesw5-dev xz-utils tk-dev libffi-dev liblzma-dev \
        ffmpeg imagemagick graphicsmagick webp mediainfo \
        default-mysql-client \
    && mkdir -p --mode=0755 /usr/share/keyrings \
    && curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | gpg --dearmor > /usr/share/keyrings/cloudflare-public-v2.gpg \
    && echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main' | tee /etc/apt/sources.list.d/cloudflared.list \
    && apt-get update && apt-get install -y cloudflared

# --- PHP (via Sury/Ondřej repo, mendukung banyak versi PHP) + PHP-FPM + Nginx + Supervisor ---
RUN curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor > /usr/share/keyrings/sury-php.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/sury-php.gpg] https://packages.sury.org/php/ bullseye main" | tee /etc/apt/sources.list.d/sury-php.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        php${PHP_VERSION} php${PHP_VERSION}-cli php${PHP_VERSION}-common \
        php${PHP_VERSION}-fpm \
        php${PHP_VERSION}-mysql php${PHP_VERSION}-pgsql php${PHP_VERSION}-sqlite3 \
        php${PHP_VERSION}-curl php${PHP_VERSION}-mbstring php${PHP_VERSION}-xml \
        php${PHP_VERSION}-zip php${PHP_VERSION}-gd php${PHP_VERSION}-bcmath \
        php${PHP_VERSION}-intl php${PHP_VERSION}-opcache \
        nginx supervisor \
    && ln -sf /usr/bin/php${PHP_VERSION} /usr/bin/php \
    && ln -sf /usr/sbin/php-fpm${PHP_VERSION} /usr/sbin/php-fpm \
    && curl -fsSL https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \
    && rm -f /etc/nginx/sites-enabled/default

# --- Java (Eclipse Temurin / Adoptium, distribusi OpenJDK resmi) ---
RUN mkdir -p --mode=0755 /usr/share/keyrings \
    && curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor > /usr/share/keyrings/adoptium.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb bullseye main" | tee /etc/apt/sources.list.d/adoptium.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends temurin-${JAVA_VERSION}-jdk \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
        fonts-liberation fonts-noto-color-emoji libfontconfig1 libfreetype6 \
        libasound2 libgbm1 libgtk-3-0 libnss3 libnspr4 libatk1.0-0 \
        libatk-bridge2.0-0 libcups2 libdrm2 libdbus-1-3 libexpat1 \
        libx11-xcb1 libxcb-dri3-0 libxss1 libxtst6 \
    && rm -rf /var/lib/apt/lists/*

RUN cd /tmp && wget https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz \
    && tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz && rm go*.tar.gz

RUN cd /tmp && wget https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz \
    && tar xzf Python-${PYTHON_VERSION}.tgz && cd Python-${PYTHON_VERSION} \
    && ./configure --enable-optimizations && make altinstall \
    && ln -sf /usr/local/bin/python3.13 /usr/local/bin/python3 \
    && ln -sf /usr/local/bin/pip3.13 /usr/local/bin/pip3 \
    && cd .. && rm -rf Python-${PYTHON_VERSION}*

RUN cd /tmp && wget https://github.com/oven-sh/bun/releases/latest/download/bun-linux-x64.zip \
    && unzip bun-linux-x64.zip \
    && mkdir -p $BUN_INSTALL/bin \
    && mv bun-linux-x64/bun $BUN_INSTALL/bin/bun \
    && chmod +x $BUN_INSTALL/bin/bun \
    && rm -rf bun-linux-x64 bun-linux-x64.zip

RUN mkdir -p $PLAYWRIGHT_BROWSERS_PATH \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g playwright@1.47.0 \
    && npx playwright install --with-deps \
    && apt-get purge -y nodejs && apt-get autoremove -y \
    && chmod -R 777 $PLAYWRIGHT_BROWSERS_PATH

RUN useradd -m -d /home/container container
RUN mkdir -p $NODE_INSTALL_DIR && chown -R container:container $NODE_INSTALL_DIR

# --- Config Nginx + PHP-FPM + Supervisor (semuanya jalan sebagai user non-root 'container') ---
COPY ./docker/nginx.conf /etc/nginx/nginx.conf
COPY ./docker/nginx-php.conf.template /etc/nginx/sites-available/php.conf.template
COPY ./docker/www.conf /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf
COPY ./docker/supervisord.conf /etc/supervisor/supervisord.conf

RUN mkdir -p /etc/nginx/sites-enabled /run/php \
        /home/container/public /home/container/logs /home/container/run \
    && echo '<?php phpinfo();' > /home/container/public/index.php \
    && chown -R container:container \
        /etc/nginx /var/lib/nginx /var/log/nginx /run/php \
        /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf \
        /etc/supervisor/supervisord.conf \
        /home/container

USER container
WORKDIR /home/container

COPY ./entrypoint.sh /entrypoint.sh
CMD [ "/bin/bash", "/entrypoint.sh" ]
