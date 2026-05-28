FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    apache2 \
    php8.1 \
    php8.1-mysql \
    php8.1-xml \
    php8.1-mbstring \
    php8.1-curl \
    php8.1-zip \
    php8.1-gd \
    php8.1-intl \
    php8.1-soap \
    libapache2-mod-php8.1 \
    curl \
    wget \
    unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN wget -q "https://download.moodle.org/download.php/direct/stable405/moodle-latest-405.tgz" -O /tmp/moodle.tgz \
    && tar -xf /tmp/moodle.tgz -C /var/www/html/ \
    && rm /tmp/moodle.tgz \
    && chown -R www-data:www-data /var/www/html/moodle

RUN mkdir -p /var/moodledata \
    && chown -R www-data:www-data /var/moodledata \
    && chmod 0777 /var/moodledata

RUN rm -f /var/www/html/index.html

RUN echo "max_input_vars = 5000" >> /etc/php/8.1/apache2/php.ini && \
    echo "upload_max_filesize = 64M" >> /etc/php/8.1/apache2/php.ini && \
    echo "post_max_size = 64M" >> /etc/php/8.1/apache2/php.ini && \
    echo "memory_limit = 256M" >> /etc/php/8.1/apache2/php.ini

RUN echo "ServerName localhost" >> /etc/apache2/apache2.conf && \
    a2enmod rewrite

COPY moodle.conf /etc/apache2/sites-available/moodle.conf
RUN a2dissite 000-default && a2ensite moodle

COPY config.php /var/www/html/moodle/config.php
RUN chown www-data:www-data /var/www/html/moodle/config.php

EXPOSE 80

CMD ["apache2ctl", "-D", "FOREGROUND"]
