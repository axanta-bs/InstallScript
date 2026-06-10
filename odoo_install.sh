#!/bin/bash
################################################################################
# Script for installing Odoo on Ubuntu 16.04, 18.04, 20.04 and 22.04 (could be used for other version too)
# Author: Yenthe Van Ginneken
#-------------------------------------------------------------------------------
# This script will install Odoo on your Ubuntu server. It can install multiple Odoo instances
# in one Ubuntu because of the different xmlrpc_ports
#-------------------------------------------------------------------------------
# Make a new file:
# sudo nano odoo-install.sh
# Place this content in it and then make the file executable:
# sudo chmod +x odoo-install.sh
# Execute the script to install Odoo:
# ./odoo-install
################################################################################

OE_USER="axanta"
OE_HOME="/$OE_USER"
OE_HOME_EXT="/$OE_USER/${OE_USER}-server"
# The default port where this Odoo instance will run under (provided you use the command -c in the terminal)
# Set to true if you want to install it, false if you don't need it or have it already installed.
INSTALL_WKHTMLTOPDF="True"
# Set the default Odoo port (you still have to use -c /etc/odoo-server.conf for example to use this.)
OE_PORT="8069"
# Choose the Odoo version which you want to install. For example: 16.0, 15.0, 14.0 or saas-22. When using 'master' the master version will be installed.
# IMPORTANT! This script contains extra libraries that are specifically needed for Odoo 16.0
OE_VERSION="16.0"
# Set this to True if you want to install the Odoo enterprise version!
IS_ENTERPRISE="False"
# Installs postgreSQL V14 instead of defaults (e.g V12 for Ubuntu 20/22) - this improves performance
INSTALL_POSTGRESQL_FOURTEEN="True"
# Set this to True if you want to install Nginx!
INSTALL_NGINX="True"
# Set the superadmin password - if GENERATE_RANDOM_PASSWORD is set to "True" we will automatically generate a random password, otherwise we use this one
OE_SUPERADMIN="admin"
# Set to "True" to generate a random password, "False" to use the variable in OE_SUPERADMIN
GENERATE_RANDOM_PASSWORD="True"
OE_CONFIG="${OE_USER}-server"
WORKDIR="$(pwd)"
# Set the website name
WEBSITE_NAME="_"
# Set the default Odoo longpolling port (you still have to use -c /etc/odoo-server.conf for example to use this.)
LONGPOLLING_PORT="8072"
# Set to "True" to install certbot and have ssl enabled, "False" to use http
ENABLE_SSL="True"
# Provide Email to register ssl certificate
ADMIN_EMAIL="odoo@example.com"

AXANTA_REPO=https://github.com/burhanghee/ax-addons-16.git
AXANTA_BRANCH=16.0
AXANTA_ADDONS_PATH=$OE_HOME_EXT/ax-addons-16

PYTHON_VERSION="3.10.12"
PYTHON_SHORT_VERSION="${PYTHON_VERSION%.*}"
PYTHON_BIN="/usr/local/bin/python${PYTHON_SHORT_VERSION}"
ODOO_VENV="$OE_HOME_EXT/venv"
ODOO_PYTHON_BIN="$ODOO_VENV/bin/python"
ODOO_PIP_BIN="$ODOO_VENV/bin/pip"
if command -v lsb_release >/dev/null 2>&1; then
    UBUNTU_VERSION="$(lsb_release -r -s)"
    UBUNTU_CODENAME="$(lsb_release -c -s)"
elif [ -r /etc/os-release ]; then
    . /etc/os-release
    UBUNTU_VERSION="${VERSION_ID:-}"
    UBUNTU_CODENAME="${VERSION_CODENAME:-}"
else
    UBUNTU_VERSION=""
    UBUNTU_CODENAME=""
fi


#--------------------------------------------------
# Define color variables
#--------------------------------------------------
NC='\e[0m';
REDC='\e[31m';
GREENC='\e[32m';
YELLOWC='\e[33m';
BLUEC='\e[34m';
LBLUEC='\e[94m';

print_step() {
    echo -e "\n${BLUEC}---- $1 ----${NC}"
}

print_info() {
    echo -e "${LBLUEC}$1${NC}"
}

print_success() {
    echo -e "${GREENC}$1${NC}"
}

print_warning() {
    echo -e "${YELLOWC}$1${NC}"
}

print_error() {
    echo -e "${REDC}$1${NC}"
}

install_python_from_source() {
    if [ -x "$PYTHON_BIN" ]; then
        INSTALLED_VERSION=$("$PYTHON_BIN" -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')
        if [ "$INSTALLED_VERSION" = "$PYTHON_VERSION" ]; then
            print_success "Python $PYTHON_VERSION is already installed at $PYTHON_BIN"
            return
        fi
        print_warning "$PYTHON_BIN exists but is Python $INSTALLED_VERSION. Rebuilding Python $PYTHON_VERSION."
    fi

    PYTHON_TARBALL="Python-${PYTHON_VERSION}.tgz"
    PYTHON_SOURCE_DIR="/tmp/Python-${PYTHON_VERSION}"

    print_info "Downloading Python $PYTHON_VERSION source"
    cd /tmp || exit 1
    sudo rm -rf "$PYTHON_SOURCE_DIR" "$PYTHON_TARBALL"
    wget -O "$PYTHON_TARBALL" "https://www.python.org/ftp/python/${PYTHON_VERSION}/${PYTHON_TARBALL}" || exit 1
    tar -xzf "$PYTHON_TARBALL" || exit 1

    print_info "Building Python $PYTHON_VERSION"
    cd "$PYTHON_SOURCE_DIR" || exit 1
    ./configure --with-ensurepip=install || exit 1
    make -j "$(nproc)" || exit 1
    sudo make altinstall || exit 1
    cd "$WORKDIR" || exit 1

    INSTALLED_VERSION=$("$PYTHON_BIN" -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')
    if [ "$INSTALLED_VERSION" != "$PYTHON_VERSION" ]; then
        print_error "Expected Python $PYTHON_VERSION, but $PYTHON_BIN reports $INSTALLED_VERSION"
        exit 1
    fi
    print_success "Python $PYTHON_VERSION installed at $PYTHON_BIN"
}

clone_or_update_repo() {
    local repo_url="$1"
    local branch="$2"
    local target="$3"
    local repo_name
    repo_name="$(basename "$target")"

    if [ -d "$target/.git" ]; then
        print_warning "$repo_name already exists. Updating branch $branch..."
        sudo -u "$OE_USER" git -C "$target" fetch --depth 1 origin "$branch" || exit 1
        sudo -u "$OE_USER" git -C "$target" checkout "$branch" || exit 1
        sudo -u "$OE_USER" git -C "$target" pull --ff-only origin "$branch" || exit 1
        print_success "$repo_name updated."
    elif [ -e "$target" ]; then
        print_error "$target exists but is not a git repository. Move it away before running this script again."
        exit 1
    else
        sudo -u "$OE_USER" git clone --depth 1 --branch "$branch" "$repo_url" "$target" || exit 1
    fi
}

##
###  WKHTMLTOPDF download links
## === Ubuntu Trusty x64 & x32 === (for other distributions please replace these two links,
## in order to have correct version of wkhtmltopdf installed, for a danger note refer to
## https://github.com/odoo/odoo/wiki/Wkhtmltopdf ):
## https://www.odoo.com/documentation/16.0/administration/install.html

# Ubuntu 22.04 installs wkhtmltopdf from apt. Older releases use wkhtmltox packages.
if [[ "$UBUNTU_VERSION" != "22.04" ]]; then
    # For older versions of Ubuntu
    WKHTMLTOX_X64="https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.5/wkhtmltox_0.12.5-1.${UBUNTU_CODENAME}_amd64.deb"
    WKHTMLTOX_X32="https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.5/wkhtmltox_0.12.5-1.${UBUNTU_CODENAME}_i386.deb"
fi

#--------------------------------------------------
# Update Server
#--------------------------------------------------
print_step "Update Server"
sudo apt-get update || exit 1
sudo apt-get install software-properties-common curl ca-certificates gnupg -y || exit 1
# universe package is for Ubuntu 18.x
sudo add-apt-repository universe -y || exit 1
# libpng12-0 dependency for wkhtmltopdf for older Ubuntu versions
if [ "$INSTALL_WKHTMLTOPDF" = "True" ] && [[ "$UBUNTU_VERSION" != "22.04" ]]; then
    sudo add-apt-repository "deb https://mirrors.kernel.org/ubuntu/ xenial main" -y || exit 1
fi
sudo apt-get update || exit 1
sudo apt-get upgrade -y || exit 1
sudo apt-get install libpq-dev -y || exit 1

#--------------------------------------------------
# Install PostgreSQL Server
#--------------------------------------------------
print_step "Install PostgreSQL Server"
if [ "$INSTALL_POSTGRESQL_FOURTEEN" = "True" ]; then
    print_info "Installing PostgreSQL V14 due to the user's choice"
    sudo curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc|sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg || exit 1
    sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' || exit 1
    sudo apt-get update || exit 1
    sudo apt-get install postgresql-14 -y || exit 1
else
    print_info "Installing the default PostgreSQL version based on Linux version"
    sudo apt-get install postgresql postgresql-server-dev-all -y || exit 1
fi


print_step "Creating the ODOO PostgreSQL User"
sudo su - postgres -c "createuser -s $OE_USER" 2> /dev/null || true

#--------------------------------------------------
# Install Dependencies
#--------------------------------------------------
print_step "Installing Python ${PYTHON_VERSION} build dependencies"
sudo apt-get install git build-essential make wget xz-utils tk-dev libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev libncursesw5-dev libffi-dev liblzma-dev libxml2-dev libxmlsec1-dev llvm python3-cffi python3-dev python3-venv python3-wheel libxslt-dev libzip-dev libldap2-dev libsasl2-dev python3-setuptools node-less libpng-dev libjpeg-dev gdebi -y || exit 1
install_python_from_source

print_step "Installing nodeJS NPM and rtlcss for LTR support"
sudo apt-get install nodejs npm -y || exit 1
sudo npm install -g rtlcss || exit 1

if [ "$INSTALL_WKHTMLTOPDF" = "True" ]; then
  print_step "Install wkhtmltopdf"
  if [[ "$UBUNTU_VERSION" == "22.04" ]]; then
    sudo apt-get install wkhtmltopdf -y || exit 1
  else
    # Pick up correct one from x64 & x32 versions.
    if [ "$(getconf LONG_BIT)" = "64" ]; then
        _url="$WKHTMLTOX_X64"
    else
        _url="$WKHTMLTOX_X32"
    fi
    _wkhtml_deb="/tmp/$(basename "$_url")"
    wget -O "$_wkhtml_deb" "$_url" || exit 1
    sudo gdebi --n "$_wkhtml_deb" || exit 1
    sudo ln -sf /usr/local/bin/wkhtmltopdf /usr/bin/wkhtmltopdf
    sudo ln -sf /usr/local/bin/wkhtmltoimage /usr/bin/wkhtmltoimage
  fi
else
  print_warning "Wkhtmltopdf isn't installed due to the choice of the user!"
fi

print_step "Create ODOO system user"
if id "$OE_USER" >/dev/null 2>&1; then
    print_warning "User $OE_USER already exists."
else
    sudo adduser --system --quiet --shell=/bin/bash --home="$OE_HOME" --gecos 'ODOO' --group "$OE_USER"
fi
#The user should also be added to the sudo'ers group.
sudo adduser "$OE_USER" sudo

print_step "Create Log directory"
sudo mkdir -p "$OE_HOME"
sudo mkdir -p "/var/log/$OE_USER"
sudo chown "$OE_USER:$OE_USER" "/var/log/$OE_USER"
sudo chown -R "$OE_USER:$OE_USER" "$OE_HOME"

#--------------------------------------------------
# Install ODOO
#--------------------------------------------------
print_step "Installing ODOO Server"
clone_or_update_repo "https://www.github.com/odoo/odoo" "$OE_VERSION" "$OE_HOME_EXT"

print_step "Installing Axanta Addons"
clone_or_update_repo "$AXANTA_REPO" "$AXANTA_BRANCH" "$AXANTA_ADDONS_PATH"

print_step "Creating ODOO Python virtual environment"
sudo "$PYTHON_BIN" -m venv "$ODOO_VENV" || exit 1
sudo "$ODOO_PYTHON_BIN" -m pip install --upgrade pip setuptools wheel || exit 1

print_step "Installing python packages/requirements"
sudo "$ODOO_PYTHON_BIN" -m pip install -r "https://github.com/odoo/odoo/raw/${OE_VERSION}/requirements.txt" || exit 1
if [ -f "$AXANTA_ADDONS_PATH/requirements.txt" ]; then
    sudo "$ODOO_PYTHON_BIN" -m pip install -r "$AXANTA_ADDONS_PATH/requirements.txt" || exit 1
else
    print_warning "No Axanta requirements.txt found at $AXANTA_ADDONS_PATH/requirements.txt"
fi


print_step "Setting permissions on home folder"
sudo chown -R "$OE_USER:$OE_USER" "$OE_HOME"

print_info "* Create server config file"


print_info "* Creating server config file"
if [ "$GENERATE_RANDOM_PASSWORD" = "True" ]; then
    print_info "* Generating random admin password"
    OE_SUPERADMIN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
fi
if [[ "$OE_VERSION" > "11.0" ]]; then
    PORT_OPTION="http_port"
else
    PORT_OPTION="xmlrpc_port"
fi
if [ "$INSTALL_NGINX" = "True" ]; then
    PROXY_MODE="True"
else
    PROXY_MODE="False"
fi

AXANTA_ADDONS_DIR=$AXANTA_ADDONS_PATH,$AXANTA_ADDONS_PATH/oca_addons,$AXANTA_ADDONS_PATH/3rd_party_addons,$AXANTA_ADDONS_PATH/oca_reporting_addons,$AXANTA_ADDONS_PATH/tier_validation,$AXANTA_ADDONS_PATH/client_addons,$AXANTA_ADDONS_PATH/oca_operating_unit;

sudo tee "/etc/${OE_CONFIG}.conf" > /dev/null <<EOF
[options]
; This is the password that allows database operations:
admin_passwd = ${OE_SUPERADMIN}
${PORT_OPTION} = ${OE_PORT}
gevent_port = ${LONGPOLLING_PORT}
proxy_mode = ${PROXY_MODE}
logfile = /var/log/${OE_USER}/${OE_CONFIG}.log
addons_path=${OE_HOME_EXT}/addons,${AXANTA_ADDONS_DIR}
workers = 5
max_cron_threads = 1
limit_memory_hard = 24159191040000
limit_memory_soft = 20132659200000
limit_time_real = 3000000
limit_time_cpu = 3000000
limit_request = 999999
db_maxconn = 5
server_wide_modules = web,base_ext,letsencrypt
modules_auto_install_disabled = partner_autocomplete
EOF

sudo chown "$OE_USER:$OE_USER" "/etc/${OE_CONFIG}.conf"
sudo chmod 640 "/etc/${OE_CONFIG}.conf"

print_info "* Create startup file"
sudo tee "$OE_HOME_EXT/start.sh" > /dev/null <<EOF
#!/bin/sh
sudo -u $OE_USER $ODOO_PYTHON_BIN $OE_HOME_EXT/odoo-bin --config=/etc/${OE_CONFIG}.conf
EOF
sudo chmod 755 "$OE_HOME_EXT/start.sh"

#--------------------------------------------------
# Adding ODOO as a deamon (initscript)
#--------------------------------------------------

print_info "* Create init file"
cat <<EOF > ~/$OE_CONFIG
#!/bin/sh
### BEGIN INIT INFO
# Provides: $OE_CONFIG
# Required-Start: \$remote_fs \$syslog
# Required-Stop: \$remote_fs \$syslog
# Should-Start: \$network
# Should-Stop: \$network
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: Enterprise Business Applications
# Description: ODOO Business Applications
### END INIT INFO
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin
PYTHON_BIN=$ODOO_PYTHON_BIN
DAEMON=$OE_HOME_EXT/odoo-bin
NAME=$OE_CONFIG
DESC=$OE_CONFIG
# Specify the user name (Default: odoo).
USER=$OE_USER
# Specify an alternate config file (Default: /etc/openerp-server.conf).
CONFIGFILE="/etc/${OE_CONFIG}.conf"
# pidfile
PIDFILE=/var/run/\${NAME}.pid
# Additional options that are passed to the Daemon.
DAEMON_OPTS="-c \$CONFIGFILE"
[ -x \$PYTHON_BIN ] || exit 0
[ -f \$DAEMON ] || exit 0
[ -f \$CONFIGFILE ] || exit 0
checkpid() {
[ -f \$PIDFILE ] || return 1
pid=\`cat \$PIDFILE\`
[ -d /proc/\$pid ] && return 0
return 1
}
case "\${1}" in
start)
echo -n "Starting \${DESC}: "
start-stop-daemon --start --quiet --pidfile \$PIDFILE \
--chuid \$USER --background --make-pidfile \
--exec \$PYTHON_BIN -- \$DAEMON \$DAEMON_OPTS
echo "\${NAME}."
;;
stop)
echo -n "Stopping \${DESC}: "
start-stop-daemon --stop --quiet --pidfile \$PIDFILE \
--oknodo
echo "\${NAME}."
;;
restart|force-reload)
echo -n "Restarting \${DESC}: "
start-stop-daemon --stop --quiet --pidfile \$PIDFILE \
--oknodo
sleep 1
start-stop-daemon --start --quiet --pidfile \$PIDFILE \
--chuid \$USER --background --make-pidfile \
--exec \$PYTHON_BIN -- \$DAEMON \$DAEMON_OPTS
echo "\${NAME}."
;;
*)
N=/etc/init.d/\$NAME
echo "Usage: \$NAME {start|stop|restart|force-reload}" >&2
exit 1
;;
esac
exit 0
EOF

print_info "* Security Init File"
sudo mv ~/$OE_CONFIG "/etc/init.d/$OE_CONFIG"
sudo chmod 755 "/etc/init.d/$OE_CONFIG"
sudo chown root: "/etc/init.d/$OE_CONFIG"

print_info "* Start ODOO on Startup"
sudo update-rc.d "$OE_CONFIG" defaults

#--------------------------------------------------
# Install Nginx if needed
#--------------------------------------------------
if [ "$INSTALL_NGINX" = "True" ]; then
  print_step "Installing and setting up Nginx"
  sudo apt install nginx -y || exit 1
  cat <<EOF > ~/odoo
map \$http_upgrade \$connection_upgrade {
  default upgrade;
  '' close;
}

server {
  listen 80;

  # set proper server name after domain set
  server_name $WEBSITE_NAME;

  # Add Headers for odoo proxy mode
  proxy_set_header X-Forwarded-Host \$host;
  proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto \$scheme;
  proxy_set_header X-Real-IP \$remote_addr;
  add_header X-Frame-Options "SAMEORIGIN";
  add_header X-XSS-Protection "1; mode=block";
  proxy_set_header X-Client-IP \$remote_addr;
  proxy_set_header HTTP_X_FORWARDED_HOST \$remote_addr;

  #   odoo    log files
  access_log  /var/log/nginx/$OE_USER-access.log;
  error_log       /var/log/nginx/$OE_USER-error.log;

  #   increase    proxy   buffer  size
  proxy_buffers   16  64k;
  proxy_buffer_size   128k;

  proxy_read_timeout 900s;
  proxy_connect_timeout 900s;
  proxy_send_timeout 900s;

  #   force   timeouts    if  the backend dies
  proxy_next_upstream error   timeout invalid_header  http_500    http_502
  http_503;

  types {
    text/less less;
    text/scss scss;
  }

  #   enable  data    compression
  gzip    on;
  gzip_min_length 1100;
  gzip_buffers    4   32k;
  gzip_types  text/css text/less text/plain text/xml application/xml application/json application/javascript application/pdf image/jpeg image/png;
  gzip_vary   on;
  client_header_buffer_size 4k;
  large_client_header_buffers 4 64k;
  client_max_body_size 0;

  location / {
    proxy_pass    http://127.0.0.1:$OE_PORT;
    # by default, do not forward anything
    proxy_redirect off;
  }

  location /websocket {
    proxy_pass http://127.0.0.1:$LONGPOLLING_PORT;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Real-IP \$remote_addr;
  }

  location ~* \.(js|css|png|jpg|jpeg|gif|ico)$ {
    expires 2d;
    proxy_pass http://127.0.0.1:$OE_PORT;
    add_header Cache-Control "public, no-transform";
  }

  # cache some static data in memory for 60mins.
  location ~ /[a-zA-Z0-9_-]*/static/ {
    proxy_cache_valid 200 302 60m;
    proxy_cache_valid 404      1m;
    proxy_buffering    on;
    expires 864000;
    proxy_pass    http://127.0.0.1:$OE_PORT;
  }
}
EOF

  sudo mv ~/odoo "/etc/nginx/sites-available/$WEBSITE_NAME"
  sudo ln -sf "/etc/nginx/sites-available/$WEBSITE_NAME" "/etc/nginx/sites-enabled/$WEBSITE_NAME"
  sudo rm -f /etc/nginx/sites-enabled/default
  sudo nginx -t || exit 1
  sudo service nginx reload || exit 1
  print_success "Done! The Nginx server is up and running. Configuration can be found at /etc/nginx/sites-available/$WEBSITE_NAME"
else
  print_warning "Nginx isn't installed due to choice of the user!"
fi

#--------------------------------------------------
# Enable ssl with certbot
#--------------------------------------------------

if [ "$INSTALL_NGINX" = "True" ] && [ "$ENABLE_SSL" = "True" ] && [ "$ADMIN_EMAIL" != "odoo@example.com" ]  && [ "$WEBSITE_NAME" != "_" ]; then
  sudo apt-get update -y
  sudo apt install snapd -y
  sudo snap install core
  sudo snap refresh core
  sudo snap install --classic certbot
  sudo apt-get install python3-certbot-nginx -y
  sudo certbot --nginx -d "$WEBSITE_NAME" --noninteractive --agree-tos --email "$ADMIN_EMAIL" --redirect
  sudo service nginx reload
  print_success "SSL/HTTPS is enabled!"
else
  print_warning "SSL/HTTPS isn't enabled due to choice of the user or because of a misconfiguration!"
  if [ "$ADMIN_EMAIL" = "odoo@example.com" ]; then
    print_error "Certbot does not support registering odoo@example.com. You should use real e-mail address."
  fi
  if [ "$WEBSITE_NAME" = "_" ]; then
    print_error "Website name is set as _. Cannot obtain SSL Certificate for _. You should use real website address."
  fi
fi

print_info "* Starting Odoo Service"
sudo service "$OE_CONFIG" start || exit 1
print_success "-----------------------------------------------------------"
print_success "Done! The Odoo server is up and running. Specifications:"
print_info "Port: $OE_PORT"
print_info "User service: $OE_USER"
print_info "Configuration file location: /etc/${OE_CONFIG}.conf"
print_info "Logfile location: /var/log/${OE_USER}/${OE_CONFIG}.log"
print_info "User PostgreSQL: $OE_USER"
print_info "Code location: $OE_USER"
print_info "Addons folder: $OE_USER/$OE_CONFIG/addons/"
print_info "Password superadmin (database): $OE_SUPERADMIN"
print_info "Start Odoo service: sudo service $OE_CONFIG start"
print_info "Stop Odoo service: sudo service $OE_CONFIG stop"
print_info "Restart Odoo service: sudo service $OE_CONFIG restart"
if [ "$INSTALL_NGINX" = "True" ]; then
  print_info "Nginx configuration file: /etc/nginx/sites-available/$WEBSITE_NAME"
fi
print_success "-----------------------------------------------------------"
