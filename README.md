在`Linux`上运行`mosdns`所需的配置文件及所有数据文件。

**信息：**
+ 路径：`/etc/mosdns/`
+ 配置文件结构参考`luci-app-mosdns`
+ `GEOIP`、`GEOSITE`相关数据文件每日从上游拉取，自动更新，详见`Actions`
+ 默认无缓存、无去广告、apple相关域名解析走alidns、防泄漏
+ 项目不包括`mosdns`程序本身
