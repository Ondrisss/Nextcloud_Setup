#!/bin/bash

# Конфигурация
# Генерация случайного пароля для базы данных
DB_PASSWORD=$(openssl rand -base64 12)
# Имя пользователя для входа в Nextcloud
NEXTCLOUD_USER="admin"
# Генерация случайного пароля для администратора Nextcloud
ADMIN_PASSWORD=$(openssl rand -base64 12)
# Запрос домена у пользователя для настройки Certbot
DOMAIN=$(read -p "Введите домен сайта(для Certbot):" answer)
# Путь к каталогу данных Nextcloud
DATA_DIR="/var/www/nextcloud/data"

# Настройки PHP
# Максимальный размер загружаемого файла
PHP_UPLOAD_LIMIT="16G"
# Максимальный размер POST-запроса
PHP_POST_LIMIT="16G"
# Лимит памяти для PHP
PHP_MEMORY_LIMIT="512M"
# Автоматическое определение пути к php.ini на основе версии PHP
PHP_INI_PATH="/etc/php/$(php -v 2>/dev/null | grep -oP 'PHP \K\d+\.\d+' || echo '8.2')/apache2/php.ini"

# Проверка, что скрипт запущен от root
if [ "$(id -u)" != "0" ]; then
   echo "Этот скрипт должен быть запущен от root" 1>&2
   exit 1
fi

# Обновление системы
echo "Обновление системы..."
apt update && apt upgrade -y

# Установка Apache
echo "Установка Apache..."
apt install apache2 -y
systemctl enable --now apache2

# Установка MariaDB
echo "Установка MariaDB..."
apt install mariadb-server -y
systemctl enable --now mariadb

# Настройка безопасности MariaDB
mysql -e "DELETE FROM mysql.user WHERE User='';"
mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
mysql -e "DROP DATABASE IF EXISTS test;"
mysql -e "FLUSH PRIVILEGES;"

# Создание базы данных для Nextcloud
echo "Создание базы данных..."
mysql -e "CREATE DATABASE nextcloud;"
mysql -e "CREATE USER 'nextcloud'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -e "GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# Установка PHP и необходимых модулей
echo "Установка PHP..."
apt install -y php php-curl php-gd php-mbstring php-xml php-zip php-mysql php-intl \
php-imagick php-bcmath php-gmp php-apcu php-redis

# Настройка лимитов PHP
echo "Настройка PHP-лимитов..."
sed -i "s/^\(;\?\)upload_max_filesize =.*/upload_max_filesize = ${PHP_UPLOAD_LIMIT}/" $PHP_INI_PATH
sed -i "s/^\(;\?\)post_max_size =.*/post_max_size = ${PHP_POST_LIMIT}/" $PHP_INI_PATH
sed -i "s/^\(;\?\)memory_limit =.*/memory_limit = ${PHP_MEMORY_LIMIT}/" $PHP_INI_PATH

# Загрузка и установка Nextcloud
echo "Установка Nextcloud..."
cd /var/www/
wget https://download.nextcloud.com/server/releases/latest.zip
unzip latest.zip
chown -R www-data:www-data nextcloud  # Установка прав для веб-сервера
rm latest.zip

# Настройка виртуального хоста Apache для Nextcloud
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

# Активация сайта и модулей Apache
a2ensite nextcloud.conf
a2enmod rewrite headers env dir mime
systemctl restart apache2

# Опциональная установка SSL с помощью Certbot
read -p "Установить SSL с помощью Certbot? (y/n): " ssl_choice
if [[ $ssl_choice =~ ^[Yy]$ ]]; then
    apt install -y certbot python3-certbot-apache
    certbot --apache -d ${DOMAIN} --non-interactive --agree-tos --email admin@${DOMAIN}
fi

# Настройка cron для автоматического выполнения задач Nextcloud
echo "Настройка cron..."
(crontab -u www-data -l 2>/dev/null; echo "*/5  *  *  *  * php -f /var/www/nextcloud/cron.php") | crontab -u www-data -

# Вывод итоговой информации
echo ""
echo "=================================================="
echo "Установка Nextcloud завершена!"
echo "Доступные данные:"
echo "URL: http://${DOMAIN}"
echo "Администратор: ${NEXTCLOUD_USER}"
echo "Пароль администратора: ${ADMIN_PASSWORD}"
echo "Пароль базы данных: ${DB_PASSWORD}"
echo "Каталог данных: ${DATA_DIR}"
echo "=================================================="

