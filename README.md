在`Linux`上运行`mosdns`所需的配置文件及所有数据文件。

**信息：**
+ 路径：`/etc/mosdns/`
+ 配置文件结构参考`luci-app-mosdns`
+ `GEOIP`、`GEOSITE`相关数据文件每日从上游拉取，自动更新，详见`Actions`
+ 配置文件中默认的`remote_dns`本身解析需要添加`/etc/hosts`，而对外DNS请求需要`魔法`，没有魔法则改成`1.1.1.1`、`https://1.1.1.1/dns-query`
+ 项目不包括`mosdns`程序本身
