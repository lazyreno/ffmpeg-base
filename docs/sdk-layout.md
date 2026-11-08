# FFmpeg SDK v2 产物结构

每个平台的候选 ZIP 解压后只有一个 SDK 根目录：

```text
ffmpeg-sdk-{ffmpegVersion}-v{sdkVersion}-{platform}/
  bin/                  # ffmpeg、ffprobe、动态运行库
  include/              # FFmpeg 公共头文件
  lib/                  # 动态库或 MSVC 导入库
  cmake/                # FFmpegConfig/Targets/Runtime.cmake
  licenses/             # FFmpeg 与所有已安装 vcpkg port 的真实版权文件
  manifest.json         # 版本、平台、最低系统版本、依赖与构建来源
  components.json       # 暂存产物的组件清单及数量
```

四个目标平台为 `macos-arm64`、`macos-x86_64`、`windows-x86_64`、`windows-arm64`。目标系统下限分别由 `config/platform-matrix.json` 指定。`config/sdk-version.json` 指定单一 `gpl-desktop-media-v2` Profile；`config/ffmpeg-profile.json` 默认保留 FFmpeg 内置输入、处理和输出组件，显式启用 32 项外部能力，并添加平台设备、TLS 与硬件能力。`--disable-autodetect` 防止构建机隐式改变外部依赖。外部依赖由锁定的 vcpkg 基线、`vcpkg.json` 和 `ports/` 管理。

`manifest.json` 记录统一的 `featureProfile`、`externalDependencies`、`componentsFile`、源文件 SHA256、vcpkg 基线、平台、架构和最低系统版本。`components.json` 来自该平台暂存的 FFmpeg 输出；Parser 从同一次 Configure 生成的注册表读取。两份文件分别说明目标配置与实际注册范围。候选归档另附 ZIP SHA256 和 `artifact-index.json`。

macOS 的运行 dylib 放在 `bin/`，供 FFmpeg 工具与桌面程序就近加载；`lib/` 保留供 CMake 导入目标使用的库。暂存程序递归处理运行依赖，改写为 `@loader_path` 后签名。Windows 的 FFmpeg DLL、vcpkg 运行 DLL 与两个工具放在 `bin/`，导入库放在 `lib/`。验证器检查所有非系统动态依赖均可在 SDK 中解析，并拒绝构建机绝对路径与缺失的版权文本。

SDK 只交付运行和开发集成所需内容；构建源码、下载缓存、示例、FATE 数据和构建文档不进入候选 ZIP。正式桌面客户端通过 `cmake/` 消费固定 SDK，不能从 Homebrew、系统 PATH 或开发机 FFmpeg 替代。
