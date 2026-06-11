---
name: network-penetration-testing
description: 网络渗透测试，覆盖端口扫描→服务识别→NSE脚本→防火墙规避→隧道→内网探测→常见端口攻击全流程
---

# 网络渗透测试

## 概述

网络渗透测试是评估网络基础设施安全性的核心环节。本技能覆盖从端口扫描到内网探测的完整攻击面识别流程。

## 1. Nmap核心命令

### 1.1 按速度分级

```bash
# === 超快速 (1-2分钟, 仅端口) ===
nmap -sS -p- --min-rate 10000 -T4 <target>
masscan -p1-65535 --rate=10000 <target>
rustscan -a <target> --range 1-65535 --batch-size 5000

# === 快速 (5-10分钟, 端口+服务) ===
nmap -sS -sV -p 21,22,23,25,53,80,110,111,135,139,143,443,445,993,995,1723,3306,3389,5432,5900,6379,8080,8443,9001,27017,50000 -T4 <target>

# === 标准 (20-30分钟, 全面) ===
nmap -sS -sV -sC -p- -T4 -oA nmap_full <target>

# === 深入 (1-2小时, 含脚本) ===
nmap -sS -sV -sC -O -p- -T4 --script=default,safe,vuln -oA nmap_deep <target>
```

### 1.2 参数速查

| 参数 | 含义 | 参数 | 含义 |
|------|------|------|------|
| `-sS` | TCP SYN扫描(需root) | `-sT` | TCP Connect(无需root) |
| `-sU` | UDP扫描 | `-sV` | 服务版本检测 |
| `-sC` | 默认脚本 | `-O` | OS检测 |
| `-p-` | 全部65535端口 | `--top-ports 1000` | Top 1000 |
| `-T4` | 速度模板(0-5) | `--min-rate 1000` | 最小发包速率 |
| `-Pn` | 跳过主机发现 | `-n` | 禁止DNS解析 |
| `-oA name` | 输出所有格式 | `-oN name.nmap` | 文本输出 |

## 2. 防火墙/IDS规避

```bash
# === 分片扫描 ===
nmap -sS -f <target>                          # 8字节碎片
nmap -sS -f --mtu 24 <target>                 # 指定MTU
nmap -sS -ff <target>                         # 16字节碎片

# === 诱饵扫描 ===
nmap -sS -D RND:5 <target>                    # 5个随机诱饵IP
nmap -sS -D 192.168.1.1,10.0.0.1 <target>    # 指定诱饵

# === 源端口欺骗 ===
nmap -sS --source-port 53 <target>            # 伪装DNS流量
nmap -sS -g 80 <target>                       # 伪装HTTP流量

# === 空闲扫描 (Idle Scan) ===
nmap -sI <zombie_ip> <target>                 # 通过僵尸主机扫描

# === 延时扫描 (避免触发IDS) ===
nmap -sS -T2 --scan-delay 5s <target>

# === 随机顺序+假MAC ===
nmap -sS --randomize-hosts --spoof-mac Apple <target>
```

## 3. NSE脚本扫描

```bash
# === 漏洞扫描类 ===
nmap --script=vuln <target>
nmap --script=smb-vuln* <target>                         # SMB漏洞
nmap --script=http-vuln* <target>                        # HTTP漏洞
nmap --script=ssl-* --script=ssl-enum-ciphers <target>   # SSL/TLS

# === 信息收集类 ===
nmap --script=discovery <target>
nmap --script=http-enum,http-headers,http-title <target>
nmap --script=smb-enum-shares,smb-os-discovery <target>

# === 具体漏洞检测 ===
nmap --script=http-shellshock --script-args uri=/cgi-bin/test.cgi <target>
nmap --script=http-vuln-cve2017-5638 <target>             # Struts2
nmap --script=ssl-heartbleed <target>                     # Heartbleed
```

### 常用脚本速查

| 脚本 | 用途 | 脚本 | 用途 |
|------|------|------|------|
| `http-enum` | 目录枚举 | `smb-vuln-ms17-010` | 永恒之蓝 |
| `http-shellshock` | Shellshock | `ftp-anon` | FTP匿名登录 |
| `mysql-empty-password` | MySQL空密码 | `redis-info` | Redis信息泄露 |
| `ssl-heartbleed` | 心脏滴血 | `dns-zone-transfer` | DNS域传送 |

## 4. 存活主机与端口发现

```bash
# === Ping扫描 ===
nmap -sn 192.168.1.0/24
fping -a -g 192.168.1.0/24 2>/dev/null

# === ARP扫描 (内网最快) ===
nmap -sn -PR 192.168.1.0/24
arp-scan --local

# === 无Ping端口扫描 ===
nmap -Pn -p 445 --open 192.168.1.0/24   # 扫MS17-010
```

## 5. 隧道与端口转发

```bash
# === SSH动态转发 (SOCKS5) ===
ssh -D 1080 user@jumphost
proxychains nmap -sT -Pn target

# === SSH本地转发 ===
ssh -L 4450:target:445 user@jumphost

# === chisel (万能隧道) ===
# Server: ./chisel server -p 8000 --reverse
# Client: ./chisel client server:8000 R:socks
```

## 6. 常用端口+攻击方向

| 端口 | 服务 | 优先检查 |
|------|------|---------|
| **21** | FTP | 匿名登录 `ftp anonymous@<target>` |
| **22** | SSH | 弱口令、私钥泄露 |
| **25** | SMTP | 用户枚举 `VRFY` |
| **53** | DNS | 域传送 `dig axfr @<target> domain` |
| **80/443** | HTTP/HTTPS | Web漏洞、目录爆破 |
| **135/139/445** | SMB/RPC | MS17-010、空会话 |
| **1433** | MSSQL | 弱口令 sa |
| **1521** | Oracle | 弱口令 |
| **2049** | NFS | `showmount -e <target>` |
| **3306** | MySQL | 弱口令 root |
| **3389** | RDP | 弱口令、CVE-2019-0708 |
| **5432** | PostgreSQL | 弱口令 postgres |
| **6379** | Redis | 未授权访问 |
| **8080/8443** | Web管理 | Tomcat/Jenkins |
| **11211** | Memcached | 未授权 |
| **27017** | MongoDB | 未授权 |

## 7. 快速扫描策略

```bash
# 第一波: 30秒存活+常用端口
nmap -sn -T5 192.168.1.0/24 -oA quick_ping
nmap -sS -sV -p 21,22,23,25,53,80,135,139,443,445,1433,3306,3389,5432,6379,8080,8443,27017 --open -iL alive_hosts.txt -T4 -oA quick_scan

# 第二波: 深度全端口
nmap -sS -sV -sC -p- -T4 --open -iL alive_hosts.txt -oA deep_scan

# 第三波: 漏洞脚本精准扫描
nmap -sS -sV --script=vuln -p $(从deep_scan提取的端口) -iL alive_hosts.txt -oA vuln_scan

# 提取端口列表
grep -E '^[0-9]+/tcp' scan.nmap | awk -F/ '{print $1}' | tr '\n' , | sed 's/,$//'
```

---

*参考: Nmap官方文档 + 实战经验整理*
