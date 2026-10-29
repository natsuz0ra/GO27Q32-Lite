# 第三方声明

本项目代码使用 MIT License。以下材料适用各自许可，不因项目的 MIT License 而改变。

## Flutter 与 Dart 依赖

Flutter、Dart、Material Icons、window_manager、screen_retriever、path_provider、ffi、win32 及传递依赖的声明由 Flutter 汇总在发行包的 `data/flutter_assets/NOTICES.Z`。软件“设置 → 开源许可”可查看汇总内容。

依赖的确切版本见 `pubspec.lock`。Flutter：https://github.com/flutter/flutter 。

## HarmonyOS Sans

本软件使用未经修改的 HarmonyOS Sans SC Regular / Medium 字体。

Copyright 2021 Huawei Device Co., Ltd. All Rights Reserved.

字体适用 HarmonyOS Sans Fonts License Agreement，完整原文随字体保存在 `assets/fonts/LICENSE.txt`，并加入应用内许可页。

官方资源：https://developer.huawei.com/consumer/cn/design/resource/ 。许可原文来源：https://github.com/openharmony/utils_system_resources/blob/4d96c1c7158103732b687e9ea47f4454f6df3ea4/LICENSE_Fonts 。

## .NET 与 Visual C++

Windows 发行包包含自包含 .NET 运行时。后端发布目录中的 `LICENSE.txt` 和 `ThirdPartyNotices.txt` 保留原始声明。来源：https://github.com/dotnet/runtime 。

Windows 发行包含 Visual Studio Redist 提供的未经修改的 Visual C++ x64 Runtime DLL，按 Microsoft Software License Terms 分发。说明：https://learn.microsoft.com/en-us/cpp/windows/redistributing-visual-cpp-files 。这些 DLL 不适用本项目的 MIT License。

## 安装程序

安装程序由 Inno Setup 6.7.3 生成。项目中的简体中文安装语言文件来自其官方源码仓库同版本的 `Files/Languages/Unofficial/ChineseSimplified.isl`，保留原始版权与许可说明。Inno Setup 使用自己的许可：https://github.com/jrsoftware/issrc/blob/is-6_7_3/license.txt 。

## 图标与硬件控制

应用图标由图像生成工具生成，采用透明底扁平风格。GO27Q32 的外形参考技嘉公开产品图片，来源及生成记录见 `docs/icon-reference/README.md`；仓库不附带原始产品图片。

硬件控制代码来自本项目的早期实现。没有链接或分发 GCC/OSD Sidekick 的二进制、固件或安装包，也没有包含已撤回的 myKVM 集成代码。技嘉及显示器型号名称归各自权利人所有，本项目与技嘉无隶属关系。
