# 一键邮 / OneTap Mail

[English](#english) | 中文

把文件拖进来，一键发送到自己的工作邮箱。

![macOS 界面](macos/docs/main.png)

「一键邮」是原生 macOS 应用：SwiftUI，支持 Apple Silicon，macOS 14+。

应用直接通过你自己邮箱的 SMTP 服务发送，不经过第三方服务器。授权码保存在本机 macOS 系统钥匙串中。

## 下载

- [一键邮 1.7.1 macOS 安装包](releases/一键邮-1.7.1-macOS.dmg)
- [一键邮 1.7.1 源码包](releases/一键邮-1.7.1-源码.zip)

## 功能

- 首次使用填写工作邮箱、发件邮箱、SMTP 授权码
- 主界面左侧临时邮箱 + 默认工作邮箱，可选是否同步发送
- 通讯录：临时邮箱发送成功后自动保存，支持备注名字、最近收件人下拉和搜索
- 完整邮箱：内嵌网页版邮箱，支持外部浏览器打开和下载到系统「下载」文件夹
- 主窗口任意位置（包括顶部、边距和底部栏）都可拖入文件
- 主窗口可自由缩放（最小 820×640），内容随窗口自适应
- 拖拽或选择多个文件
- 正文编辑，支持一键粘贴剪贴板文字，随文件一起发送
- 自动压缩规则：
  - 只有 1 个文件且小于 50 MB：不压缩，直接作为普通附件发送
  - 2 个及以上文件，或文件达到/超过 50 MB：自动压缩
  - 压缩后多个 ZIP 总大小不超过 50 MB：合并到同一封邮件
  - 压缩后仍超过 50 MB：分成多封邮件发送
- 所有邮件主题自动加 **【一键邮】**
- 邮件发送成功后弹出系统通知
- QQ / 163 / 126 / Gmail / Outlook / iCloud / 阿里云 / 新浪 / 企业邮箱预设
- macOS OpenSSL / curl 备用发信通道，兼容 QQ 邮箱
- macOS 支持 Finder 原生服务
- 「关于」中显示：作者：阿坝分行 何帅；无版权，免费使用

## 仓库结构

```text
OneTap-Mail/
├── macos/                 macOS SwiftUI 源码
│   ├── Sources/           Swift 源码
│   ├── Resources/         Info.plist、图标
│   ├── scripts/           构建、安装、图标脚本
│   ├── tests/             本地 SMTP 测试
│   ├── docs/              界面截图
│   └── README.md          macOS 详细说明
├── releases/              1.7.1 安装包和源码包
├── LICENSE                Unlicense（公共领域）
└── README.md
```

## 构建 macOS 版

要求：macOS 14+、Xcode Command Line Tools。

```bash
cd macos
./scripts/build.sh
open "build/一键邮.app"
```

安装到用户应用程序目录：

```bash
./scripts/install.sh
```

## 测试

```bash
cd macos
mkdir -p .build/test .build/modulecache
swiftc -disable-sandbox -swift-version 5 -parse-as-library \
  -module-cache-path "$PWD/.build/modulecache" \
  -target "$(uname -m)-apple-macos14.0" \
  Sources/Models.swift Sources/MIMEBuilder.swift Sources/MailSender.swift \
  Sources/OpenSSLSender.swift tests/SendHarness.swift -o .build/SendHarness
python3 tests/mock_smtp.py .build/test/message.eml &
.build/SendHarness "某个文件.txt"
```

## 安全与隐私

- 邮箱授权码不会写入仓库，也不会上传到任何服务器。
- macOS 使用系统钥匙串保存授权码。
- 邮件通过你自己的 SMTP 服务直接发出。
- 仓库不包含任何个人邮箱、授权码、钥匙串或本地配置。

## 许可证

本项目采用 **The Unlicense**，即放弃版权、进入公共领域，可自由使用、修改、分发。详见 [LICENSE](LICENSE)。

作者：阿坝分行 何帅

---

## English

**OneTap Mail** is an open-source native macOS app that sends files to your work email in one click.

Drag files into the window, choose the recipients, add an optional message, and send them directly through your own SMTP account. No third-party mail service is involved.

### Download

- [OneTap Mail 1.7.1 for macOS](releases/一键邮-1.7.1-macOS.dmg)
- [OneTap Mail 1.7.1 source archive](releases/一键邮-1.7.1-源码.zip)

### Features

- Native SwiftUI interface for macOS 14+ (Apple Silicon and Intel)
- Temporary recipient plus default work mailbox, with an optional "send to both" toggle
- Contact book: temporary addresses are saved after a successful send, with names, recent-address suggestions and search
- Built-in full-webmail mode with external-link handling and downloads saved to the macOS Downloads folder
- Drag files anywhere in the main window
- Freely resizable window with responsive layout
- Automatic ZIP compression, merging and splitting based on the attachment size limit
- Every subject is prefixed with **【一键邮】**
- Success notifications
- Presets for QQ, 163, 126, Gmail, Outlook, iCloud, Aliyun, Sina and custom SMTP servers
- QQ Mail authorization codes are supported
- Credentials are stored in the macOS Keychain

### Build

Requirements: macOS 14+, Xcode Command Line Tools.

```bash
cd macos
./scripts/build.sh
open "build/一键邮.app"
```

Install into the user Applications folder:

```bash
./scripts/install.sh
```

### Privacy

- No email address, authorization code or local configuration is committed to this repository.
- Emails are sent directly through your SMTP provider.
- The repository contains no keychain data or personal contacts.

### License

**The Unlicense** — public domain. Free to use, modify and redistribute. See [LICENSE](LICENSE).

Author: 阿坝分行 何帅
