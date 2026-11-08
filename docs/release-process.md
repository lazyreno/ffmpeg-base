# FFmpeg SDK v2 构建与候选交付

`.github/workflows/build-desktop.yml` 的手动入口默认运行 `preflight`。四个原生 runner 使用锁定的 FFmpeg 8.1.2 源码、vcpkg 基线和同一 v2 Profile。预检先核对 runner、工具链、磁盘和依赖图，再安装依赖并运行平台构建脚本的 `SDK_CONFIGURE_ONLY=1`；任一平台失败，完整 FFmpeg 编译不会启动。

手动选择 `candidate` 时，该次运行仍先完成四平台预检。正式构建依赖预检成功及二进制依赖缓存，随后在每个平台编译、暂存、生成 `components.json` 与 `manifest.json`，并检查注册组件、动态依赖、版权、最低系统版本、媒体命令和本地 HTTPS 输入。Windows ARM64 必须在原生 ARM64 runner 执行运行时验证。构建脚本将已验证的 SDK 目录打成 tar 传给候选打包 job；该 job 生成四个平台 ZIP、SHA256 与 `artifact-index.json`，作为限期保存的 workflow artifact。构建 workflow 不创建公开 GitHub Release。

候选产物需从同一次成功运行下载，在 macOS 11 两架构、Windows 7 SP1 x86_64、Windows 10 ARM64 上分别实测 `ffmpeg`、`ffprobe` 和代表性解码、编码命令。还要记录目标设备硬件处理结果；组件注册不等于实机硬件可用。缺少目标系统实测时，候选产物只能用于工程验证，不能据此确认最低系统版本承诺。

公开发布由独立的手动流程消费已通过验收的同一批候选 ZIP，不重新运行 vcpkg、Configure 或 make。发布前核对候选 run、提交、版本、四平台文件与 SHA256，以及最低系统实测记录。发布失败可修复发布流程并复用仍在保留期内的候选资产；构建输入改变或候选资产失效则重新构建和实测。
