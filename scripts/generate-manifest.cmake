cmake_minimum_required(VERSION 3.21)

foreach(required_var IN ITEMS
        TEMPLATE_FILE
        OUTPUT_FILE
        SDK_VERSION
        FFMPEG_VERSION
        SDK_PLATFORM
        SDK_ARCH
        SDK_COMPILER
        VCPKG_BASELINE
        VCPKG_TRIPLET
        FFMPEG_SOURCE_URL
        FFMPEG_SOURCE_SHA256
        SDK_FEATURES_JSON
        LICENSE_MODE
        BUILD_ID
        CREATED_AT)
    if(NOT DEFINED ${required_var} OR "${${required_var}}" STREQUAL "")
        message(FATAL_ERROR "${required_var} is required to generate manifest.json")
    endif()
endforeach()

if(NOT EXISTS "${TEMPLATE_FILE}")
    message(FATAL_ERROR "Manifest template not found: ${TEMPLATE_FILE}")
endif()

get_filename_component(output_dir "${OUTPUT_FILE}" DIRECTORY)
file(MAKE_DIRECTORY "${output_dir}")

configure_file("${TEMPLATE_FILE}" "${OUTPUT_FILE}" @ONLY)
