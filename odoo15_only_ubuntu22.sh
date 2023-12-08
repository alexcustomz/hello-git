#!/bin/bash
# Copyright 2022 odooerpcloud.com
# AVISO IMPORTANTE!!! (WARNING!!!)
# ASEGURESE DE TENER UN SERVIDOR / VPS CON AL MENOS > 2GB DE RAM
# You must to have at least > 2GB of RAM
# Ubuntu 18.04, 20.04 LTS, Ubuntu 22.04 LTS, Debian 10, Debian 11
# v3.3
# Last updated: 2022-09-17

OS_NAME=$(lsb_release -cs)
usuario=$USER
DIR_PATH=$(pwd)
VCODE=15
VERSION=15.0
PORT=1569
DEPTH=1
SERVICE_NAME=odoo_dev
PROJECT_NAME=odoo15
PATHBASE=/opt/$PROJECT_NAME
PATH_LOG=$PATHBASE/log
PATHREPOS=$PATHBASE/extra-addons
PATHREPOS_OCA=$PATHREPOS/oca

wk64=""
wk32=""


if [[ $OS_NAME == "jammy" ]];

then
	wk64="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb"

fi



if [[ $OS_NAME == "buster"  ||  $OS_NAME == "bionic" || $OS_NAME == "focal" ]];

then
	wk64="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6-1/wkhtmltox_0.12.6-1."$OS_NAME"_amd64.deb"
	wk32="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6-1/wkhtmltox_0.12.6-1."$OS_NAME"_i386.deb"

fi


if [[ $OS_NAME == "bullseye" ]];

then
	wk64="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2."$OS_NAME"_amd64.deb"
	wk32="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2."$OS_NAME"_i386.deb"
fi


echo $wk64

sudo adduser --system --quiet --shell=/bin/bash --home=$PATHBASE --gecos 'ODOO' --group $usuario
sudo adduser $usuario sudo

# add universe repository & update (Fix error download libraries)
sudo add-apt-repository universe
sudo apt-get update
sudo apt-get upgrade
sudo apt-get install -y git
# Update and install Postgresql
sudo apt-get install postgresql -y
sudo  -u postgres  createuser -s $usuario

sudo mkdir $PATHBASE
sudo mkdir $PATHREPOS
sudo mkdir $PATHREPOS_OCA
sudo mkdir $PATH_LOG
cd $PATHBASE
# Download Odoo from git source
sudo git clone https://github.com/odoo/odoo.git -b $VERSION --depth $DEPTH $PATHBASE/odoo
sudo git clone https://github.com/oca/web.git -b $VERSION --depth $DEPTH $PATHREPOS_OCA/web
# sudo git clone https://github.com/odooerpdevelopers/backend_theme.git -b 14.0 --depth $DEPTH $PATHREPOS


# Install python3 and dependencies for Odoo
sudo apt-get -y install gcc python3-dev libxml2-dev libxslt1-dev \
 libevent-dev libsasl2-dev libldap2-dev libpq-dev \
 libpng-dev libjpeg-dev xfonts-base xfonts-75dpi

sudo apt-get -y install python3 python3-pip python3-setuptools htop zip unzip python3-lxml
sudo pip3 install virtualenv

# FIX wkhtml* dependencie Ubuntu Server 18.04
sudo apt-get -y install libxrender1

# Install nodejs and less
sudo apt-get install -y npm node-less
sudo ln -s /usr/bin/nodejs /usr/bin/node
sudo npm install -g less

# Download & install WKHTMLTOPDF
sudo rm $PATHBASE/wkhtmltox*.deb

if [[ "`getconf LONG_BIT`" == "32" ]];

then
	sudo wget $wk32
else
	sudo wget $wk64
fi

sudo dpkg -i --force-depends wkhtmltox_0.12.6*.deb
sudo apt-get -f -y install
sudo ln -s /usr/local/bin/wkhtml* /usr/bin
sudo rm $PATHBASE/wkhtmltox*.deb
sudo apt-get -f -y install

# install python requirements file (Odoo)
sudo rm -rf $PATHBASE/venv
sudo mkdir $PATHBASE/venv
sudo chown -R $usuario: $PATHBASE/venv
virtualenv -q -p python3 $PATHBASE/venv
# estas lineas se eliminan del fichero por defecto para instalar las declaradas arriba por apt-get en su lugar
sed -i '/libsass/d' $PATHBASE/odoo/requirements.txt
sed -i '/lxml/d' $PATHBASE/odoo/requirements.txt
$PATHBASE/venv/bin/pip3 install --upgrade pip
$PATHBASE/venv/bin/pip3 install libsass
$PATHBASE/venv/bin/pip3 install -r $PATHBASE/odoo/requirements.txt
#$PATHBASE/venv/bin/pip3 install pyopenssl --upgrade

cd $DIR_PATH

sudo mkdir $PATHBASE/config
sudo rm $PATHBASE/config/odoo$VCODE.conf
sudo touch $PATHBASE/config/odoo$VCODE.conf
echo "
[options]
; This is the password that allows database operations:
;admin_passwd =
db_host = False
db_port = False
;db_user =

;db_password =
data_dir = $PATHBASE/data
logfile= $PATH_LOG/odoo$VCODE-server.log

xmlrpc_port = $PORT
;dbfilter = odoo$VCODE
logrotate = True
limit_time_real = 6000
limit_time_cpu = 6000

############# addons path ######################################

addons_path =
    $PATHREPOS,
    $PATHREPOS_OCA/web,
    $PATHBASE/odoo/addons

#################################################################
" | sudo tee --append $PATHBASE/config/odoo$VCODE.conf

sudo rm /etc/systemd/system/$SERVICE_NAME.service
sudo touch /etc/systemd/system/$SERVICE_NAME.service
sudo chmod +x /etc/systemd/system/$SERVICE_NAME.service
echo "
[Unit]
Description=Odoo$VCODE-$SERVICE_NAME
After=postgresql.service

[Service]
Restart=on-failure
RestartSec=5s
Type=simple
User=$usuario
ExecStart=$PATHBASE/venv/bin/python $PATHBASE/odoo/odoo-bin --config $PATHBASE/config/odoo$VCODE.conf

[Install]
WantedBy=multi-user.target
" | sudo tee --append /etc/systemd/system/$SERVICE_NAME.service
sudo systemctl daemon-reload
sudo systemctl enable $SERVICE_NAME.service
sudo systemctl start $SERVICE_NAME.service

sudo chown -R $usuario: $PATHBASE

## Add cron backup project folder (Todos lunes 4:30am)
sudo -u root bash << eof
cd /root
echo "Agregando crontab para backup carpeta instalacion Odoo..."

sudo crontab -l | sed -e '/zip/d; /$PROJECT_NAME/d' > temporal

echo "
30 4 * * 1 zip -r /opt/$PROJECT_NAME.zip $PATHBASE" >> temporal
crontab temporal
rm temporal
eof


echo "Odoo $VERSION Installation has finished!! ;) by odooerpcloud.com"
IP=$(ip route get 8.8.8.8 | head -1 | cut -d' ' -f7)
echo "You can access from: http://$IP:$PORT  or http://localhost:$PORT"
