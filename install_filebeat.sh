curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-9.3.0-amd64.deb
# скачиваем пакет Filebeat

sudo dpkg -i filebeat-9.3.0-amd64.deb
# устанавливаем Filebeat

filebeat version
# проверяем, что установился
