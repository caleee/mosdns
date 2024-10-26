## 简介

在`Linux`上运行`mosdns`所需的配置文件及所有数据文件。

## 说明

+ 路径：`/etc/mosdns/`
+ 配置文件结构参考`luci-app-mosdns`
+ `GEOIP`、`GEOSITE`相关数据文件每日从上游拉取，自动更新，详见`Actions`
+ 更新脚本配合linux计划任务实现配置更新：`/sh/update.sh`
  + 脚本放到 `/etc/mosdns/` 目录下
  + 添加crontab `0 3 * * * /etc/mosdns/update.sh >>/var/log/consumer-mosdns-script.log 2>&1`
  + 相关 [Issue #2](https://github.com/caleee/mosdns/issues/2)
+ 项目不包括`mosdns`程序本身

## 配置

### 默认配置：`etc/mosdns/config.yaml`

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

### 默认配置+缓存配置：`etc/mosdns/config_cache.yaml`

+ DNS 缓存大小：55462条
+ 乐观缓存 TTL：
  + 开启
  + 无访问的过期时间：21600秒 (要禁用乐观缓存，则此项设置为 0)
+ 自动保存缓存(避免cache因为系统或进程复位丢失，保存路径：/etc/mosdns/cache.dump)
  + 开启
  + 自动保存缓存间隔：3600秒
+ 覆盖 TTL 值：600-86400(秒)

---
