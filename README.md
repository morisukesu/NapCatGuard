# NapCatGuard - NapCat 掉线守护任务

自动检测 NapCat/QQ 是否在线，掉线时自动通过快速登录重启。

## 功能

- 每 5 分钟体检一次 NapCat 状态
- 检测 `NapCatWinBootMain.exe` 进程是否存活
- 检测 6199 端口是否有 ESTABLISHED 连接
- 掉线后自动通过 `run-napcat.cmd` 快速登录重启（无需扫码）
- 等待 QR 扫码时提供 20 分钟宽限期
- 两次重启之间 5 分钟冷却期
- 运行时不弹窗

## 文件

- `napcat-guard.ps1` - 主守护脚本
- `install-napcat-guard.ps1` - Windows 计划任务安装脚本

## 使用方法

1. 以管理员身份运行 PowerShell
2. 执行 `.\install-napcat-guard.ps1` 注册计划任务
3. 登录后自动运行，之后每 5 分钟体检一次

## 健康规则

- healthy = `NapCatWinBootMain.exe` 存活 AND 6199 端口有 ESTABLISHED 连接
- 不检查 QQ 命令行中的 `-q <uin>`（因为 NapCat 启动的 QQ 只带 `--enable-logging`）
- 如果 NapCat 活着但未连接，等待 20 分钟供扫码
