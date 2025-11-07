#!/bin/bash

## Parse named parameters
##
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --CUSTOM_PORT) CUSTOM_PORT="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Update repositories
export DEBIAN_FRONTEND=dialog
apt-get -o DPkg::Lock::Timeout=60 update

# Install apache2
echo "Installing apache2..."
apt-get -o DPkg::Lock::Timeout=60 install -y apache2

# Install MySQL Server
echo "Installing MySQL Server..."
apt-get -o DPkg::Lock::Timeout=60 install -y mysql-server

# Run MySQL secure installation with automated responses.
# Modify these responses as needed for your security requirements.
echo "Securing MySQL installation..."
mysql_secure_installation <<EOF

y
n
y
y
y
y
EOF

# Enable and start the MySQL service
systemctl enable mysql
systemctl start mysql

# Configure MySQL to listen on all ports
sed -i 's/^bind-address\s*=.*/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf

systemctl restart mysql

echo "MySQL has been provisioned successfully."

# Set a custom port for SSH (only if customPort=true is passed)
if [ "$CUSTOM_PORT" = true ]; then
  echo "Configuring SSH to use custom port 2222..."
  mkdir -p /etc/systemd/system/ssh.socket.d
  cat >/etc/systemd/system/ssh.socket.d/listen.conf <<EOF
[Socket]
ListenStream=
ListenStream=2222
EOF

  # Restart SSH service
  systemctl daemon-reload
  systemctl restart ssh.socket
  echo "SSH has been configured to use port 2222."
else
  echo "SSH will continue to use the default port 22."
fi

# Setup a simple hello world page
echo "<html><body><h1>This is machine ${HOSTNAME}</h1></body></html>" > /var/www/html/index.html

# Configure Apache to listen on port 8080
echo "Configuring Apache to listen on port 8080..."
sed -i '/^Listen 80$/s/^Listen 80$/Listen 8080/' /etc/apache2/ports.conf
sed -i 's/<VirtualHost \*:80>/<VirtualHost *:8080>/' /etc/apache2/sites-available/000-default.conf

# Restart apache2 service to apply changes
systemctl restart apache2