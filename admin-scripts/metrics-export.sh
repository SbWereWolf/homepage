#!/bin/bash

# Делаем конвертер логов в JSON
# chmod +x /root/metrics-export.sh

INPUT="/var/log/server-metrics.log"
OUTPUT="/home/homepage/www/metrics/data.json"

echo "[" > $OUTPUT

tail -100 $INPUT | awk '
{
  split($4,a,"=");
  split($5,b,"=");
  split($6,c,"=");

  printf "{\"time\":\"%s %s %s\",\"load\":%s,\"ram\":%s},\n",
         $1" "$2" "$3,
         a[2],
         substr(b[2],1,length(b[2])-1)
}' >> $OUTPUT

sed -i '$ s/,$//' $OUTPUT
echo "]" >> $OUTPUT
