sudo apt install wget gnupg
# prerequisites для скачивания и проверки MySQL repo package

wget https://repo.mysql.com//mysql-apt-config_0.8.36-1_all.deb
# скачиваем конфиг официального MySQL APT repository

sudo dpkg -i mysql-apt-config_0.8.36-1_all.deb
# добавляем MySQL repository в APT

sudo apt update
# обновляем package lists

sudo apt install mysql-server
# ставим MySQL Server; вместе с ним появляется mysql_secure_installation
