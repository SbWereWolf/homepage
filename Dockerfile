FROM alpine:latest

RUN apk add --no-cache apache2 \
    && mkdir /home/www/

EXPOSE 80
CMD /usr/sbin/httpd -f /etc/apache2/httpd.conf -DFOREGROUND
