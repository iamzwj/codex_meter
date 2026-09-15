# Codex Meter

macOS 菜单栏工具，显示 Codex 剩余用量：`5小时剩余%(周剩余%)`，例如 `16%(37%)`。每分钟自动刷新。

## 要求

- macOS 12+
- 已安装并登录 Codex Desktop（使用本机 Codex App Server 读取用量）

## 构建

```zsh
mkdir -p build/CodexMeter.app/Contents/MacOS
clang -fobjc-arc -fmodules -framework AppKit -o build/CodexMeter.app/Contents/MacOS/CodexMeter CodexMeter.m
cp Info.plist build/CodexMeter.app/Contents/Info.plist
codesign --force --deep --sign - build/CodexMeter.app
open build/CodexMeter.app
```

## 登录启动

将 `com.codex.meter.plist` 中的 `INSTALL_PATH` 替换为本仓库的绝对路径，复制到 `~/Library/LaunchAgents/` 后加载：

```zsh
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.codex.meter.plist
```

工具不会保存或上传登录令牌；它只调用本机已登录 Codex 的用量接口。
