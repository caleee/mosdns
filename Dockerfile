FROM irinesistiana/mosdns:latest

RUN apk update && \
    apk add --no-cache tzdata && \
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone && \
    apk del tzdata

COPY ./etc/mosdns/ /etc/mosdns/

RUN chmod +x /etc/mosdns/mosdns.sh

CMD ["/usr/bin/mosdns start --dir /etc/mosdns"]
