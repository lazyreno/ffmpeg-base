cmake_minimum_required(VERSION 3.21)

if(NOT DEFINED SOURCE_DIR OR SOURCE_DIR STREQUAL "")
    message(FATAL_ERROR "SOURCE_DIR is required")
endif()

set(muxer_list "${SOURCE_DIR}/libavformat/muxer_list.c")
if(NOT EXISTS "${muxer_list}")
    message(FATAL_ERROR
        "FFmpeg generated muxer registry was not found after configure: ${muxer_list}")
endif()

file(READ "${muxer_list}" muxer_list_content)
if(NOT muxer_list_content MATCHES "ff_pcm_f32le_muxer")
    message(FATAL_ERROR
        "FFmpeg configure did not register the required pcm_f32le muxer in ${muxer_list}")
endif()
