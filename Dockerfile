FROM irinesistiana/mosdns:latest

RUN apk update && apk add --no-cache curl

RUN apk update && \
    apk add --no-cache tzdata && \
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone && \
    apk del tzdata

COPY ./etc/mosdns/ /etc/mosdns/

COPY ./sh/mosdns-rule-update_for_docker.sh /etc/periodic/daily/

RUN chmod +x /etc/periodic/daily/mosdns-rule-update_for_docker.sh

CMD ["/usr/bin/mosdns", "start", "--dir", "/etc/mosdns"]
