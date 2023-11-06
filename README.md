# cc_waf

#### 起因

​			在我现在的项目中每一天都有竞争对手恶意的cc攻击，特别是在业务的高峰期来攻击接口，加上业务开发的能力不是很好，写出来的接口性能特别差(吐槽一下)，一开始只是使用nginx自带的限流，效果确实不错大部分攻击都失去效果了，但是我们的用户反馈他们也限流经常打不开，公司又舍不得花钱，在我的调研中发现市面上的大部分不太能使用，于是自己查了一下，动手仿写了一个窗口限流，如果有小伙伴需要我进行功能升级的可以提pr，我会定期进行总结和开发更新

#### 技术方面

​		  openresty  支持lua的高性能网关自定义性强，基于openresty 做了自建的缓存系统，如果项目倒闭了可以开源出来

​          lua 高性能的脚本语言    防火墙使用了redis的原子操作实现的封禁

​		  redis  存用户访问数据， IP次数

#### 食用方法

安装好openresty 编译安装

系统: centos7.9

```shell
# 安装依赖 
yum install -y gcc make pcre pcre-devel openssl-devel \
gcc-c++ pcre-devel zlib-devel make unzip openssl \
libxslt-devel libxml2 libxml2-devel geoip-devel \
perl-ExtUtils-Embed libuuid-devel GeoIP GeoIP-data \
redhat-rpm-config.noarch pkgconfig readline-devel postgresql-devel

# 下载openresty
wget https://openresty.org/download/openresty-1.19.9.1.tar.gz

# 解压缩
tar -xvf openresty-1.19.9.1.tar.gz
mv openresty-1.19.9.1 openresty

# 编译安装
cd openresty
./configure --prefix=/opt/openresty\
             --with-luajit\
             --without-http_redis2_module \
             --with-http_iconv_module
gmake
gmake install

# 设置环境变量
vim /etc/profile
PATH=$PATH:/opt/openresty/nginx/sbin
source /etc/profile

# 到这里就安装完成
```

 安装redis 我是使用docker启动的

```shell
yum install docker -y
systemctl enable docker
systemctl start docker
docker run -itd --name redis-openresty -p 6379:6379 redis:5
```

#### openresty 脚本配置

				1. 拉取代码以后修改你的location 把脚本添加到location中
				1. 需要了解一下openresty的执行阶段
				1. 一定要记得做好openresty和redis的监控

```shell
location  /xxxx {
        proxy_pass http://xxxxx;
        proxy_set_header Host $proxy_host;
        proxy_set_header  X-Real-IP  $remote_addr;
        proxy_set_header  X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-NginX-Proxy true;
        error_log /var/log/nginx/error.log error;
        set $BUSINESS "lua";
        access_by_lua_file  /opt/lua/scripts/count.lua;  # 引用黑名单API的Lua脚本文件
}
## 这样就可以把你的接口保护起来
```



##### 科普openresty执行阶段

​    OpenResty 处理一个请求

​				

- `init_by_lua` master init 阶段，初始化全局配置或模块

- `init_worker_by_lua` workinit 阶段，初始化进程配置

- ```
  ssl_certificate_by_lua
  ```

   

  ssl 设置阶段

  - `ssl_certificate_by_lua_block/ssl_certificate_by_lua_file` 当要与客户端 SSL（https）连接握手时，通过上述指令运行 Lua 代码

- `set_by_lua` 流程分支处理判断变量初始化

- `rewrite_by_lua` 转发、重定向、缓存等功能(例如我们的缓存就在这里实现的，开发把需要缓存的接口添加进去设置好过期时间，利用redis的原子性，在这里就可以实现对接口响应的缓存)

- `access_by_lua` IP 准入、接口权限等情况集中处理(我们的脚步就是在这里进行判断处理的)

- `content_by_lua` 内容生成 

- `balancer_by_lua` 反向代理选择阶段

- `header_filter_by_lua` 响应头部过滤处理(例如添加头部信息)

- ```
  body_filter_by_lua 
  ```

   

  响应体过滤/修改处理(例如完成应答内容统一成大写)

  - 通过 `ngx.arg[1]` 操作发送的数据，`ngx.arg[2]` bool 类型，标识是否发送完成
  - `body_filter_by_lua` 修改数据后，导致响应体数据长度变化，可以在 `header_filter_by_lua` 中修改 `ngx.header.content_length = nil` 删除长度头

- `log_by_lua` 会话完成后本地异步完成日志记录(日志可以记录在本地，还可以同步到其他机器)





​             

