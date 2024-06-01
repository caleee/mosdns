FROM irinesistiana/mosdns:latest

RUN apk update && apk add --no-cache curl

RUN apk add --no-cache tzdata && \
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone && \
    apk del tzdata

COPY /etc/mosdns/ /etc/mosdns/
COPY /etc/mosdns/mosdns.sh /etc/periodic/daily/mosdns.sh
RUN chmod +x /etc/periodic/daily/mosdns.sh

WORKDIR /etc/mosdns

CMD ["/usr/bin/mosdns start --dir /etc/mosdns"]
