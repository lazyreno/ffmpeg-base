Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RootDir = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $RootDir

$SdkArch = if ($env:SDK_ARCH) { $env:SDK_ARCH } else { "x86_64" }
switch ($SdkArch) {
    "x86_64" {
        $FfmpegArch = "x86_64"
        $FfmpegCrossCompileFlag = ""
        $FfmpegTargetCflags = ""
        $FfmpegAssemblyFlag = "--disable-x86asm"
        $VcpkgTriplet = "windows-x64-msvc"
    }
    "arm64" {
        $FfmpegArch = "aarch64"
        $FfmpegCrossCompileFlag = "--enable-cross-compile"
        $FfmpegTargetCflags = "--target=arm64-windows"
        $FfmpegAssemblyFlag = "--disable-asm"
        $VcpkgTriplet = "windows-arm64-msvc"
    }
    default {
        throw "Unsupported Windows SDK architecture: $SdkArch"
    }
}

$PlatformKey = "windows-$SdkArch"
$BuildRoot = if ($env:BUILD_ROOT) { $env:BUILD_ROOT } else { Join-Path $RootDir "build/$PlatformKey" }
$DistDir = if ($env:DIST_DIR) { $env:DIST_DIR } else { Join-Path $RootDir "dist" }

$SdkConfig = Get-Content "config/sdk-version.json" -Raw | ConvertFrom-Json
$SourceLock = Get-Content "config/source-lock.json" -Raw | ConvertFrom-Json
$SdkVersion = $SdkConfig.sdkVersion
$FfmpegVersion = $SdkConfig.ffmpegVersion
$LicenseMode = $SdkConfig.licenseMode
$FeatureProfile = $SdkConfig.featureProfile
$VcpkgBaseline = $SdkConfig.vcpkgBaseline
$ProfileConfig = Get-Content "config/ffmpeg-profile.json" -Raw | ConvertFrom-Json
if ($ProfileConfig.profile -ne $FeatureProfile) {
    throw "config/ffmpeg-profile.json profile $($ProfileConfig.profile) does not match sdk-version featureProfile $FeatureProfile"
}
if ($ProfileConfig.licenseMode -ne $LicenseMode) {
    throw "config/ffmpeg-profile.json licenseMode $($ProfileConfig.licenseMode) does not match sdk-version licenseMode $LicenseMode"
}
$FeaturesJson = (@($ProfileConfig.features.common) + @($ProfileConfig.features.windows) | ConvertTo-Json -Compress)
$ProfileConfigureFlags = @($ProfileConfig.configure.common) + @($ProfileConfig.configure.windows)

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
$ArchivePath = Join-Path $DistDir "$SdkDirName.zip"
$BuildToolsDir = Join-Path $BuildRoot "tools"
$LibAliasDir = Join-Path $BuildRoot "lib-alias"
$VcpkgRoot = if ($env:VCPKG_ROOT) { $env:VCPKG_ROOT } elseif ($env:VCPKG_INSTALLATION_ROOT) { $env:VCPKG_INSTALLATION_ROOT } else { "C:\vcpkg" }
$VcpkgInstalledDir = if ($env:VCPKG_INSTALLED_DIR) { $env:VCPKG_INSTALLED_DIR } else { Join-Path $VcpkgRoot "installed" }
$VcpkgDependencyRoot = Join-Path $VcpkgInstalledDir $VcpkgTriplet
$VcpkgMsysToolsRoot = Join-Path $VcpkgRoot "downloads/tools/msys2"

$RequiredVcpkgDependencyHeaders = @(
    "include/lame/lame.h",
    "include/vpx/vpx_encoder.h",
    "include/aom/aom_encoder.h",
    "include/opus/opus.h",
    "include/vorbis/codec.h"
)
foreach ($RequiredHeader in $RequiredVcpkgDependencyHeaders) {
    if (!(Test-Path (Join-Path $VcpkgDependencyRoot $RequiredHeader))) {
        throw "$RequiredHeader from $VcpkgTriplet must be installed with vcpkg before building the desktop LGPL app SDK profile"
    }
}
if (!(Test-Path (Join-Path $VcpkgDependencyRoot "lib"))) {
    throw "vcpkg lib directory for $VcpkgTriplet is required before building the desktop LGPL app SDK profile"
}

New-Item -ItemType Directory -Force $LibAliasDir | Out-Null
$LameImportLib = Join-Path $VcpkgDependencyRoot "lib/libmp3lame.lib"
if (!(Test-Path $LameImportLib)) {
    throw "libmp3lame.lib from $VcpkgTriplet is required for FFmpeg libmp3lame linking"
}
Copy-Item -Force $LameImportLib (Join-Path $LibAliasDir "mp3lame.lib")

$VcpkgDependencyRootForMsvc = $VcpkgDependencyRoot.Replace("\", "/")
$LibAliasDirForMsvc = $LibAliasDir.Replace("\", "/")

if (!(Test-Path $VcpkgMsysToolsRoot)) {
    throw "vcpkg MSYS2 tools directory is required for pkg-config: $VcpkgMsysToolsRoot"
}
$PkgConfigCandidates = @(Get-ChildItem -Path $VcpkgMsysToolsRoot -Recurse -File |
    Where-Object { $_.Name -in @("pkg-config.exe", "pkgconf.exe") } |
    Where-Object { $_.FullName -match "\\(mingw64|usr)\\bin\\" } |
    Sort-Object {
        if ($_.FullName -match "\\mingw64\\bin\\pkg-config\.exe$") { 0 }
        elseif ($_.FullName -match "\\usr\\bin\\pkg-config\.exe$") { 1 }
        else { 2 }
    }, FullName)
if ($PkgConfigCandidates.Count -eq 0) {
    throw "No vcpkg-provided pkg-config executable found under $VcpkgMsysToolsRoot"
}
$PkgConfigExe = $PkgConfigCandidates[0].FullName

New-Item -ItemType Directory -Force (Join-Path $BuildRoot "downloads") | Out-Null
New-Item -ItemType Directory -Force (Join-Path $BuildRoot "src") | Out-Null
New-Item -ItemType Directory -Force $DistDir | Out-Null
New-Item -ItemType Directory -Force $BuildToolsDir | Out-Null
Remove-Item -Recurse -Force $InstallPrefix, $SdkRoot, $ArchivePath, "$ArchivePath.sha256" -ErrorAction SilentlyContinue

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

$env:GIT_CEILING_DIRECTORIES = (Join-Path $BuildRoot "src").Replace("\", "/")
$MsysSourceDir = cygpath -u $SourceDir
$MsysInstallPrefix = cygpath -u $InstallPrefix
$MsysSdkRoot = cygpath -u $SdkRoot
$MsysRootDir = cygpath -u $RootDir
$MsysBuildToolsDir = cygpath -u $BuildToolsDir
$MsysVcpkgDependencyRoot = cygpath -u $VcpkgDependencyRoot
$MsysPkgConfigExe = cygpath -u $PkgConfigExe
$MsysPkgConfigDir = Split-Path $MsysPkgConfigExe -Parent

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
export PATH='${MsysBuildToolsDir}:${MsysPkgConfigDir}:'"`$PATH"':/usr/bin'
export PKG_CONFIG_PATH='${MsysVcpkgDependencyRoot}/lib/pkgconfig:${MsysVcpkgDependencyRoot}/share/pkgconfig'":`${PKG_CONFIG_PATH:-}"
echo "bash: `$(command -v bash)"
echo "awk: `$(command -v awk)"
echo "clang-cl: `$(command -v clang-cl)"
echo "link: `$(command -v link)"
echo "make: `$(command -v make)"
echo "pkgconf: `$(command -v pkgconf || true)"
echo "pkg-config: `$(command -v pkg-config || true)"
echo "vcpkg pkg-config: $MsysPkgConfigExe"
echo "wslpath: `$(command -v wslpath)"
'$MsysPkgConfigExe' --version
cd '$MsysSourceDir'
if ! ./configure \
  --prefix='$MsysInstallPrefix' \
  --toolchain=msvc \
  --cc=clang-cl \
  --pkg-config='$MsysPkgConfigExe' \
  --target-os=win64 \
  --arch='$FfmpegArch' \
  $FfmpegCrossCompileFlag \
  --extra-cflags='$FfmpegTargetCflags -I$VcpkgDependencyRootForMsvc/include' \
  --extra-ldflags='dxguid.lib /libpath:$LibAliasDirForMsvc /libpath:$VcpkgDependencyRootForMsvc/lib' \
  $FfmpegAssemblyFlag \
$FfmpegProfileConfigureArgs
  ; then
  cat ffbuild/config.log >&2 || true
  exit 1
fi
make -j`$(nproc)
find . -name '*.d' -delete
make install
mkdir -p '$MsysInstallPrefix/lib'
mkdir -p '$MsysInstallPrefix/licenses/lame'
for import_lib in avcodec avdevice avfilter avformat avutil swresample swscale; do
  import_lib_path="lib`${import_lib}/`${import_lib}.lib"
  if [[ ! -f "`${import_lib_path}" ]]; then
    echo "Missing MSVC import library: `${import_lib_path}" >&2
    exit 1
  fi
  cp -p "`${import_lib_path}" "$MsysInstallPrefix/lib/`${import_lib}.lib"
done
if [[ -d '$MsysVcpkgDependencyRoot/bin' ]]; then
  for runtime_pattern in '*mp3lame*.dll' '*vpx*.dll' '*aom*.dll' '*opus*.dll' '*vorbis*.dll' '*ogg*.dll'; do
    find '$MsysVcpkgDependencyRoot/bin' -maxdepth 1 -type f -iname "`${runtime_pattern}" \
      -exec cp -p {} '$MsysInstallPrefix/bin/' \;
  done
fi
for package_name in mp3lame libvpx aom opus libvorbis libogg; do
  mkdir -p "$MsysInstallPrefix/licenses/`${package_name}"
  if [[ -f "$MsysVcpkgDependencyRoot/share/`${package_name}/copyright" ]]; then
    cp -p "$MsysVcpkgDependencyRoot/share/`${package_name}/copyright" "$MsysInstallPrefix/licenses/`${package_name}/LICENSE"
  fi
done
"@

bash -lc $configureCommand
if ($LASTEXITCODE -ne 0) {
    throw "FFmpeg Windows MSVC build failed"
}

bash "$MsysRootDir/scripts/stage-sdk.sh" `
    --source "$MsysSourceDir" `
    --prefix "$MsysInstallPrefix" `
    --output "$MsysSdkRoot" `
    --platform windows `
    --arch "$SdkArch"
if ($LASTEXITCODE -ne 0) {
    throw "Windows SDK staging failed"
}

cmake `
    -D "TEMPLATE_FILE=$RootDir/templates/manifest.json.in" `
    -D "OUTPUT_FILE=$SdkRoot/manifest.json" `
    -D "SDK_VERSION=$SdkVersion" `
    -D "FFMPEG_VERSION=$FfmpegVersion" `
    -D "SDK_PLATFORM=windows" `
    -D "SDK_ARCH=$SdkArch" `
    -D "SDK_COMPILER=$(& clang-cl --version 2>&1 | Select-Object -First 1)" `
    -D "VCPKG_BASELINE=$VcpkgBaseline" `
    -D "VCPKG_TRIPLET=$VcpkgTriplet" `
    -D "FFMPEG_SOURCE_URL=$FfmpegSourceUrl" `
    -D "FFMPEG_SOURCE_SHA256=$FfmpegSourceSha256" `
    -D "SDK_FEATURES_JSON=$FeaturesJson" `
    -D "LICENSE_MODE=$LicenseMode" `
    -D "BUILD_ID=$($env:GITHUB_RUN_ID)-$($env:GITHUB_RUN_ATTEMPT)" `
    -D "CREATED_AT=$((Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ"))" `
    -P "$RootDir/scripts/generate-manifest.cmake"
if ($LASTEXITCODE -ne 0) {
    throw "Windows SDK manifest generation failed"
}

cmake `
    -D "SDK_ROOT=$SdkRoot" `
    -D "SDK_PLATFORM=windows" `
    -D "SDK_ARCH=$SdkArch" `
    -P "$RootDir/scripts/validate-sdk-layout.cmake"
if ($LASTEXITCODE -ne 0) {
    throw "Windows SDK validation failed"
}

Compress-Archive -Path $SdkRoot -DestinationPath $ArchivePath -Force
$ArchiveHash = (Get-FileHash -Algorithm SHA256 $ArchivePath).Hash.ToLowerInvariant()
Set-Content -Path "$ArchivePath.sha256" -Value $ArchiveHash -NoNewline

Write-Host "SDK archive: $ArchivePath"
Write-Host "SHA256     : $ArchiveHash"
