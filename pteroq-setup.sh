#!/bin/bash
set -e

# -------------------- CONFIG --------------------
FQDN="${FQDN:-localhost}"
MYSQL_DB="${MYSQL_DB:-panel}"
MYSQL_USER="${MYSQL_USER:-pterodactyl}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-$(openssl rand -base64 24)}"
TIMEZONE="${TIMEZONE:-UTC}"

EMAIL="${EMAIL:-admin@example.com}"
USER_EMAIL="${USER_EMAIL:-admin@example.com}"
USER_USERNAME="${USER_USERNAME:-admin}"
USER_FIRSTNAME="${USER_FIRSTNAME:-Admin}"
USER_LASTNAME="${USER_LASTNAME:-User}"
USER_PASSWORD="${USER_PASSWORD:-password123}"

PANEL_DL_URL="https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"

# -------------------- UTILS --------------------

function output() { echo -e "\033[1;34m[*]\033[0m $1"; }
function success() { echo -e "\033[1;32m[+]\033[0m $1"; }
function error() { echo -e "\033[1;31m[!]\033[0m $1" >&2; }

# -------------------- FUNCTIONS --------------------

install_dependencies() {
  output "Updating repositories and installing dependencies"
  apt update && apt upgrade -y
  apt install -y software-properties-common curl apt-transport-https ca-certificates gnupg unzip git redis-server mariadb-server php8.3 php8.3-cli php8.3-fpm php8.3-mysql php8.3-mbstring php8.3-xml php8.3-bcmath php8.3-curl php8.3-zip php8.3-common php8.3-gd php8.3-readline php8.3-opcache cron
  systemctl enable --now mariadb redis-server php8.3-fpm
  success "Dependencies installed"
}

install_composer() {
  output "Installing Composer"
  curl -sS https://getcomposer.org/installer | php
  mv composer.phar /usr/local/bin/composer
  chmod +x /usr/local/bin/composer
  success "Composer installed"
}

download_panel() {
  output "Downloading Pterodactyl panel"
  mkdir -p /var/www/pterodactyl
  cd /var/www/pterodactyl
  curl -Lo panel.tar.gz "$PANEL_DL_URL"
  tar -xzvf panel.tar.gz --strip-components=1
  chmod -R 755 storage/* bootstrap/cache
  cp .env.example .env
  success "Panel downloaded and initialized"
}

install_php_dependencies() {
  output "Installing PHP dependencies with Composer"
  cd /var/www/pterodactyl
  COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
  success "PHP dependencies installed"
}

setup_database() {
  output "Creating MySQL user and database"
  mysql -u root <<EOF
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'localhost' IDENTIFIED BY '${MYSQL_PASSWORD}';
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DB}\`;
GRANT ALL PRIVILEGES ON \`${MYSQL_DB}\`.* TO '${MYSQL_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
  success "Database and user created"
}

configure_panel() {
  output "Running Pterodactyl environment setup"
  cd /var/www/pterodactyl

  php artisan key:generate --force

  php artisan p:environment:setup \
    --author="$EMAIL" \
    --url="https://$FQDN" \
    --timezone="$TIMEZONE" \
    --cache="redis" \
    --session="redis" \
    --queue="redis"

  php artisan p:environment:database \
    --host="127.0.0.1" \
    --port="3306" \
    --database="$MYSQL_DB" \
    --username="$MYSQL_USER" \
    --password="$MYSQL_PASSWORD"

  php artisan migrate --seed --force

  php artisan p:user:make \
    --email="$USER_EMAIL" \
    --username="$USER_USERNAME" \
    --name-first="$USER_FIRSTNAME" \
    --name-last="$USER_LASTNAME" \
    --password="$USER_PASSWORD" \
    --admin=1

  success "Panel configured"
}

setup_permissions() {
  output "Setting permissions for www-data"
  chown -R www-data:www-data /var/www/pterodactyl
  success "Permissions set"
}

setup_cron() {
  output "Adding Laravel scheduler to crontab"
  (crontab -l 2>/dev/null; echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1") | crontab -
  success "Cronjob added"
}

setup_pteroq() {
  output "Creating pteroq service"
  cat <<EOF >/etc/systemd/system/pteroq.service
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service
Requires=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reexec
  systemctl enable --now pteroq.service
  success "pteroq service installed and started"
}

# -------------------- MAIN --------------------

main() {
  install_dependencies
  install_composer
  download_panel
  install_php_dependencies
  setup_database
  configure_panel
  setup_permissions
  setup_cron
  setup_pteroq

  success "Pterodactyl Panel installed! Now run your nginx and certbot scripts."
}

main
