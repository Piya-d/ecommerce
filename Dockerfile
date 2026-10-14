# syntax=docker/dockerfile:1

FROM php:8.5-apache

ENV COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_MEMORY_LIMIT=-1

# System packages and PHP extensions.
# gd/intl/pgsql/zip back the platform; soap is required by the commerce
# lock (payment/shipping integrations); pcntl and sockets by the MQ consumer.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        gnupg \
        libfreetype6-dev \
        libicu-dev \
        libjpeg62-turbo-dev \
        libpng-dev \
        libpq-dev \
        libxml2-dev \
        libzip-dev \
        unzip \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install gd intl pcntl pdo_pgsql soap sockets zip \
    && a2enmod rewrite headers \
    && rm -rf /var/lib/apt/lists/*

# Node + pnpm. oro:assets:build shells out to pnpm, so both must be on PATH.
# Versions follow package.json engines: node >=24.11 <25, pnpm >=10.7.
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && corepack enable \
    && corepack prepare pnpm@latest-10 --activate

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

RUN printf 'memory_limit=2G\n' > /usr/local/etc/php/conf.d/oro-memory.ini

ENV APACHE_DOCUMENT_ROOT=/var/www/html/public

RUN sed -ri "s!/var/www/html!${APACHE_DOCUMENT_ROOT}!g" \
        /etc/apache2/sites-available/*.conf \
        /etc/apache2/apache2.conf \
        /etc/apache2/conf-available/*.conf

WORKDIR /var/www/html

# Dependencies before app code so composer layers survive source edits.
# Dev requirements are kept because docker-compose runs with ORO_ENV=dev.
COPY composer.json composer.lock ./
RUN composer install --no-interaction --prefer-dist --no-scripts --no-autoloader

COPY . /var/www/html

RUN composer dump-autoload --no-interaction --optimize

# Asset build. oro:assets:install chains the three Oro steps:
#   oro:localization:dump  emits oro.locale_data.js
#   assets:install         copies each bundle's Resources/public into public/bundles
#   oro:assets:build       runs pnpm install, then webpack for the back-office
#                          and every storefront theme, emitting public/build/<theme>/
# All three run without a database. Commerce builds several storefront themes,
# so webpack needs more heap than the CRM build.
ENV NODE_OPTIONS=--max-old-space-size=4096
RUN php bin/console oro:assets:install --env=prod -v

RUN mkdir -p var/cache var/data var/logs var/sessions var/maintenance public/media \
    && chown -R www-data:www-data var public

EXPOSE 80
