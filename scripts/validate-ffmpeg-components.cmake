cmake_minimum_required(VERSION 3.21)

if(NOT DEFINED SOURCE_DIR OR SOURCE_DIR STREQUAL "")
    message(FATAL_ERROR "SOURCE_DIR is required")
endif()
if(NOT SDK_PLATFORM MATCHES "^(macos|windows)$")
    message(FATAL_ERROR "SDK_PLATFORM must be macos or windows")
endif()
if(NOT SDK_ARCH MATCHES "^(arm64|x86_64)$")
    message(FATAL_ERROR "SDK_ARCH must be arm64 or x86_64")
endif()

function(require_registry_symbol registry_path registry_content symbol description)
    if(NOT "${registry_content}" MATCHES
            "(^|\n)[ \t]*&${symbol},[ \t]*(\r?\n|$)")
        message(FATAL_ERROR
            "FFmpeg configure did not register ${description} (${symbol}) in ${registry_path}")
    endif()
endfunction()

set(demuxer_list "${SOURCE_DIR}/libavformat/demuxer_list.c")
set(muxer_list "${SOURCE_DIR}/libavformat/muxer_list.c")
set(codec_list "${SOURCE_DIR}/libavcodec/codec_list.c")
set(filter_list "${SOURCE_DIR}/libavfilter/filter_list.c")
set(indev_list "${SOURCE_DIR}/libavdevice/indev_list.c")
set(outdev_list "${SOURCE_DIR}/libavdevice/outdev_list.c")
set(config_header "${SOURCE_DIR}/config.h")

foreach(registry_path IN ITEMS
        "${demuxer_list}"
        "${muxer_list}"
        "${codec_list}"
        "${filter_list}"
        "${indev_list}"
        "${outdev_list}"
        "${config_header}")
    if(NOT EXISTS "${registry_path}")
        message(FATAL_ERROR
            "FFmpeg generated registry was not found after configure: ${registry_path}")
    endif()
endforeach()

file(READ "${demuxer_list}" demuxer_list_content)
file(READ "${muxer_list}" muxer_list_content)
file(READ "${codec_list}" codec_list_content)
file(READ "${filter_list}" filter_list_content)
file(READ "${indev_list}" indev_list_content)
file(READ "${outdev_list}" outdev_list_content)
file(READ "${config_header}" config_header_content)

foreach(audio_filter IN ITEMS adelay afftdn aformat amix aresample pan volume)
    require_registry_symbol(
        "${filter_list}" "${filter_list_content}"
        "ff_af_${audio_filter}" "${audio_filter} audio filter")
endforeach()

require_registry_symbol(
    "${muxer_list}" "${muxer_list_content}"
    "ff_pcm_f32le_muxer" "pcm_f32le muxer")
require_registry_symbol(
    "${muxer_list}" "${muxer_list_content}"
    "ff_amr_muxer" "AMR muxer")
require_registry_symbol(
    "${muxer_list}" "${muxer_list_content}"
    "ff_aiff_muxer" "AIFF muxer")
require_registry_symbol(
    "${codec_list}" "${codec_list_content}"
    "ff_mjpeg_encoder" "MJPEG encoder")
require_registry_symbol(
    "${codec_list}" "${codec_list_content}"
    "ff_rawvideo_decoder" "RawVideo decoder")
require_registry_symbol(
    "${codec_list}" "${codec_list_content}"
    "ff_prores_decoder" "ProRes decoder")
require_registry_symbol(
    "${codec_list}" "${codec_list_content}"
    "ff_prores_ks_encoder" "ProRes encoder")
require_registry_symbol(
    "${codec_list}" "${codec_list_content}"
    "ff_rawvideo_encoder" "RawVideo encoder")
require_registry_symbol(
    "${codec_list}" "${codec_list_content}"
    "ff_adpcm_ima_wav_decoder" "IMA ADPCM decoder")
require_registry_symbol(
    "${codec_list}" "${codec_list_content}"
    "ff_alac_encoder" "ALAC encoder")
require_registry_symbol(
    "${codec_list}" "${codec_list_content}"
    "ff_libopencore_amrnb_encoder" "OpenCORE AMR-NB encoder")
require_registry_symbol(
    "${codec_list}" "${codec_list_content}"
    "ff_pcm_s16be_encoder" "PCM S16BE encoder")
require_registry_symbol(
    "${codec_list}" "${codec_list_content}"
    "ff_wmav2_encoder" "Windows Media Audio v2 encoder")
require_registry_symbol(
    "${codec_list}" "${codec_list_content}"
    "ff_libx264_encoder" "libx264 encoder")
require_registry_symbol(
    "${codec_list}" "${codec_list_content}"
    "ff_libx265_encoder" "libx265 encoder")
require_registry_symbol(
    "${codec_list}" "${codec_list_content}"
    "ff_libvpx_vp9_encoder" "libvpx-vp9 encoder")
require_registry_symbol(
    "${indev_list}" "${indev_list_content}"
    "ff_lavfi_demuxer" "lavfi demuxer")

foreach(external_codec IN ITEMS
        ff_libdav1d_decoder
        ff_libgsm_decoder
        ff_libgsm_encoder
        ff_libjxl_encoder
        ff_libopenjpeg_encoder
        ff_libopencore_amrwb_decoder
        ff_libspeex_encoder
        ff_libsvtav1_encoder
        ff_libvo_amrwbenc_encoder
        ff_libwebp_encoder)
    require_registry_symbol(
        "${codec_list}" "${codec_list_content}"
        "${external_codec}" "external codec")
endforeach()
foreach(external_demuxer IN ITEMS ff_libopenmpt_demuxer ff_libgme_demuxer)
    require_registry_symbol(
        "${demuxer_list}" "${demuxer_list_content}"
        "${external_demuxer}" "external demuxer")
endforeach()
foreach(external_filter IN ITEMS ff_af_rubberband ff_vf_zscale ff_vf_subtitles ff_vf_drawtext)
    require_registry_symbol(
        "${filter_list}" "${filter_list_content}"
        "${external_filter}" "external filter")
endforeach()

if(SDK_PLATFORM STREQUAL "macos")
    require_registry_symbol("${indev_list}" "${indev_list_content}"
        "ff_avfoundation_demuxer" "AVFoundation input device")
    require_registry_symbol("${outdev_list}" "${outdev_list_content}"
        "ff_audiotoolbox_muxer" "AudioToolbox output device")
    require_registry_symbol("${codec_list}" "${codec_list_content}"
        "ff_h264_videotoolbox_encoder" "VideoToolbox hardware encoder")
elseif(SDK_PLATFORM STREQUAL "windows")
    foreach(input_device IN ITEMS ff_dshow_demuxer ff_gdigrab_demuxer)
        require_registry_symbol("${indev_list}" "${indev_list_content}"
            "${input_device}" "Windows input device")
    endforeach()
    require_registry_symbol("${codec_list}" "${codec_list_content}"
        "ff_h264_mf_encoder" "MediaFoundation hardware encoder")
    if(NOT config_header_content MATCHES "(^|\n)#define CONFIG_D3D11VA 1(\n|$)")
        message(FATAL_ERROR "FFmpeg configure did not enable D3D11VA")
    endif()
    if(SDK_ARCH STREQUAL "x86_64" AND
       NOT config_header_content MATCHES "(^|\n)#define CONFIG_DXVA2 1(\n|$)")
        message(FATAL_ERROR "FFmpeg configure did not enable DXVA2")
    endif()
endif()

foreach(pcm_format IN ITEMS s16le s24le s32le f32le)
    require_registry_symbol(
        "${demuxer_list}" "${demuxer_list_content}"
        "ff_pcm_${pcm_format}_demuxer" "pcm_${pcm_format} demuxer")
    require_registry_symbol(
        "${codec_list}" "${codec_list_content}"
        "ff_pcm_${pcm_format}_decoder" "pcm_${pcm_format} decoder")
    require_registry_symbol(
        "${codec_list}" "${codec_list_content}"
        "ff_pcm_${pcm_format}_encoder" "pcm_${pcm_format} encoder")
endforeach()
