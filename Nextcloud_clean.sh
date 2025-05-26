#!/bin/bash

# Функция для полной очистки системы
cleanup() {
    echo "=== Начало очистки системы ==="
    
    # Остановка сервисов
    echo "Остановка сервисов..."
    systemctl stop apache2 2>/dev/null
    systemctl stop mariadb 2>/dev/null
    
    # Удаление Nextcloud
    echo "Удаление файлов Nextcloud..."
    rm -rf /var/www/nextcloud 2>/dev/null
    
    # Удаление репозиториев
    echo "Удаление репозиториев PHP..."
    rm -f /etc/apt/sources.list.d/php.list 2>/dev/null
    rm -f /etc/apt/trusted.gpg.d/php.gpg 2>/dev/null
    
    # Удаление пакетов
    echo "Удаление пакетов..."
    apt purge -y apache2* mariadb* php* libapache2* certbot* python3-certbot* 2>/dev/null
    apt autoremove -y 2>/dev/null
    
    # Удаление cron
    echo "Удаление cron-заданий..."
    crontab -u www-data -r 2>/dev/null
    
    # Удаление БД
    echo "Удаление базы данных..."
    mysql -e "DROP DATABASE IF EXISTS nextcloud;" 2>/dev/null
    mysql -e "DROP USER IF EXISTS 'nextcloud'@'localhost';" 2>/dev/null
    
    echo "=== Очистка завершена успешно ==="
}

# Проверка прав root
if [ "$(id -u)" != "0" ]; then
    echo "Ошибка: этот скрипт должен быть запущен от root" 1>&2
    exit 1
fi

# Вызов основной функции
cleanup