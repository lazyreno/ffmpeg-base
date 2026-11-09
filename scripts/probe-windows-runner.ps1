$ErrorActionPreference = 'Stop'
$sdkInclude = @($env:INCLUDE -split ';' | Where-Object { $_ -and (Test-Path (Join-Path $_ 'windows.h')) })[0]
if (-not $sdkInclude) { throw 'Windows SDK windows.h is absent from vcvarsall INCLUDE' }
$env:PROBE_WINSDK_INCLUDE = $sdkInclude
Write-Host "ImageOS=$env:ImageOS ImageVersion=$env:ImageVersion"
Write-Host "MSVC=$env:VCToolsVersion WindowsSDK=$env:WindowsSDKVersion"
Write-Host "Windows SDK include=$sdkInclude"
Write-Host "rc.exe=$((Get-Command rc.exe).Source)"
Write-Host "link.exe=$((Get-Command link.exe).Source)"
$bash = (Get-Command bash.exe -ErrorAction Stop).Source
Write-Host "bash=$bash"

$probe = @'
set -u
cd "$(cygpath -u "$GITHUB_WORKSPACE")"
printf 'MSYS pwd=%s\n' "$(pwd -W)"
printf 'MSYS INCLUDE=%s\n' "${INCLUDE:-missing}"
printf 'make=%s\n' "$(command -v make || true)"
printf '#include <windows.h>\n1 RCDATA BEGIN 0 END\n' > ci-probe.rc
if rc.exe -nologo -fo ci-probe.res ci-probe.rc; then echo RC_DEFAULT_OK; else echo RC_DEFAULT_FAILED; fi
if rc.exe -nologo -i"$PROBE_WINSDK_INCLUDE" -fo ci-probe-explicit.res ci-probe.rc; then echo RC_EXPLICIT_OK; else echo RC_EXPLICIT_FAILED; fi
if rc.exe -nologo -i. -i. -fo ci-probe-source-only.res ci-probe.rc; then echo RC_SOURCE_ONLY_OK; else echo RC_SOURCE_ONLY_FAILED; fi
if rc.exe -nologo -i. -i./ -fo ci-probe-source-slash.res ci-probe.rc; then echo RC_SOURCE_SLASH_OK; else echo RC_SOURCE_SLASH_FAILED; fi
cat > ci-mswindres <<'EOF'
#!/bin/sh
EXTRA_OPTS="-nologo"
while [ $# -gt 2 ]; do
  case $1 in
    -D*) EXTRA_OPTS="$EXTRA_OPTS -d$(echo $1 | sed -e "s/^..//" -e "s/ /\\ /g")" ;;
    -I*) EXTRA_OPTS="$EXTRA_OPTS -i$(echo $1 | sed -e "s/^..//" -e "s/ /\\ /g")" ;;
    -o) OPT_OUT="$2"; shift ;;
  esac
  shift
done
IN="$1"
OUT="$OPT_OUT"
eval set -- $EXTRA_OPTS
rc.exe "$@" -fo "$OUT" "$IN"
EOF
chmod +x ci-mswindres
if ./ci-mswindres -I. -I./ -o ci-probe-wrapper.res ci-probe.rc; then echo RC_WRAPPER_OK; else echo RC_WRAPPER_FAILED; fi
printf 'int ci_probe(void) { return 42; }\n' > ci-probe.c
cl.exe -nologo -c -Foci-probe.obj ci-probe.c || exit $?
mkdir -p libavcodec
cp ci-probe.obj libavcodec/ci-probe.o
printf 'libavcodec/ci-probe.o\n' > libavcodec/avcodec-62.dll.objs
printf 'response-file bytes=%s\n' "$(wc -c < libavcodec/avcodec-62.dll.objs)"
cat > ci-mslink <<'EOF'
#!/bin/sh
LINK_EXE_PATH=$(dirname "$(command -v cl)")/link
if [ -x "$LINK_EXE_PATH" ]; then "$LINK_EXE_PATH" $@; else link.exe $@; fi
EOF
chmod +x ci-mslink
if ./ci-mslink -NOLOGO -DLL -NOENTRY -OUT:libavcodec/probe.dll @libavcodec/avcodec-62.dll.objs; then echo RESPONSE_RELATIVE_OK; else echo RESPONSE_RELATIVE_FAILED; fi
response_native=$(cygpath -w "$(pwd)/libavcodec/avcodec-62.dll.objs")
if ./ci-mslink -NOLOGO -DLL -NOENTRY -OUT:libavcodec/probe-native.dll "@$response_native"; then echo RESPONSE_NATIVE_OK; else echo RESPONSE_NATIVE_FAILED; fi
for i in $(seq 1 2500); do echo libavcodec/ci-probe.o; done > libavcodec/avcodec-62.dll.objs
printf 'large-response bytes=%s\n' "$(wc -c < libavcodec/avcodec-62.dll.objs)"
if ./ci-mslink -NOLOGO -DLL -NOENTRY -OUT:libavcodec/probe-large.dll @libavcodec/avcodec-62.dll.objs; then echo RESPONSE_LARGE_OK; else echo RESPONSE_LARGE_FAILED; fi
objects=$(for i in $(seq 1 2500); do printf 'libavcodec/ci-probe.o '; done)
if bash -c "echo $objects > libavcodec/avcodec-make.dll.objs" && test -s libavcodec/avcodec-make.dll.objs; then
  echo RESPONSE_MAKE_STYLE_OK
else
  echo RESPONSE_MAKE_STYLE_FAILED
fi
printf 'OBJS :=' > ci-probe.mk
for i in $(seq 1 2500); do printf ' libavcodec/ci-probe.o' >> ci-probe.mk; done
cat >> ci-probe.mk <<'EOF'

.PHONY: all
all: ci-probe-make.res libavcodec/avcodec-make2.dll.objs
ci-probe-make.res: ci-probe.rc
	./ci-mswindres -I. -I./ -o $@ $<
libavcodec/avcodec-make2.dll.objs:
	@echo $(OBJS) > $@
EOF
if make -f ci-probe.mk all; then echo MAKE_RECIPES_OK; else echo MAKE_RECIPES_FAILED; fi
if test -s libavcodec/avcodec-make2.dll.objs; then echo MAKE_RESPONSE_EXISTS; else echo MAKE_RESPONSE_MISSING; fi
cat >> ci-probe.mk <<'EOF'
.PHONY: file
file:
	$(file >libavcodec/avcodec-make3.dll.objs,$(OBJS))
	@test -s libavcodec/avcodec-make3.dll.objs
EOF
if make -f ci-probe.mk file; then echo MAKE_FILE_FUNCTION_OK; else echo MAKE_FILE_FUNCTION_FAILED; fi
'@
$probePath = Join-Path $env:GITHUB_WORKSPACE 'ci-probe.sh'
Set-Content -LiteralPath $probePath -Value $probe -NoNewline -Encoding utf8NoBOM
& $bash --login $probePath
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$lock = Get-Content (Join-Path $env:GITHUB_WORKSPACE 'config/source-lock.json') -Raw | ConvertFrom-Json
$sourceArchive = Join-Path $env:RUNNER_TEMP 'ffmpeg-source-probe.tar.gz'
Invoke-WebRequest -Uri $lock.url -OutFile $sourceArchive -MaximumRetryCount 3 -RetryIntervalSec 5
if ((Get-FileHash $sourceArchive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $lock.sha256) {
    throw 'Pinned FFmpeg source hash mismatch in Windows probe'
}
$sourceParent = Join-Path $env:RUNNER_TEMP 'ffmpeg-source-probe'
New-Item -ItemType Directory -Force $sourceParent | Out-Null
tar -xzf $sourceArchive -C $sourceParent
if ($LASTEXITCODE -ne 0) { throw 'Pinned FFmpeg source extraction failed in Windows probe' }
$sourceDir = Join-Path $sourceParent "FFmpeg-$($lock.tag)"
$sourceMsys = (& $bash --login -c "cygpath -u '$sourceDir'").Trim()
$targetArch = if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq [System.Runtime.InteropServices.Architecture]::Arm64) { 'aarch64' } else { 'x86_64' }
$asmFlag = '--disable-asm'
& $bash --login -c "cd '$sourceMsys' && ./configure --toolchain=msvc --cc=clang-cl --target-os=win64 --arch=$targetArch $asmFlag --disable-autodetect --disable-everything --enable-avdevice --enable-indev=dshow --enable-indev=gdigrab --enable-shared --disable-static --disable-doc --disable-programs > ci-configure.log 2>&1 && make V=1 libavdevice/avdeviceres.o"
if ($LASTEXITCODE -eq 0) {
    Write-Host 'FFMPEG_REAL_RESOURCE_OK'
} else {
    Write-Host 'FFMPEG_REAL_RESOURCE_FAILED'
    Get-Content (Join-Path $sourceDir 'ci-configure.log') -Tail 30
}
