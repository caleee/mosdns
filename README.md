Linux上快速部署使用[mosdns](https://github.com/IrineSistiana/mosdns)，每日打包更新分流数据。

## 项目核心内容

- [脚本](https://github.com/caleee/mosdns/blob/main/usr/local/bin/mosdns.sh) 功能包括: 
  - 自动化全新安装 [IrineSistiana](https://github.com/IrineSistiana)大神的[mosdns](https://github.com/IrineSistiana/mosdns)，安装后无需其他配置即可满足基础使用需求
    - 理论适用于 amd64/arm64 架构下的 'Ubuntu', 'Debian', 'RedHat', 'CentOS', 'Fedora', 'Alpine' 等使用 'apt', 'yum', 'apk'包管理器的Linux发行版，amd64架构下'Ubuntu 24.04''CentOS 9 stream''Alpine 3.21'已不充分测试、可用
    - 默认端口: 5353
  - 升级[mosdns](https://github.com/IrineSistiana/mosdns/releases)程序
  - 升级规则数据[Releases](https://github.com/caleee/mosdns/releases)
  - 卸载程序及所有数据(配置文件、规则数据、日志、备份)
  - 服务相关基础功能(start|stop|restart|status)

- [配置文件](https://github.com/caleee/mosdns/blob/main/etc/mosdns/config.yaml)是一个即用的配置，常用功能和规则已设置，详见下方 [配置说明](### 配置说明)

- **[Releases](https://github.com/caleee/mosdns/releases)** `mosdns-rule.tar.gz`包含配置文件所需的规则文件**[tree](https://github.com/caleee/mosdns/tree/main/etc/mosdns/rule)**，其中的`GEOIP`(IP分流数据)、`GEOSITE`(域名数据)，每日从上游拉取，每日自动更新，详见`Actions`。
- [GitHub Actions](https://github.com/caleee/mosdns/tree/main/.github/workflows) 构建docker镜像等功能 [镜像地址](https://hub.docker.com/r/caleee/mosdns)

### 快速开始

!  以下命令都需要 root 用户或 sudo 执行

```bash
curl -sSL https://raw.githubusercontent.com/caleee/mosdns/refs/heads/main/usr/local/bin/mosdns.sh -O && sh mosdns.sh
```

国内可选:

```bash
curl -sSL https://testingcf.jsdelivr.net/gh/caleee/mosdns@main/usr/local/bin/mosdns.sh -O && sh mosdns.sh
```

### 升级 [mosdns](https://github.com/IrineSistiana/mosdns/releases) 主程序

- 与`快速开始`命令相同，脚本会自行判断是否需要升级

### 升级规则数据

```bash
curl -sSL https://raw.githubusercontent.com/caleee/mosdns/refs/heads/main/usr/local/bin/mosdns.sh -O && sh mosdns.sh update-rules
```

国内可选:

```bash
curl -sSL https://testingcf.jsdelivr.net/gh/caleee/mosdns@main/usr/local/bin/mosdns.sh -O && sh mosdns.sh update-rules
```

#### 设置数据更新计划任务(可选)

```bash
curl -sSL https://raw.githubusercontent.com/caleee/mosdns/refs/heads/main/usr/local/bin/mosdns.sh -o /usr/local/bin/mosdns.sh && chmod +x /usr/local/bin/mosdns.sh
```

国内可选:

```bash
curl -sSL https://testingcf.jsdelivr.net/gh/caleee/mosdns@main/usr/local/bin/mosdns.sh -o /usr/local/bin/mosdns.sh && chmod +x /usr/local/bin/mosdns.sh
```

##### 设置Linux计划任务

```bash
# 编辑计划任务
crontab -e

# 文件下方添加以下内容后保存退出 (每天系统时区3:00执行规则数据更新)
0 3 * * * /bin/sh /usr/local/bin/mosdns.sh update-rules
```

一键设置计划任务(慎用)
```bash
echo "$(crontab -l ; echo -e "\n# mosdns rules update\n0 3 * * * /bin/sh /usr/local/mosdns.sh update-rules")" | crontab - &
& crontab -l
```

### 卸载

```bash
curl -sSL https://raw.githubusercontent.com/caleee/mosdns/refs/heads/main/usr/local/bin/mosdns.sh -O && sh mosdns.sh uninstall
```

国内可选:

```bash
curl -sSL https://testingcf.jsdelivr.net/gh/caleee/mosdns@main/usr/local/bin/mosdns.sh -O && sh mosdns.sh uninstall
```

### Docker

build - [Dockerfile](https://github.com/caleee/mosdns/blob/main/Dockerfile)

```bash
docker pull caleee/mosdns:latest
```

这里给出使用示例，仅供参考，不保证可用，请自行研究

docker command

```bash
docker run -d \
  --name mosdns \
  --restart always \
  -p 5353:53/udp \
  -p 5353:53/tcp \
  -v /etc/mosdns:/etc/mosdns \
  caleee/mosdns:latest
```

docker-compose.yml

```yaml
services:
  mosdns:
    container_name: mosdns
    image: caleee/mosdns:latest
    restart: always
    ports:
    - "5353:53/udp"
    - "5353:53/tcp"
    volumes:
    - /etc/mosdns:/etc/mosdns
version: '3.8'
```

k8s/k3s (修改ip端口等)

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: dns
---
apiVersion: v1
kind: Service
metadata:
  namespace: dns
  name: mosdns
spec:
  type: NodePort
  clusterIP: 10.43.43.43
  ports:
  - name: dns-tcp
    protocol: TCP
    port: 53
    targetPort: 53
    nodePort: 30054
  - name: dns-udp
    protocol: UDP
    port: 53
    targetPort: 53
    nodePort: 30054
  - name: api
    protocol: TCP
    port: 9091
    targetPort: 9091
    nodePort: 30091
  selector:
    app: mosdns
---
apiVersion: apps/v1
kind: Deployment
metadata:
  namespace: dns
  name: mosdns
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mosdns
  strategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        app: mosdns
    spec:
      containers:
        - image: caleee/mosdns:latest
          name: mosdns
          ports:
            - containerPort: 53
              name: dns-tcp
              protocol: TCP
            - containerPort: 53
              name: dns-udp
              protocol: UDP
            - containerPort: 9091
              name: api
              protocol: TCP
          volumeMounts:
            - mountPath: /etc/mosdns
              name: mosdns-dir
      restartPolicy: Always
      volumes:
        - name: mosdns-dir
          hostPath:
            path: /opt/mosdns
            type: DirectoryOrCreate
```

---

### 配置说明

#### 默认配置：`etc/mosdns/config.yaml`

+ API：关闭
+ 缓存相关功能：关闭
+ 去广告功能：关闭
+ Cloudflare 自选 IP：关闭
+ 日志：开启(info)
+ apple相关域名国内解析(alidns)
+ 防泄漏(fallback: 远程DNS服务器)
+ 启用 EDNS 客户端子网
+ TCP/DoT 连接复用
+ DNS 服务器并发请求数：2

#### 默认配置+缓存配置：`etc/mosdns/config_cache.yaml`

+ DNS 缓存大小：55462条
+ 乐观缓存 TTL：
  + 开启
  + 无访问的过期时间：21600秒 (要禁用乐观缓存，则此项设置为 0)
+ 自动保存缓存(避免cache因为系统或进程复位丢失，保存路径：/etc/mosdns/cache.dump)
  + 开启
  + 自动保存缓存间隔：3600秒
+ 覆盖 TTL 值：600-86400(秒)

---

## 感谢

@[IrineSistiana/mosdns](https://github.com/IrineSistiana/mosdns)

@[sbwml/luci-app-mosdns](https://github.com/sbwml/luci-app-mosdns)

@[urlesistiana/v2dat](https://github.com/urlesistiana/v2dat)

@[Loyalsoldier/geoip](https://github.com/Loyalsoldier/geoip)

@[Loyalsoldier/v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat)

---

