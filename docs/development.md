# 构建与发布

## 工具

在 Windows x64 上准备：

- Flutter 3.35.4 / Dart 3.9.2。
- Visual Studio 2022“使用 C++ 的桌面开发”，包括 MSVC x64、Windows SDK 和 CMake。
- .NET 9 SDK、Python 3 和 PowerShell 7。
- 生成安装包时使用 Inno Setup 6.7.3。

`pubspec.lock` 已提交，应用依赖按锁定文件还原。首次构建需要联网。

## 编译

```powershell
flutter pub get
./build.ps1 -Flutter (Get-Command flutter).Source -Dotnet (Get-Command dotnet).Source
```

脚本依次执行静态分析、Flutter 测试、核心逻辑检查、JSONL 后端检查、Release 编译和原生桌面自检。演示检查不会读写真实显示器。

输出到 `dist/版本号/win-x64`，并生成便携 ZIP 与源码 ZIP。.NET 后端使用自包含发布；C++ 运行库从已安装的 Visual Studio Redist 目录复制到应用目录。

自动构建可以用以下命令获取固定版本的安装器编译器：

```powershell
$iscc = ./installer/get-inno.ps1
./installer/build-installer.ps1 -Iscc $iscc
```

脚本下载 Inno Setup 6.7.3，校验 SHA-256 后安装到 `installer/.tools`。语言文件来自同一版本的官方源码仓库，保留文件头版权声明。

## 代码结构

| 目录 | 内容 |
| --- | --- |
| `lib` | Material 3 界面、配置编辑、轮询协调、中英文文案、更新检查 |
| `windows/runner` | Windows 窗口、托盘、单实例、启动项和文件对话框 |
| `native/ControlHost` | DDC/CI、Windows HDR、应用检测及配置自动切换，通过 JSONL 与界面通信 |
| `native/CoreTests` | 模拟显示器测试及真实测试进程的生命周期检查 |
| `test` | Flutter 逻辑、交互和布局测试 |
| `installer` | 中英文安装程序及构建脚本 |

## 发布

版本号以 `pubspec.yaml` 为准，`native/ControlHost/ControlHost.csproj` 的版本需同步。构建脚本把版本传给 Dart 与 Windows 文件资源。提交后打 `vX.Y.Z` 标签，GitHub Actions 会构建并在同名 Release 中上传：

- Windows x64 安装程序。
- Windows x64 便携 ZIP。
- 源码 ZIP。
- `SHA256SUMS.txt`。

工作流也可手动触发，此时只上传构建产物，不公开发布。发布任务先创建草稿、上传全部文件，再公开草稿，避免出现半成品下载页。

更改更新检查时，必须保留“远端正式版严格高于本地版本才提示”的规则。构建编号不影响版本顺序，预发布版不用于稳定版更新提示。
