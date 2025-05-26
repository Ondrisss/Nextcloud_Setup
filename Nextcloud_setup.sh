#!/bin/bash

# Проверка прав root
if [ "$(id -u)" != "0" ]; then
    echo "Ошибка: скрипт требует root-прав. Запустите с sudo." >&2
    exit 1
fi

# Конфигурация
DB_PASSWORD=$(openssl rand -base64 12)
NEXTCLOUD_USER="admin"
ADMIN_PASSWORD=$(openssl rand -base64 12)
read -p "Введите домен сайта (для Certbot): " DOMAIN
DATA_DIR="/var/www/nextcloud/data"
PHP_VERSION="8.2"

# Функция обработки ошибок
handle_error() {
    echo "Ошибка: $1" >&2
    echo "Для очистки выполните: sudo ./Nextcloud_clean.sh" >&2
    exit 1
}

echo "=== Начало установки Nextcloud ==="

# Установка базовых зависимостей
echo "Установка необходимых пакетов..."
apt update || handle_error "не удалось обновить список пакетов"
apt install -y unzip curl apt-transport-https || handle_error "не удалось установить зависимости"

# Установка Apache
echo "Установка Apache..."
apt install -y apache2 || handle_error "ошибка установки Apache"
systemctl enable --now apache2 || handle_error "ошибка запуска Apache"

# Установка MariaDB
echo "Установка MariaDB..."
apt install -y mariadb-server || handle_error "ошибка установки MariaDB"
systemctl enable --now mariadb || handle_error "ошибка запуска MariaDB"

# Настройка MariaDB
echo "Настройка базы данных..."
mysql -e "CREATE DATABASE IF NOT EXISTS nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;" || handle_error "ошибка создания БД"
mysql -e "CREATE USER IF NOT EXISTS 'Киextcloud'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';" || handle_error "ошибка создания пользователя"
mysql -e "GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'localhost';" || handle_error "ошибка назначения прав"
mysql -e "FLUSH PRIVILEGES;" || handle_error "ошибка обновления привилегий"

# Установка PHP и модулей
echo "Установка PHP и модулей..."
apt install -y software-properties-common || handle_error "ошибка установки зависимостей"
apt install -y php${PHP_VERSION} php${PHP_VERSION}-{curl,gd,mbstring,xml,zip,mysql,intl,imagick,bcmath,gmp,apcu,redis} || handle_error "ошибка установки PHP"

# Настройка PHP
echo "Настройка PHP..."
PHP_INI="/etc/php/${PHP_VERSION}/apache2/php.ini"
sed -i "s/^\(;\?\)upload_max_filesize =.*/upload_max_filesize = 16G/" "$PHP_INI"
sed -i "s/^\(;\?\)post_max_size =.*/post_max_size = 16G/" "$PHP_INI"
sed -i "s/^\(;\?\)memory_limit =.*/memory_limit = 512M/" "$PHP_INI"

# Установка Nextcloud
echo "Установка Nextcloud..."
cd /var/www || handle_error "ошибка перехода в /var/www"
curl -O https://download.nextcloud.com/server/releases/latest.zip || handle_error "ошибка загрузки Nextcloud"
unzip latest.zip || handle_error "ошибка распаковки Nextcloud"
rm latest.zip
chown -R www-data:www-data nextcloud || handle_error "ошибка настройки прав"

# Настройка Apache
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

a2ensite nextcloud.conf || handle_error "ошибка активации сайта"
a2enmod rewrite headers env dir mime || handle_error "ошибка активации модулей"
systemctl restart apache2 || handle_error "ошибка перезапуска Apache"

# Настройка SSL (опционально)
read -p "Установить SSL сертификат Let's Encrypt? (y/n): " SSL_CHOICE
if [[ $SSL_CHOICE =~ ^[Yy] ]]; then
    echo "Установка Certbot..."
    apt install -y certbot python3-certbot-apache || handle_error "ошибка установки Certbot"
    certbot --apache -d ${DOMAIN} --non-interactive --agree-tos --email admin@${DOMAIN} || handle_error "ошибка получения SSL"
fi

# Настройка cron
echo "Настройка cron-заданий..."
(crontab -u www-data -l 2>/dev/null; echo "*/5 * * * * php -f /var/www/nextcloud/cron.php") | crontab -u www-data - || handle_error "ошибка настройки cron"

sudo a2dissite 000-default.conf
sudo a2ensite nextcloud.conf
sudo systemctl restart apache2

echo "========================================================"
echo "           НАСТРОЙКИ ДЛЯ ПЕРВОГО ВХОДА В NEXTCLOUD       "
echo "========================================================"
echo "URL: https://${DOMAIN}"
echo "Логин: ${NEXTCLOUD_USER}"
echo "Пароль администратора: ${ADMIN_PASSWORD}"
echo "Пароль БД: ${DB_PASSWORD}"
echo "Хост БД: localhost"
echo "Имя БД: nextcloud"
echo "Путь к данным: ${DATA_DIR}"
echo "Версия PHP: ${PHP_VERSION}"





