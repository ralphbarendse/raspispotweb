#!/bin/bash

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Functions for output
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to execute remote commands
remote_cmd() {
    ssh "$REMOTE_USER@$REMOTE_HOST" "echo '$SUDO_PASS' | sudo -S bash -c '$1'"
    return $?
}

# Function for commands that should not error on non-zero exit
remote_cmd_no_error() {
    ssh "$REMOTE_USER@$REMOTE_HOST" "echo '$SUDO_PASS' | sudo -S bash -c '$1'" || true
    return 0
}

# Welcome message
clear
print_message "Welcome to Spotweb Installation Script"
echo "----------------------------------------"

# Get SSH credentials
while true; do
    read -p "Enter remote hostname (e.g., if its raspberrypi.local then just raspberrypi): " REMOTE_HOST
    if [ -n "$REMOTE_HOST" ]; then
        break
    else
        print_warning "Hostname cannot be empty. Please try again."
    fi
done

while true; do
    read -p "Enter SSH username: " REMOTE_USER
    if [ -n "$REMOTE_USER" ]; then
        break
    else
        print_warning "Username cannot be empty. Please try again."
    fi
done

while true; do
    read -s -p "Enter sudo password for $REMOTE_USER: " SUDO_PASS
    echo ""
    if [ -n "$SUDO_PASS" ]; then
        break
    else
        print_warning "Password cannot be empty. Please try again."
    fi
done

read -p "Enter timezone (default: Europe/Amsterdam): " USER_TIMEZONE
TIMEZONE=${USER_TIMEZONE:-"Europe/Amsterdam"}

print_message "Using SSH connection: $REMOTE_USER@$REMOTE_HOST"

# Check used ports
print_message "Checking currently used ports..."
echo "----------------------------------------"
remote_cmd "netstat -tuln | grep LISTEN"
echo "----------------------------------------"

# Get port for Spotweb
while true; do
    read -p "Enter port for Spotweb (default: 8080): " SPOTWEB_PORT
    SPOTWEB_PORT=${SPOTWEB_PORT:-8080}
    
    # Store the netstat output in a variable
    PORT_CHECK=$(ssh "$REMOTE_USER@$REMOTE_HOST" "netstat -tuln | grep -w :$SPOTWEB_PORT")
    
    if [ -z "$PORT_CHECK" ]; then
        print_message "Port $SPOTWEB_PORT is available and will be used for Spotweb."
        break
    else
        print_warning "Port $SPOTWEB_PORT is already in use. Please choose another port."
    fi
done

# Get Usenet details
read -p "Enter Usenet server (default: news.eweka.nl): " USENET_SERVER
USENET_SERVER=${USENET_SERVER:-news.eweka.nl}
read -p "Enter Usenet username: " USENET_USER
read -s -p "Enter Usenet password: " USENET_PASS
echo ""

# Test SSH connection before proceeding
print_message "Testing SSH connection..."
if ! ssh -q "$REMOTE_USER@$REMOTE_HOST" exit; then
    print_error "SSH connection failed! Please verify your SSH credentials and ensure the remote host is accessible."
fi

# Install required packages
print_message "Installing required packages..."
remote_cmd_no_error "apt-get update"
remote_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-server php php-mysql php-fpm php-gd php-cli php-curl php-xml php-zip nginx openssl git screen curl"

# Configure MySQL with proper quoting
print_message "Configuring MySQL..."

# Create a temporary SQL file
TMP_SQL="/tmp/setup_spotweb.sql"
cat > "${TMP_SQL}" << EOF
CREATE DATABASE IF NOT EXISTS spotweb;
CREATE USER IF NOT EXISTS 'spotweb'@'localhost' IDENTIFIED BY 'spotwebpass';
GRANT ALL PRIVILEGES ON spotweb.* TO 'spotweb'@'localhost';
FLUSH PRIVILEGES;
EOF

# Upload and execute the script remotely
print_message "Uploading MySQL configuration..."
scp "${TMP_SQL}" "$REMOTE_USER@$REMOTE_HOST:/tmp/setup_spotweb.sql"
print_message "Configuring MySQL database..."
remote_cmd "mysql < /tmp/setup_spotweb.sql"

# Clean up
print_message "Cleaning up temporary files..."
remote_cmd "rm -f /tmp/setup_spotweb.sql"
rm -f "${TMP_SQL}"

# Get PHP version and FPM socket path
print_message "Detecting PHP configuration..."
PHP_VERSION=$(ssh "$REMOTE_USER@$REMOTE_HOST" "php -v | grep -oP '^PHP \K[0-9]+\.[0-9]+' | tr -d '\r'")
print_message "Detected PHP version: $PHP_VERSION"

# Configure PHP
print_message "Configuring PHP..."

# Create temporary PHP configuration files
print_message "Creating PHP configuration files..."

# FPM configuration
TMP_FPM_INI="/tmp/php-fpm.ini"
cat > "${TMP_FPM_INI}" << EOF
[PHP]
date.timezone = "$TIMEZONE"
memory_limit = 512M
EOF

# CLI configuration
TMP_CLI_INI="/tmp/php-cli.ini"
cat > "${TMP_CLI_INI}" << EOF
[PHP]
date.timezone = "$TIMEZONE"
memory_limit = 512M
EOF

# Upload and apply configurations
print_message "Uploading PHP configurations..."
scp "${TMP_FPM_INI}" "$REMOTE_USER@$REMOTE_HOST:/tmp/php-fpm.ini"
scp "${TMP_CLI_INI}" "$REMOTE_USER@$REMOTE_HOST:/tmp/php-cli.ini"

print_message "Applying PHP configurations..."
remote_cmd "cat /tmp/php-fpm.ini >> /etc/php/${PHP_VERSION}/fpm/php.ini"
remote_cmd "cat /tmp/php-cli.ini >> /etc/php/${PHP_VERSION}/cli/php.ini"

# Clean up
print_message "Cleaning up temporary files..."
remote_cmd "rm -f /tmp/php-fpm.ini /tmp/php-cli.ini"
rm -f "${TMP_FPM_INI}" "${TMP_CLI_INI}"

# Create necessary directories
print_message "Creating necessary directories..."
remote_cmd "mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled /etc/nginx/conf.d /var/www"
remote_cmd "rm -f /etc/nginx/sites-enabled/*"

# Configure nginx (following HTPC Guides configuration)
print_message "Configuring nginx..."
TMP_NGINX_CONF="/tmp/spotweb.conf"
cat > "${TMP_NGINX_CONF}" << EOF
server {
    listen ${SPOTWEB_PORT};
    server_name _;
    root /var/www;
    index index.php index.html index.htm;

    location /spotweb {
        root /var/www;
        try_files \$uri \$uri/ /spotweb/index.php?\$args;

        location ~ \.php$ {
            try_files \$uri =404;
            include fastcgi_params;
            fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
            fastcgi_param PATH_INFO \$fastcgi_path_info;
            fastcgi_split_path_info ^(.+\.php)(/.+)$;
        }

        location ~ /api {
            satisfy any;
            allow all;
            rewrite ^/spotweb/api/?$ /spotweb/index.php?page=newznabapi last;
        }
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

# Upload and apply nginx configuration
print_message "Uploading nginx configuration..."
scp "${TMP_NGINX_CONF}" "$REMOTE_USER@$REMOTE_HOST:/tmp/spotweb.conf"
remote_cmd "mv /tmp/spotweb.conf /etc/nginx/sites-available/spotweb"

# Clean up
print_message "Cleaning up temporary files..."
rm -f "${TMP_NGINX_CONF}"

# Enable the site
print_message "Enabling nginx site..."
remote_cmd "ln -sf /etc/nginx/sites-available/spotweb /etc/nginx/sites-enabled/spotweb"
remote_cmd "rm -f /etc/nginx/sites-enabled/default"

# Install Spotweb
print_message "Installing Spotweb..."
remote_cmd "rm -rf /var/www/spotweb"
remote_cmd "git clone https://github.com/spotweb/spotweb /var/www/spotweb"

# Install composer dependencies with PHP 8.x compatibility
print_message "Installing composer dependencies..."
remote_cmd "cd /var/www/spotweb && curl -sS https://getcomposer.org/installer | php"
remote_cmd "cd /var/www/spotweb && rm -f composer.lock"
remote_cmd "cd /var/www/spotweb && COMPOSER_ALLOW_SUPERUSER=1 php composer.phar require phpseclib/phpseclib:^2.0 --update-with-dependencies"
remote_cmd "cd /var/www/spotweb && COMPOSER_ALLOW_SUPERUSER=1 php composer.phar require laminas/laminas-xml2json:^3.3 --update-with-dependencies"
remote_cmd "cd /var/www/spotweb && COMPOSER_ALLOW_SUPERUSER=1 php composer.phar update --with-all-dependencies"

# Create settings files
print_message "Creating configuration files..."

# Create temporary configuration files
TMP_DBSETTINGS="/tmp/dbsettings.inc.php"
TMP_SETTINGS="/tmp/settings.php"

# Create dbsettings.inc.php
cat > "${TMP_DBSETTINGS}" << EOF
<?php
\$dbsettings['engine'] = 'pdo_mysql';
\$dbsettings['host'] = 'localhost';
\$dbsettings['dbname'] = 'spotweb';
\$dbsettings['user'] = 'spotweb';
\$dbsettings['pass'] = 'spotwebpass';
\$dbsettings['port'] = '3306';
\$dbsettings['schema'] = '';
EOF

# Create settings.php
cat > "${TMP_SETTINGS}" << EOF
<?php
\$settings['installer_loaded'] = true;
\$settings['db'] = 'mysql';
\$settings['mysql']['host'] = 'localhost';
\$settings['mysql']['dbname'] = 'spotweb';
\$settings['mysql']['user'] = 'spotweb';
\$settings['mysql']['pass'] = 'spotwebpass';

# Usenet server settings
\$settings['nntp_nzb']['host'] = '${USENET_SERVER}';
\$settings['nntp_nzb']['user'] = '${USENET_USER}';
\$settings['nntp_nzb']['pass'] = '${USENET_PASS}';
\$settings['nntp_nzb']['port'] = '563';
\$settings['nntp_nzb']['enc'] = 'ssl';
\$settings['nntp_nzb']['hdr'] = false;
\$settings['nntp_hdr'] = \$settings['nntp_nzb'];
\$settings['nntp_post'] = \$settings['nntp_nzb'];
\$settings['retrieve_newer_than'] = time() - (730 * 24 * 60 * 60);
\$settings['retrieve_full'] = false;
\$settings['spot_group'] = array('free.usenet.nl.spots');
EOF

# Upload configuration files
print_message "Uploading configuration files..."
scp "${TMP_DBSETTINGS}" "$REMOTE_USER@$REMOTE_HOST:/tmp/dbsettings.inc.php"
scp "${TMP_SETTINGS}" "$REMOTE_USER@$REMOTE_HOST:/tmp/settings.php"

# Move files to final location
remote_cmd "mv /tmp/dbsettings.inc.php /var/www/spotweb/dbsettings.inc.php"
remote_cmd "mv /tmp/settings.php /var/www/spotweb/settings.php"

# Clean up temporary files
rm -f "${TMP_DBSETTINGS}" "${TMP_SETTINGS}"

# Set correct permissions
print_message "Setting permissions..."
remote_cmd "chown -R www-data:www-data /var/www/spotweb"
remote_cmd "chmod -R 755 /var/www/spotweb"
remote_cmd "chmod 644 /var/www/spotweb/dbsettings.inc.php /var/www/spotweb/settings.php"

# Initialize database
print_message "Initializing Spotweb database..."
remote_cmd "cd /var/www/spotweb && php bin/upgrade-db.php"

# Restart services
print_message "Restarting services..."
remote_cmd "systemctl enable php${PHP_VERSION}-fpm"
remote_cmd "systemctl restart php${PHP_VERSION}-fpm"
remote_cmd "systemctl status php${PHP_VERSION}-fpm"
remote_cmd "nginx -t && systemctl restart nginx"
remote_cmd "systemctl status nginx"

# Set up cron job for retrieval
print_message "Setting up cron job..."
remote_cmd "(crontab -l 2>/dev/null; echo \"00 * * * * cd /var/www/spotweb && php retrieve.php > /var/www/spotweb/retrieve.log\") | crontab -"

# Initial retrieval in screen session
print_message "Starting initial retrieval in screen session..."
remote_cmd "cd /var/www/spotweb && screen -dmS spotweb php retrieve.php"

# Final instructions
echo "----------------------------------------"
print_message "Installation completed!"
echo ""
print_message "Access Spotweb at: http://${REMOTE_HOST}:${SPOTWEB_PORT}/spotweb"
print_message "Complete the setup by visiting: http://${REMOTE_HOST}:${SPOTWEB_PORT}/spotweb/install.php"
echo ""
print_message "To monitor the retrieval process:"
echo "ssh ${REMOTE_USER}@${REMOTE_HOST}"
echo "screen -r spotweb"
echo ""
print_message "To detach from screen: Press Ctrl+A, then D"
print_message "To view logs: tail -f /var/www/spotweb/retrieve.log" 