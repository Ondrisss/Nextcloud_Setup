#!/bin/bash

# Проверка прав root
if [ "$(id -u)" != "0" ]; then
    echo "Ошибка: скрипт требует root-прав. Запустите с sudo." >&2
    exit 1
fi

echo "=== Начало очистки Nextcloud ==="

# Остановка сервисов
echo "Остановка сервисов..."
systemctl stop apache2 2>/dev/null
systemctl stop mariadb 2>/dev/null

# Удаление файлов Nextcloud
echo "Удаление файлов Nextcloud..."
rm -rf /var/www/nextcloud 2>/dev/null

# Удаление конфигов Apache
echo "Удаление конфигурации Apache..."
rm -f /etc/apache2/sites-available/nextcloud.conf 2>/dev/null
rm -f /etc/apache2/sites-enabled/nextcloud.conf 2>/dev/null

# Удаление репозиториев PHP
echo "Удаление репозиториев PHP..."
rm -f /etc/apt/sources.list.d/php.list 2>/dev/null
rm -f /etc/apt/trusted.gpg.d/php.gpg 2>/dev/null

# Удаление пакетов
echo "Удаление пакетов..."
apt purge -y apache2* mariadb-server* php* libapache2* certbot* python3-certbot-* unzip 2>/dev/null
apt autoremove -y 2>/dev/null

# Удаление cron-заданий
echo "Удаление cron-заданий..."
crontab -u www-data -r 2>/dev/null

# Удаление базы данных
echo "Удаление базы данных..."
mysql -e "DROP DATABASE IF EXISTS nextcloud;" 2>/dev/null
mysql -e "DROP USER IF EXISTS 'nextcloud'@'localhost';" 2>/dev/null

echo "=== Очистка завершена успешно ==="