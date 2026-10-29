# GO27Q32 Lite

[简体中文](README.md) | [English](README.en.md)

为技嘉 GO27Q32 显示器提供的 Windows 控制工具。可以调节画面参数、管理 SDR/HDR 配置，也可以在应用启动和退出时自动切换配置。

[下载 Windows 安装程序](https://github.com/natsuz0ra/GO27Q32-Lite/releases/latest) · [使用说明](docs/usage.md) · [构建说明](docs/development.md)

![显示器控制界面](docs/images/display.png)

## 安装

1. 在 [Releases](https://github.com/natsuz0ra/GO27Q32-Lite/releases/latest) 下载 `GO27Q32Lite-版本号-windows-x64-setup.exe`。
2. 运行安装程序，选择“简体中文”或“English”。默认安装到当前用户目录，无需管理员权限。
3. 保持显示器唤醒，并在 Windows 中启用该显示器。显示器需要允许 DDC/CI 控制。

支持 Windows 10/11 x64。安装包内含 .NET 运行时和 Visual C++ 运行库。首次打开时，中文系统默认使用中文，其余系统使用英文；之后按软件中保存的语言设置显示。

也可以下载 `windows-x64.zip`，解压后运行 `go27q32_lite.exe`。请保留同目录 DLL、`data` 和 `backend` 文件夹。

## 功能

| 功能 | 支持范围 |
| --- | --- |
| 画面调节 | 亮度、对比度、SDR 画面模式、Gamma、色温、锐度、黑平衡、色彩鲜艳度、低蓝光、超级分辨率和过驱 |
| 游戏辅助 | 准星、刷新率显示、FreeSync、正计时/倒计时、暂停/继续和六档辅助显示位置 |
| Windows HDR | 切换当前 GO27Q32 的系统 HDR，分别显示开关请求与实际输出 |
| 配置库 | 保存 SDR/HDR 两组参数，设置 HDR 保持/开启/关闭策略，导入和导出配置 |
| 应用规则 | 按完整 EXE 路径匹配；支持优先级，应用退出后恢复桌面配置 |
| 设备设置 | 输入源、音量、OSD 时间/透明度、指示灯和四向摇杆快捷功能 |
| 后台运行 | 托盘快捷菜单、开机自启、启动时最小化和关闭后驻留 |
| 外部同步 | 读取机身 OSD 和 Windows HDR 的改动，更新软件中的状态 |
| 界面 | 中英文、浅色/深色/跟随系统主题 |
| 更新检查 | 手动检查 GitHub 正式版；只有远端版本更高时提示更新 |

滑杆先在界面显示目标值，结束拖动后写入显示器，再读取确认。临时调整不会覆盖已保存的配置。

托盘图标单击打开快捷菜单，双击打开主窗口。为区分两种操作，单击会等待系统双击判定时间。右键菜单提供打开、暂停自动切换和退出操作。

## 界面预览

以下截图使用演示数据。软件同时提供浅色和深色主题。

| HDR 状态 | 配置库 |
| --- | --- |
| ![HDR 状态](docs/images/hdr.png) | ![配置库](docs/images/profiles.png) |

![托盘快捷菜单](docs/images/tray.png)

## 兼容性

仅对设备标识为 `GBT2761` 或 `GBT275C` 的 GO27Q32 开放写入。当前版本交付 Windows x64；尚无 macOS 版本，也不包含跨设备键鼠共享功能。

Windows HDR 开关支持 Windows 10 1709～22H2，以及 Windows 11 build 26100 或更高版本。早期 Windows 11 保留禁用保护。系统支持 HDR，也不表示所有画面参数在 HDR 下都可调；以显示器实际返回值为准。

HDR显示、HDR游戏、HDR电影、HDR亮彩和 HDRPeak 1300 仍需通过显示器机身菜单选择。现有协议证据不足以区分或写入这些 HDR 专用预设，软件没有提供猜测编号的控制入口。

请避免同时让 GCC、OSD Sidekick 或其他控制工具自动改写同一台显示器。软件没有数字签名，Windows 可能显示“未知发布者”。

## 配置与更新

设置保存在 `%LOCALAPPDATA%\GO27Q32Lite\settings.json`，保存时生成 `.bak`。首次升级时，若新目录中没有配置，会从旧版 `GO27Q32LiteFlutter` 目录复制并验证配置，原文件保留；已有的新目录配置不会被覆盖。卸载默认保留用户配置。更换电脑前，可在“设置 → 数据与配置”中导出。

“设置 → 检查更新”只访问本项目的 GitHub Release API，不上传显示器信息、配置或进程列表。不会自动下载或安装。版本比较遵循语义化版本规则，忽略构建编号；相同或较低版本不会提示更新。

## 从源码构建

需要 Flutter 3.35.4（Dart 3.9.2）、Visual Studio 2022 的“使用 C++ 的桌面开发”、.NET 9 SDK、Python 3 和 PowerShell 7。

```powershell
flutter pub get
./build.ps1 -Flutter (Get-Command flutter).Source -Dotnet (Get-Command dotnet).Source
```

生成安装程序需要 Inno Setup 6：

```powershell
./installer/build-installer.ps1 -Iscc 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe'
```

构建脚本会运行 Flutter 静态分析、界面测试、后端逻辑检查和原生窗口自检。测试使用模拟设备，不修改真实显示器。完整流程见[构建说明](docs/development.md)。

## 许可与来源

项目代码使用 [MIT License](LICENSE)。字体使用 HarmonyOS Sans，授权原文位于 [assets/fonts/LICENSE.txt](assets/fonts/LICENSE.txt)。其他依赖与运行库按各自许可分发，见[第三方声明](THIRD_PARTY_NOTICES.md)。

这是独立开发的工具，与技嘉无隶属关系。项目没有分发 GCC/OSD Sidekick 的程序、固件或原厂安装包。
