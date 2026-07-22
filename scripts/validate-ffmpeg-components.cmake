cmake_minimum_required(VERSION 3.21)

if(NOT DEFINED SOURCE_DIR OR SOURCE_DIR STREQUAL "")
    message(FATAL_ERROR "SOURCE_DIR is required")
endif()

function(require_registry_symbol registry_path registry_content symbol description)
    if(NOT "${registry_content}" MATCHES "${symbol}")
        message(FATAL_ERROR
            "FFmpeg configure did not register ${description} (${symbol}) in ${registry_path}")
    endif()
endfunction()

set(demuxer_list "${SOURCE_DIR}/libavformat/demuxer_list.c")
set(muxer_list "${SOURCE_DIR}/libavformat/muxer_list.c")
set(codec_list "${SOURCE_DIR}/libavcodec/codec_list.c")

foreach(registry_path IN ITEMS "${demuxer_list}" "${muxer_list}" "${codec_list}")
    if(NOT EXISTS "${registry_path}")
        message(FATAL_ERROR
            "FFmpeg generated registry was not found after configure: ${registry_path}")
    endif()
endforeach()

file(READ "${demuxer_list}" demuxer_list_content)
file(READ "${muxer_list}" muxer_list_content)
file(READ "${codec_list}" codec_list_content)

require_registry_symbol(
    "${muxer_list}" "${muxer_list_content}"
    "ff_pcm_f32le_muxer" "pcm_f32le muxer")
require_registry_symbol(
    "${codec_list}" "${codec_list_content}"
    "ff_mjpeg_encoder" "MJPEG encoder")

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
