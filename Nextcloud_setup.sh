#!/bin/bash

# Конфигурация
DB_PASSWORD=$(openssl rand -base64 12)
NEXTCLOUD_USER="admin"
ADMIN_PASSWORD=$(openssl rand -base64 12)
read -p "Введите домен сайта (для Certbot): " DOMAIN
DATA_DIR="/var/www/nextcloud/data"
PHP_VERSION="8.2"

# Функция для обработки ошибок
handle_error() {
    echo "Ошибка при выполнении: $1" >&2
    echo "Рекомендуется выполнить скрипт очистки: sudo ./nextcloud_cleanup.sh"
    exit 1
}

# Установка Certbot
install_certbot() {
    echo "Установка Certbot..."
    if ! command -v certbot >/dev/null 2>&1; then
        if command -v snap >/dev/null 2>&1; then
            snap install core
            snap refresh core
            snap install --classic certbot
            ln -sf /snap/bin/certbot /usr/bin/certbot
        else
            apt install -y certbot python3-certbot-apache
        fi
    fi
}

# Основная функция установки
install() {
    echo "=== Начало установки Nextcloud ==="
    
    # Проверка прав root
    if [ "$(id -u)" != "0" ]; then
        handle_error "этот скрипт должен быть запущен от root"
    fi

    # 1. Обновление системы
    echo "Обновление пакетов..."
    apt update && apt upgrade -y || handle_error "Обновление системы"

    # 2. Установка Apache
    echo "Установка Apache..."
    apt install -y apache2 || handle_error "Установка Apache"
    systemctl enable --now apache2 || handle_error "Запуск Apache"

    # 3. Установка MariaDB
    echo "Установка MariaDB..."
    apt install -y mariadb-server || handle_error "Установка MariaDB"
    systemctl enable --now mariadb || handle_error "Запуск MariaDB"

    # 4. Настройка безопасности MariaDB
    echo "Настройка MariaDB..."
    mysql -e "DROP DATABASE IF EXISTS nextcloud;"
    mysql -e "DROP USER IF EXISTS 'nextcloud'@'localhost';"
    mysql -e "CREATE DATABASE nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;" || handle_error "Создание БД"
    mysql -e "CREATE USER 'nextcloud'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';" || handle_error "Создание пользователя БД"
    mysql -e "GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'localhost';" || handle_error "Настройка прав БД"
    mysql -e "FLUSH PRIVILEGES;" || handle_error "Обновление прав БД"

    # 5. Установка PHP
    echo "Установка PHP..."
    apt install -y software-properties-common || handle_error "Установка зависимостей"

    apt install -y php${PHP_VERSION} php${PHP_VERSION}-{curl,gd,mbstring,xml,zip,mysql,intl,imagick,bcmath,gmp,apcu,redis} \
    || handle_error "Установка PHP"

    # 6. Настройка PHP
    PHP_INI_PATH="/etc/php/${PHP_VERSION}/apache2/php.ini"
    sed -i "s/^\(;\?\)upload_max_filesize =.*/upload_max_filesize = 16G/" "$PHP_INI_PATH"
    sed -i "s/^\(;\?\)post_max_size =.*/post_max_size = 16G/" "$PHP_INI_PATH"
    sed -i "s/^\(;\?\)memory_limit =.*/memory_limit = 512M/" "$PHP_INI_PATH"

    # 7. Установка Nextcloud
    echo "Установка Nextcloud..."
    cd /var/www/ || handle_error "Переход в /var/www"
    wget -q https://download.nextcloud.com/server/releases/latest.zip || handle_error "Загрузка Nextcloud"
    unzip -q latest.zip || handle_error "Распаковка Nextcloud"
    rm latest.zip
    chown -R www-data:www-data nextcloud || handle_error "Настройка прав"

    # 8. Настройка Apache
    echo "Настройка Apache..."
    cat > /etc/apache2/sites-available/nextcloud.conf <<EOF
<VirtualHost *:80>
    ServerName ${DOMAIN}
    DocumentRoot /var/www/nextcloud
    <Directory /var/www/nextcloud>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

    a2ensite nextcloud.conf || handle_error "Активация сайта"
    a2enmod rewrite headers env dir mime || handle_error "Активация модулей"
    systemctl restart apache2 || handle_error "Перезапуск Apache"

    # 9. Установка SSL (опционально)
    read -p "Установить SSL с помощью Certbot? (y/n): " ssl_choice
    if [[ $ssl_choice =~ ^[Yy] ]]; then
        install_certbot
        certbot --apache -d ${DOMAIN} --non-interactive --agree-tos --email admin@${DOMAIN} \
        || handle_error "Установка SSL"
    fi

    # 10. Настройка cron
    echo "Настройка заданий cron..."
    (crontab -u www-data -l 2>/dev/null; echo "*/5 * * * * php -f /var/www/nextcloud/cron.php") | crontab -u www-data - \
    || handle_error "Настройка cron"

    # Успешное завершение
    echo "=== Установка завершена успешно! ==="
    echo "URL: https://${DOMAIN}"
    echo "Пользователь: ${NEXTCLOUD_USER}"
    echo "Пароль: ${ADMIN_PASSWORD}"
    echo "Пароль БД: ${DB_PASSWORD}"
}

# Вызов основной функции
install



