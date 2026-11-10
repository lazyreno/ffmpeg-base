Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RootDir = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $RootDir

$SdkArch = if ($env:SDK_ARCH) { $env:SDK_ARCH } else { "x86_64" }
$NativeArm64Host = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq [System.Runtime.InteropServices.Architecture]::Arm64
if ($SdkArch -eq "arm64" -and !$NativeArm64Host) {
    throw "Windows ARM64 SDK validation requires a native ARM64 runner"
}
switch ($SdkArch) {
    "x86_64" {
        $FfmpegArch = "x86_64"
        $FfmpegCrossCompileFlag = ""
        $FfmpegTargetCflags = "-D_WIN32_WINNT=0x0601 -DWINVER=0x0601 -DNTDDI_VERSION=0x06010000"
        $FfmpegTargetLdflags = "/SUBSYSTEM:CONSOLE,6.01"
        $FfmpegAssemblyFlag = ""
        $VcpkgTriplet = "x64-windows"
    }
    "arm64" {
        $FfmpegArch = "aarch64"
        $FfmpegCrossCompileFlag = ""
        $FfmpegTargetCflags = "--target=arm64-windows"
        $FfmpegTargetLdflags = ""
        $FfmpegAssemblyFlag = "--disable-asm"
        $VcpkgTriplet = "arm64-windows"
    }
    default {
        throw "Unsupported Windows SDK architecture: $SdkArch"
    }
}

$PlatformKey = "windows-$SdkArch"
$PlatformMatrix = Get-Content "config/platform-matrix.json" -Raw | ConvertFrom-Json
$PlatformDeclaration = @($PlatformMatrix.platforms | Where-Object { $_.key -eq $PlatformKey })
if ($PlatformDeclaration.Count -ne 1) {
    throw "config/platform-matrix.json must declare exactly one entry for $PlatformKey"
}
$MinimumSystemVersion = $PlatformDeclaration[0].minimumSystemVersion
if ([string]::IsNullOrWhiteSpace($MinimumSystemVersion)) {
    throw "$PlatformKey must declare non-empty minimumSystemVersion"
}
$BuildRoot = if ($env:BUILD_ROOT) { $env:BUILD_ROOT } else { Join-Path $RootDir "build/$PlatformKey" }

$SdkConfig = Get-Content "config/sdk-version.json" -Raw | ConvertFrom-Json
$SourceLock = Get-Content "config/source-lock.json" -Raw | ConvertFrom-Json
$SdkVersion = $SdkConfig.sdkVersion
$FfmpegVersion = $SdkConfig.ffmpegVersion
$LicenseMode = $SdkConfig.licenseMode
$FeatureProfile = $SdkConfig.featureProfile
$VcpkgBaseline = $SdkConfig.vcpkgBaseline
$ProfileConfig = Get-Content "config/ffmpeg-profile.json" -Raw | ConvertFrom-Json
$ExternalDependenciesJson = ConvertTo-Json -InputObject @($ProfileConfig.externalDependencies) -Compress
if ($ProfileConfig.profile -ne $FeatureProfile) {
    throw "config/ffmpeg-profile.json profile $($ProfileConfig.profile) does not match sdk-version featureProfile $FeatureProfile"
}
if ($ProfileConfig.licenseMode -ne $LicenseMode) {
    throw "config/ffmpeg-profile.json licenseMode $($ProfileConfig.licenseMode) does not match sdk-version licenseMode $LicenseMode"
}
$ProfileConfigureFlags = @($ProfileConfig.configure.common) + @($ProfileConfig.configure.windows)
if ($SdkArch -eq "x86_64") {
    $ProfileConfigureFlags += @($ProfileConfig.configure.windows_x86_64)
}

function ConvertTo-BashSingleQuoted {
    param([Parameter(Mandatory = $true)][string]$Value)
    if ($Value.Contains("'")) {
        throw "FFmpeg profile configure flags must not contain single quotes: $Value"
    }
    return "'$Value'"
}

$FfmpegProfileConfigureArgs = ($ProfileConfigureFlags | ForEach-Object {
    "  $(ConvertTo-BashSingleQuoted $_) \"
}) -join "`n"

$FfmpegTag = $SourceLock.tag
if ($FfmpegTag -ne "n$FfmpegVersion") {
    throw "config/source-lock.json tag $FfmpegTag does not match FFmpeg version $FfmpegVersion"
}
$FfmpegSourceUrl = $SourceLock.url
$FfmpegSourceSha256 = $SourceLock.sha256
$SourceArchive = Join-Path $BuildRoot "downloads/ffmpeg-$FfmpegTag.tar.gz"
$SourceDir = Join-Path $BuildRoot "src/FFmpeg-$FfmpegTag"
$InstallPrefix = Join-Path $BuildRoot "install"
$SdkParentDir = Join-Path $BuildRoot "sdk"
$SdkDirName = "ffmpeg-sdk-$FfmpegVersion-v$SdkVersion-$PlatformKey"
$SdkRoot = Join-Path $SdkParentDir $SdkDirName
$BuildToolsDir = Join-Path $BuildRoot "tools"
$LibAliasDir = Join-Path $BuildRoot "lib-alias"
$VcpkgRoot = if ($env:VCPKG_ROOT) { $env:VCPKG_ROOT } elseif ($env:VCPKG_INSTALLATION_ROOT) { $env:VCPKG_INSTALLATION_ROOT } else { "C:\vcpkg" }
$VcpkgInstalledDir = if ($env:VCPKG_INSTALLED_DIR) { $env:VCPKG_INSTALLED_DIR } else { Join-Path $VcpkgRoot "installed" }
$VcpkgDependencyRoot = Join-Path $VcpkgInstalledDir $VcpkgTriplet

$RequiredVcpkgDependencyHeaders = @(
    "include/lame/lame.h",
    "include/vpx/vpx_encoder.h",
    "include/aom/aom_encoder.h",
    "include/opus/opus.h",
    "include/vorbis/codec.h",
    "include/opencore-amrnb/interf_enc.h",
    "include/opencore-amrwb/dec_if.h",
    "include/x264.h",
    "include/x265.h",
    "include/zlib.h"
)
foreach ($RequiredHeader in $RequiredVcpkgDependencyHeaders) {
    if (!(Test-Path (Join-Path $VcpkgDependencyRoot $RequiredHeader))) {
        throw "$RequiredHeader from $VcpkgTriplet must be installed with vcpkg before building the v2 SDK profile"
    }
}
if (!(Test-Path (Join-Path $VcpkgDependencyRoot "lib"))) {
    throw "vcpkg lib directory for $VcpkgTriplet is required before building the v2 SDK profile"
}
$VpxImportLib = Join-Path $VcpkgDependencyRoot "lib/vpx.lib"
if (!(Test-Path $VpxImportLib)) {
    throw "vpx.lib from $VcpkgTriplet is required for FFmpeg libvpx VP8/VP9 linking"
}
$AmrWbImportLib = Join-Path $VcpkgDependencyRoot "lib/opencore-amrwb.lib"
if (!(Test-Path $AmrWbImportLib)) {
    throw "opencore-amrwb.lib from $VcpkgTriplet is required for FFmpeg AMR-WB decoding"
}
$IconvImportLib = $null
foreach ($LibraryName in @("iconv.lib", "libiconv.lib")) {
    $Candidate = Join-Path $VcpkgDependencyRoot "lib/$LibraryName"
    if (Test-Path $Candidate) {
        $IconvImportLib = $Candidate
        break
    }
}
if (-not $IconvImportLib) {
    throw "iconv.lib or libiconv.lib from $VcpkgTriplet is required for FFmpeg iconv linking"
}
$IconvLibraryName = Split-Path $IconvImportLib -Leaf

New-Item -ItemType Directory -Force $LibAliasDir | Out-Null
$LameImportLib = Join-Path $VcpkgDependencyRoot "lib/libmp3lame.lib"
if (!(Test-Path $LameImportLib)) {
    throw "libmp3lame.lib from $VcpkgTriplet is required for FFmpeg libmp3lame linking"
}
Copy-Item -Force $LameImportLib (Join-Path $LibAliasDir "mp3lame.lib")
$ZlibImportLib = Join-Path $VcpkgDependencyRoot "lib/z.lib"
if (!(Test-Path $ZlibImportLib)) {
    throw "z.lib from $VcpkgTriplet is required for FFmpeg zlib linking"
}
Copy-Item -Force $ZlibImportLib (Join-Path $LibAliasDir "zlib.lib")
$WindowsSdkLibraryArch = if ($SdkArch -eq "x86_64") { "x64" } else { "arm64" }
if ([string]::IsNullOrWhiteSpace($env:WindowsSdkDir) -or [string]::IsNullOrWhiteSpace($env:WindowsSDKLibVersion)) {
    throw "Windows SDK library environment is required for FFmpeg linking"
}
$WindowsSdkLibraryVersion = $env:WindowsSDKLibVersion.TrimEnd("\\")
$WindowsSdkLibraryRoot = Join-Path $env:WindowsSdkDir "Lib\$WindowsSdkLibraryVersion"
$WindowsSdkUcrtLibraryDir = Join-Path $WindowsSdkLibraryRoot "ucrt\$WindowsSdkLibraryArch"
$WindowsSdkUmLibraryDir = Join-Path $WindowsSdkLibraryRoot "um\$WindowsSdkLibraryArch"
foreach ($WindowsSdkLibraryDir in @($WindowsSdkUcrtLibraryDir, $WindowsSdkUmLibraryDir)) {
    if (!(Test-Path $WindowsSdkLibraryDir)) {
        throw "Windows SDK library directory for $WindowsSdkLibraryArch was not found: $WindowsSdkLibraryDir"
    }
}
$WindowsSdkLibraryLink = Join-Path $BuildRoot "windows-sdk-lib"
if (Test-Path -LiteralPath $WindowsSdkLibraryLink) {
    $ExistingWindowsSdkLibraryLink = Get-Item -LiteralPath $WindowsSdkLibraryLink
    if ($ExistingWindowsSdkLibraryLink.LinkType -ne "Junction") {
        throw "Windows SDK library link path is occupied by a non-junction item: $WindowsSdkLibraryLink"
    }
    [System.IO.Directory]::Delete($WindowsSdkLibraryLink)
}
New-Item -ItemType Junction -Path $WindowsSdkLibraryLink -Target $WindowsSdkLibraryRoot | Out-Null

$MsvcLibraryArch = if ($SdkArch -eq "x86_64") { "x64" } else { "ARM64" }
if ([string]::IsNullOrWhiteSpace($env:VCToolsInstallDir)) {
    throw "MSVC toolchain environment is required for FFmpeg linking"
}
$MsvcLibraryDir = Join-Path $env:VCToolsInstallDir "lib\$MsvcLibraryArch"
if (!(Test-Path $MsvcLibraryDir)) {
    throw "MSVC library directory for $MsvcLibraryArch was not found: $MsvcLibraryDir"
}
$MsvcLibraryLink = Join-Path $BuildRoot "msvc-lib"
if (Test-Path -LiteralPath $MsvcLibraryLink) {
    $ExistingMsvcLibraryLink = Get-Item -LiteralPath $MsvcLibraryLink
    if ($ExistingMsvcLibraryLink.LinkType -ne "Junction") {
        throw "MSVC library link path is occupied by a non-junction item: $MsvcLibraryLink"
    }
    [System.IO.Directory]::Delete($MsvcLibraryLink)
}
New-Item -ItemType Junction -Path $MsvcLibraryLink -Target $MsvcLibraryDir | Out-Null

$MsysNasmDir = ""
if ($SdkArch -eq "x86_64") {
    $NasmPath = $env:FFMPEG_NASM
    if ([string]::IsNullOrWhiteSpace($NasmPath)) {
        $Nasm = Get-Command nasm -ErrorAction SilentlyContinue
        if ($null -eq $Nasm) {
            throw "NASM is required for x86_64 FFmpeg builds but was not found on PATH"
        }
        $NasmPath = $Nasm.Path
    }
    if (!(Test-Path $NasmPath)) {
        throw "NASM executable does not exist: $NasmPath"
    }
    $MsysNasmDir = cygpath -u (Split-Path $NasmPath -Parent)
}

$VcpkgDependencyRootForMsvc = $VcpkgDependencyRoot.Replace("\", "/")
$LibAliasDirForMsvc = $LibAliasDir.Replace("\", "/")
$WindowsSdkLibraryLinkForMsvc = $WindowsSdkLibraryLink.Replace("\", "/")
$MsvcLibraryLinkForMsvc = $MsvcLibraryLink.Replace("\", "/")
$WindowsSdkUcrtLibraryFlag = "/libpath:$WindowsSdkLibraryLinkForMsvc/ucrt/$WindowsSdkLibraryArch"
$WindowsSdkUmLibraryFlag = "/libpath:$WindowsSdkLibraryLinkForMsvc/um/$WindowsSdkLibraryArch"
$MsvcLibraryFlag = "/libpath:$MsvcLibraryLinkForMsvc"

if ([string]::IsNullOrWhiteSpace($env:MSYS2_LOCATION)) {
    throw "MSYS2_LOCATION is required for pkg-config"
}
$PkgConfigRelativePath = if ($SdkArch -eq "arm64") { "clangarm64/bin/pkg-config.exe" } else { "mingw64/bin/pkg-config.exe" }
$PkgConfigExe = Join-Path $env:MSYS2_LOCATION $PkgConfigRelativePath
if (!(Test-Path $PkgConfigExe)) {
    throw "MSYS2 pkg-config is required for ${PlatformKey}: $PkgConfigExe"
}

New-Item -ItemType Directory -Force (Join-Path $BuildRoot "downloads") | Out-Null
New-Item -ItemType Directory -Force (Join-Path $BuildRoot "src") | Out-Null
New-Item -ItemType Directory -Force $BuildToolsDir | Out-Null
$IconvProbeSource = Join-Path $BuildToolsDir "iconv-link-probe.c"
$IconvProbeExe = Join-Path $BuildToolsDir "iconv-link-probe.exe"
Set-Content -LiteralPath $IconvProbeSource -Encoding utf8NoBOM -Value @'
#include <iconv.h>
int main(void) {
    iconv_t converter = iconv_open("UTF-8", "ASCII");
    return iconv_close(converter);
}
'@
$IconvProbeArgs = @("/nologo", "/MD", "/I$VcpkgDependencyRoot/include")
if ($SdkArch -eq "arm64") {
    $IconvProbeArgs += "--target=arm64-windows"
}
$IconvProbeArgs += @($IconvProbeSource, "/Fe$IconvProbeExe", "/link", $IconvImportLib)
& clang-cl @IconvProbeArgs
if ($LASTEXITCODE -ne 0) {
    throw "FFmpeg iconv import library failed to link for ${PlatformKey}: $IconvImportLib"
}
Remove-Item -Recurse -Force $InstallPrefix, $SdkRoot -ErrorAction SilentlyContinue

if (!(Test-Path $SourceArchive)) {
    Invoke-WebRequest `
        -Uri $FfmpegSourceUrl `
        -OutFile $SourceArchive `
        -MaximumRetryCount 3 `
        -RetryIntervalSec 5
}
$ActualSourceSha256 = (Get-FileHash -Algorithm SHA256 $SourceArchive).Hash.ToLowerInvariant()
if ($ActualSourceSha256 -ne $FfmpegSourceSha256) {
    throw "FFmpeg source archive SHA256 mismatch for $SourceArchive. Expected $FfmpegSourceSha256, got $ActualSourceSha256"
}

Remove-Item -Recurse -Force $SourceDir -ErrorAction SilentlyContinue
tar -xzf $SourceArchive -C (Join-Path $BuildRoot "src")
if ($LASTEXITCODE -ne 0) {
    throw "Failed to extract FFmpeg source archive"
}
& python "$RootDir/scripts/patch-windows-response-file.py" "$SourceDir"
if ($LASTEXITCODE -ne 0) {
    throw "Failed to patch FFmpeg Windows response-file recipe"
}
& python "$RootDir/scripts/patch-windows-mediafoundation.py" "$SourceDir"
if ($LASTEXITCODE -ne 0) {
    throw "Failed to patch FFmpeg Windows Media Foundation version guard"
}

$env:GIT_CEILING_DIRECTORIES = (Join-Path $BuildRoot "src").Replace("\", "/")
$MsysSourceDir = cygpath -u $SourceDir
$MsysInstallPrefix = cygpath -u $InstallPrefix
$MsysSdkRoot = cygpath -u $SdkRoot
$MsysRootDir = cygpath -u $RootDir
$MsysBuildToolsDir = cygpath -u $BuildToolsDir
$MsysVcpkgDependencyRoot = cygpath -u $VcpkgDependencyRoot
$MsysPkgConfigExe = cygpath -u $PkgConfigExe
$MsysPkgConfigDir = cygpath -u (Split-Path -Path $PkgConfigExe -Parent)

$configureCommand = @"
set -euo pipefail
mkdir -p '$MsysBuildToolsDir'
cat > '$MsysBuildToolsDir/wslpath' <<'EOF'
#!/usr/bin/env bash
if [[ "`$#" -eq 0 || -z "`${1:-}" ]]; then
  exit 0
fi
if [[ "`${1:-}" == "-u" ]]; then
  shift
fi
args=()
for arg in "`$@"; do
  if [[ -n "`$arg" ]]; then
    args+=("`$arg")
  fi
done
if [[ "`${#args[@]}" -eq 0 ]]; then
  exit 0
fi
cygpath -u "`${args[@]}"
EOF
chmod +x '$MsysBuildToolsDir/wslpath'
export PATH='${MsysBuildToolsDir}:${MsysPkgConfigDir}:${MsysNasmDir}:'"`$PATH"':/usr/bin'
export PKG_CONFIG_LIBDIR='${MsysVcpkgDependencyRoot}/lib/pkgconfig:${MsysVcpkgDependencyRoot}/share/pkgconfig'
export PKG_CONFIG_PATH=''
echo "bash: `$(command -v bash)"
echo "awk: `$(command -v awk)"
echo "clang-cl: `$(command -v clang-cl)"
echo "link: `$(command -v link)"
echo "make: `$(command -v make)"
if [[ -n '$MsysNasmDir' ]]; then
  echo "nasm: `$(command -v nasm)"
  nasm -v
fi
echo "pkgconf: `$(command -v pkgconf || true)"
echo "pkg-config: `$(command -v pkg-config || true)"
echo "MSYS2 pkg-config: $MsysPkgConfigExe"
echo "wslpath: `$(command -v wslpath)"
'$MsysPkgConfigExe' --version
if ! '$MsysPkgConfigExe' --exists "vpx >= 1.4.0"; then
  echo "MSYS2 pkg-config cannot locate the required vpx >= 1.4.0 package" >&2
  exit 1
fi
echo "vpx cflags: `$('$MsysPkgConfigExe' --cflags vpx)"
echo "vpx libs: `$('$MsysPkgConfigExe' --libs vpx)"
if ! '$MsysPkgConfigExe' --exists "aom >= 2.0.0"; then
  echo "MSYS2 pkg-config cannot locate the required aom >= 2.0.0 package" >&2
  exit 1
fi
cd '$MsysSourceDir'
if ! ./configure \
  --prefix='$MsysInstallPrefix' \
  --toolchain=msvc \
  --cc=clang-cl \
  --pkg-config='$MsysPkgConfigExe' \
  --target-os=win64 \
  --arch='$FfmpegArch' \
  $FfmpegCrossCompileFlag \
  --extra-cflags='$FfmpegTargetCflags -MD -I$VcpkgDependencyRootForMsvc/include' \
  --extra-ldflags='$FfmpegTargetLdflags $MsvcLibraryFlag $WindowsSdkUcrtLibraryFlag $WindowsSdkUmLibraryFlag /libpath:$LibAliasDirForMsvc /libpath:$VcpkgDependencyRootForMsvc/lib' \
  --extra-libs='$IconvLibraryName' \
  $FfmpegAssemblyFlag \
$FfmpegProfileConfigureArgs
  ; then
  cat ffbuild/config.log >&2 || true
  exit 1
fi
if ! cmake \
  -D SOURCE_DIR='$MsysSourceDir' \
  -D SDK_PLATFORM=windows \
  -D SDK_ARCH='$SdkArch' \
  -P '$MsysRootDir/scripts/validate-ffmpeg-components.cmake'; then
  echo "FFmpeg component validation failed; libvpx VP9 configure context follows:" >&2
  grep -n -C 32 "check_pkg_config libvpx_vp9_encoder" ffbuild/config.log >&2 || cat ffbuild/config.log >&2 || true
  exit 1
fi
make -j1 libavcodec/mf_utils.o
make -j`$(nproc)
find . -name '*.d' -delete
make install
mkdir -p '$MsysInstallPrefix/lib'
for import_lib in avcodec avdevice avfilter avformat avutil swresample swscale; do
  import_lib_path="lib`${import_lib}/`${import_lib}.lib"
  if [[ ! -f "`${import_lib_path}" ]]; then
    echo "Missing MSVC import library: `${import_lib_path}" >&2
    exit 1
  fi
  cp -p "`${import_lib_path}" "$MsysInstallPrefix/lib/`${import_lib}.lib"
done
if [[ -d '$MsysVcpkgDependencyRoot/bin' ]]; then
  for runtime_pattern in '*mp3lame*.dll' '*vpx*.dll' '*aom*.dll' '*opus*.dll' '*vorbis*.dll' '*ogg*.dll' '*opencore-amrnb*.dll' '*x264*.dll' '*x265*.dll' 'z.dll' 'zlib*.dll'; do
    find '$MsysVcpkgDependencyRoot/bin' -maxdepth 1 -type f -iname "`${runtime_pattern}" \
      -exec cp -p {} '$MsysInstallPrefix/bin/' \;
  done
  # Keep all vcpkg runtime DLLs beside FFmpeg. This includes libvpx's
  # transitive MSVC runtime dependencies, which are otherwise easy to miss
  # when the package changes its DLL naming or dependency graph.
  find '$MsysVcpkgDependencyRoot/bin' -maxdepth 1 -type f -iname '*.dll' \
    -exec cp -p {} '$MsysInstallPrefix/bin/' \;
fi
"@

$ConfigureScriptPath = Join-Path $BuildToolsDir "run-ffmpeg-build.sh"
Set-Content -LiteralPath $ConfigureScriptPath -Value $configureCommand -NoNewline -Encoding utf8NoBOM
& msys2 -c "bash '$MsysBuildToolsDir/run-ffmpeg-build.sh'"
if ($LASTEXITCODE -ne 0) {
    throw "FFmpeg Windows MSVC build failed"
}
& msys2 -c "bash '$MsysRootDir/scripts/stage-sdk.sh' --source '$MsysSourceDir' --prefix '$MsysInstallPrefix' --output '$MsysSdkRoot' --platform windows --arch '$SdkArch' --vcpkg-root '$MsysVcpkgDependencyRoot'"
if ($LASTEXITCODE -ne 0) {
    throw "Windows SDK staging failed"
}

& python "$RootDir/scripts/validate-sdk-dependencies.py" `
    --sdk-root "$SdkRoot" `
    --platform windows `
    --vcpkg-root "$VcpkgInstalledDir" `
    --triplet "$VcpkgTriplet"
if ($LASTEXITCODE -ne 0) {
    throw "Windows SDK dependency closure validation failed"
}

& python "$RootDir/scripts/generate-components.py" `
    --ffmpeg (Join-Path $SdkRoot "bin/ffmpeg.exe") `
    --parser-registry (Join-Path $SourceDir "libavcodec/parser_list.c") `
    --output (Join-Path $SdkRoot "components.json") `
    --platform-key "$PlatformKey" `
    --feature-profile "$FeatureProfile" `
    --ffmpeg-version "$FfmpegVersion"
if ($LASTEXITCODE -ne 0) {
    throw "Windows SDK component inventory failed"
}

$Python = (Get-Command python -ErrorAction Stop).Source
$RuntimeCapabilityValidator = Join-Path $RootDir "scripts/validate-ffmpeg-runtime-capabilities.py"
$StagedFfmpeg = Join-Path $SdkRoot "bin/ffmpeg.exe"
if (!(Test-Path $StagedFfmpeg)) {
    throw "Staged Windows FFmpeg executable was not found: $StagedFfmpeg"
}
& $Python $RuntimeCapabilityValidator `
    --ffmpeg $StagedFfmpeg `
    --require-encoder "libvpx-vp9" `
    --require-bsf "h264_metadata" `
    --require-bsf "hevc_metadata" `
    --components (Join-Path $SdkRoot "components.json")
if ($LASTEXITCODE -ne 0) {
    throw "Windows SDK runtime capability validation failed"
}

$Dumpbin = (Get-Command dumpbin -ErrorAction Stop).Path
& python "$RootDir/scripts/validate-windows-sdk-subsystem.py" `
    --sdk-root "$SdkRoot" `
    --maximum-subsystem-version "$MinimumSystemVersion" `
    --dumpbin "$Dumpbin"
if ($LASTEXITCODE -ne 0) {
    throw "Windows SDK PE subsystem validation failed"
}

cmake `
    -D "TEMPLATE_FILE=$RootDir/templates/manifest.json.in" `
    -D "OUTPUT_FILE=$SdkRoot/manifest.json" `
    -D "SDK_VERSION=$SdkVersion" `
    -D "FFMPEG_VERSION=$FfmpegVersion" `
    -D "SDK_PLATFORM=windows" `
    -D "SDK_ARCH=$SdkArch" `
    -D "MINIMUM_SYSTEM_VERSION=$MinimumSystemVersion" `
    -D "SDK_COMPILER=$(& clang-cl --version 2>&1 | Select-Object -First 1)" `
    -D "VCPKG_BASELINE=$VcpkgBaseline" `
    -D "VCPKG_TRIPLET=$VcpkgTriplet" `
    -D "FFMPEG_SOURCE_URL=$FfmpegSourceUrl" `
    -D "FFMPEG_SOURCE_SHA256=$FfmpegSourceSha256" `
    -D "FEATURE_PROFILE=$FeatureProfile" `
    -D "SDK_EXTERNAL_DEPENDENCIES_JSON=$ExternalDependenciesJson" `
    -D "LICENSE_MODE=$LicenseMode" `
    -D "BUILD_ID=$($env:GITHUB_RUN_ID)-$($env:GITHUB_RUN_ATTEMPT)" `
    -D "CREATED_AT=$((Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ"))" `
    -P "$RootDir/scripts/generate-manifest.cmake"
if ($LASTEXITCODE -ne 0) {
    throw "Windows SDK manifest generation failed"
}

& $Python $RuntimeCapabilityValidator `
    --ffmpeg $StagedFfmpeg `
    --require-encoder "libvpx-vp9" `
    --require-bsf "h264_metadata" `
    --require-bsf "hevc_metadata" `
    --components (Join-Path $SdkRoot "components.json")
if ($LASTEXITCODE -ne 0) {
    throw "Windows SDK manifest/runtime capability validation failed"
}

& $Python "$RootDir/scripts/validate-media-coverage.py" --ffmpeg $StagedFfmpeg --ffprobe (Join-Path $SdkRoot "bin/ffprobe.exe")
if ($LASTEXITCODE -ne 0) { throw "Windows SDK media coverage validation failed" }
& $Python "$RootDir/scripts/validate-https-input.py" --ffmpeg $StagedFfmpeg
if ($LASTEXITCODE -ne 0) { throw "Windows SDK HTTPS input validation failed" }

cmake `
    -D "SDK_ROOT=$SdkRoot" `
    -D "SDK_PLATFORM=windows" `
    -D "SDK_ARCH=$SdkArch" `
    -D "VCPKG_TRIPLET=$VcpkgTriplet" `
    -P "$RootDir/scripts/validate-sdk-layout.cmake"
if ($LASTEXITCODE -ne 0) {
    throw "Windows SDK validation failed"
}

Write-Host "SDK directory: $SdkRoot"
