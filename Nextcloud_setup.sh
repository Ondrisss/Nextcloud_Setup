#!/bin/bash

# Конфигурация
DB_PASSWORD=$(openssl rand -base64 12)
NEXTCLOUD_USER="admin"
ADMIN_PASSWORD=$(openssl rand -base64 12)
read -p "Введите домен сайта (для Certbot): " DOMAIN
DATA_DIR="/var/www/nextcloud/data"

# Настройки PHP
PHP_UPLOAD_LIMIT="16G"
PHP_POST_LIMIT="16G"
PHP_MEMORY_LIMIT="512M"
PHP_VERSION="8.2"  # Явно указываем версию PHP для совместимости

# Проверка root
if [ "$(id -u)" != "0" ]; then
   echo "Этот скрипт должен быть запущен от root" 1>&2
   exit 1
fi

# Функция для обработки ошибок
handle_error() {
    echo "Ошибка при выполнении команды: $1"
    exit 1
}

# Обновление системы
echo "Обновление системы..."
apt update && apt upgrade -y || handle_error "system update"

# Установка Apache
echo "Установка Apache..."
apt install -y apache2 || handle_error "Apache installation"
systemctl enable --now apache2

# Установка MariaDB
echo "Установка MariaDB..."
apt install -y mariadb-server || handle_error "MariaDB installation"
systemctl enable --now mariadb

# Настройка безопасности MariaDB
mysql -e "DELETE FROM mysql.user WHERE User='';" || handle_error "MariaDB secure 1"
mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');" || handle_error "MariaDB secure 2"
mysql -e "DROP DATABASE IF EXISTS test;" || handle_error "MariaDB secure 3"
mysql -e "FLUSH PRIVILEGES;" || handle_error "MariaDB secure 4"

# Удаление существующей базы данных Nextcloud (если есть)
echo "Проверка существующей базы данных..."
mysql -e "DROP DATABASE IF EXISTS nextcloud;" || handle_error "Drop existing DB"
mysql -e "DROP USER IF EXISTS 'nextcloud'@'localhost';" || handle_error "Drop existing user"
mysql -e "FLUSH PRIVILEGES;" || handle_error "Flush privileges after cleanup"

# Создание базы данных
echo "Создание базы данных..."
mysql -e "CREATE DATABASE nextcloud;" || handle_error "DB creation"
mysql -e "CREATE USER 'nextcloud'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';" || handle_error "DB user creation"
mysql -e "GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'localhost';" || handle_error "DB privileges"
mysql -e "FLUSH PRIVILEGES;" || handle_error "DB flush"

# Установка PHP
echo "Добавление репозитория PHP..."
apt install -y software-properties-common || handle_error "software-properties-common"
add-apt-repository ppa:ondrej/php -y || handle_error "PHP repo"
apt update || handle_error "apt update after PHP repo"

echo "Установка PHP и модулей..."
apt install -y php${PHP_VERSION} php${PHP_VERSION}-curl php${PHP_VERSION}-gd \
php${PHP_VERSION}-mbstring php${PHP_VERSION}-xml php${PHP_VERSION}-zip \
php${PHP_VERSION}-mysql php${PHP_VERSION}-intl php${PHP_VERSION}-imagick \
php${PHP_VERSION}-bcmath php${PHP_VERSION}-gmp php${PHP_VERSION}-apcu \
php${PHP_VERSION}-redis || handle_error "PHP packages"

# Настройка PHP
PHP_INI_PATH="/etc/php/${PHP_VERSION}/apache2/php.ini"
echo "Настройка PHP-лимитов..."
sed -i "s/^\(;\?\)upload_max_filesize =.*/upload_max_filesize = ${PHP_UPLOAD_LIMIT}/" "$PHP_INI_PATH"
sed -i "s/^\(;\?\)post_max_size =.*/post_max_size = ${PHP_POST_LIMIT}/" "$PHP_INI_PATH"
sed -i "s/^\(;\?\)memory_limit =.*/memory_limit = ${PHP_MEMORY_LIMIT}/" "$PHP_INI_PATH"

# Установка Nextcloud
echo "Установка Nextcloud..."
cd /var/www/ || handle_error "cd /var/www"
wget https://download.nextcloud.com/server/releases/latest.zip || handle_error "Nextcloud download"
unzip latest.zip || handle_error "Nextcloud unzip"
chown -R www-data:www-data nextcloud || handle_error "chown nextcloud"
rm latest.zip

# Настройка Apache
echo "Настройка Apache..."
cat > /etc/apache2/sites-available/nextcloud.conf <<EOF
<VirtualHost *:80>
    DocumentRoot /var/www/nextcloud
    ServerName ${DOMAIN}

    <Directory /var/www/nextcloud>
        Require all granted
        AllowOverride All
        Options FollowSymLinks MultiViews
    </Directory>
</VirtualHost>
EOF

a2ensite nextcloud.conf || handle_error "a2ensite"
a2enmod rewrite headers env dir mime || handle_error "a2enmod"
systemctl restart apache2 || handle_error "apache restart"

# Установка Certbot
install_certbot() {
    echo "Установка Certbot через Snap..."
    if ! command -v snap &> /dev/null; then
        apt install -y snapd || return 1
    fi
    snap install core || return 1
    snap refresh core || return 1
    snap install --classic certbot || return 1
    ln -s /snap/bin/certbot /usr/bin/certbot || return 1
    return 0
}

# Опциональная установка SSL
read -p "Установить SSL с помощью Certbot? (y/n): " ssl_choice
if [[ $ssl_choice =~ ^[Yy]$ ]]; then
    if ! install_certbot; then
        echo "Не удалось установить Certbot через Snap, попробуем альтернативный метод..."
        apt install -y certbot python3-certbot-apache || handle_error "Certbot installation"
    fi
    certbot --apache -d ${DOMAIN} --non-interactive --agree-tos --email admin@${DOMAIN} || handle_error "Certbot execution"
fi

# Настройка cron
echo "Настройка cron..."
(crontab -u www-data -l 2>/dev/null; echo "*/5  *  *  *  * php -f /var/www/nextcloud/cron.php") | crontab -u www-data - || handle_error "cron setup"

# Итоговая информация
echo ""
echo "=================================================="
echo "Установка Nextcloud завершена!"
echo "Доступные данные:"
echo "URL: https://${DOMAIN}"
echo "Администратор: ${NEXTCLOUD_USER}"
echo "Пароль администратора: ${ADMIN_PASSWORD}"
echo "Пароль базы данных: ${DB_PASSWORD}"
echo "Каталог данных: ${DATA_DIR}"
echo "=================================================="

