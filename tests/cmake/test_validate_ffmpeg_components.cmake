cmake_minimum_required(VERSION 3.22)

set(repo_root "${CMAKE_CURRENT_LIST_DIR}/../..")
set(validator "${repo_root}/scripts/validate-ffmpeg-components.cmake")
set(test_root "${repo_root}/build/test-validate-ffmpeg-components")

function(write_registry_fixture fixture_root volume_symbol include_alac include_amrnb include_amr_muxer include_aiff_muxer include_pcm_s16be include_wmav2)
    file(MAKE_DIRECTORY
        "${fixture_root}/libavformat"
        "${fixture_root}/libavcodec"
        "${fixture_root}/libavfilter")

    file(WRITE "${fixture_root}/libavformat/demuxer_list.c" "
&ff_pcm_s16le_demuxer,
&ff_pcm_s24le_demuxer,
&ff_pcm_s32le_demuxer,
&ff_pcm_f32le_demuxer,
")
    file(WRITE "${fixture_root}/libavformat/muxer_list.c" "
&ff_pcm_f32le_muxer,
")
    if(include_amr_muxer)
        file(APPEND "${fixture_root}/libavformat/muxer_list.c" "
&ff_amr_muxer,
")
    endif()
    if(include_aiff_muxer)
        file(APPEND "${fixture_root}/libavformat/muxer_list.c" "
&ff_aiff_muxer,
")
    endif()
    file(WRITE "${fixture_root}/libavcodec/codec_list.c" "
&ff_mjpeg_encoder,
&ff_libx264_encoder,
&ff_libx265_encoder,
&ff_pcm_s16le_decoder,
&ff_pcm_s16le_encoder,
&ff_pcm_s24le_decoder,
&ff_pcm_s24le_encoder,
&ff_pcm_s32le_decoder,
&ff_pcm_s32le_encoder,
&ff_pcm_f32le_decoder,
&ff_pcm_f32le_encoder,
")
    if(include_alac)
        file(APPEND "${fixture_root}/libavcodec/codec_list.c" "
&ff_alac_encoder,
")
    endif()
    if(include_amrnb)
        file(APPEND "${fixture_root}/libavcodec/codec_list.c" "
&ff_libopencore_amrnb_encoder,
")
    endif()
    if(include_pcm_s16be)
        file(APPEND "${fixture_root}/libavcodec/codec_list.c" "
&ff_pcm_s16be_encoder,
")
    endif()
    if(include_wmav2)
        file(APPEND "${fixture_root}/libavcodec/codec_list.c" "
&ff_wmav2_encoder,
")
    endif()
    file(WRITE "${fixture_root}/libavfilter/filter_list.c" "
&ff_af_adelay,
&ff_af_aformat,
&ff_af_amix,
&ff_af_aresample,
&ff_af_pan,
&${volume_symbol},
")
endfunction()

function(expect_missing_registry_symbol fixture_root expected_diagnostic)
    execute_process(
        COMMAND "${CMAKE_COMMAND}"
            "-DSOURCE_DIR=${fixture_root}"
            -P "${validator}"
        RESULT_VARIABLE result
        OUTPUT_VARIABLE output
        ERROR_VARIABLE error
    )
    if(result EQUAL 0)
        message(FATAL_ERROR
            "Registry fixture missing ${expected_diagnostic} must fail validation")
    endif()
    set(diagnostics "${output}\n${error}")
    string(FIND "${diagnostics}" "${expected_diagnostic}" diagnostic_offset)
    if(diagnostic_offset EQUAL -1)
        message(FATAL_ERROR
            "Missing registry diagnostic must identify ${expected_diagnostic}:\n${diagnostics}")
    endif()
endfunction()

file(REMOVE_RECURSE "${test_root}")

set(valid_fixture "${test_root}/valid")
write_registry_fixture("${valid_fixture}" "ff_af_volume" TRUE TRUE TRUE TRUE TRUE TRUE)
execute_process(
    COMMAND "${CMAKE_COMMAND}"
        "-DSOURCE_DIR=${valid_fixture}"
        -P "${validator}"
    RESULT_VARIABLE valid_result
    OUTPUT_VARIABLE valid_output
    ERROR_VARIABLE valid_error
)
if(NOT valid_result EQUAL 0)
    message(FATAL_ERROR
        "Exact registry fixture must pass:\n"
        "${valid_output}\n${valid_error}")
endif()

set(missing_alac_fixture "${test_root}/missing-alac")
write_registry_fixture("${missing_alac_fixture}" "ff_af_volume" FALSE TRUE TRUE TRUE TRUE TRUE)
expect_missing_registry_symbol(
    "${missing_alac_fixture}"
    "ff_alac_encoder")

set(missing_amrnb_fixture "${test_root}/missing-amrnb")
write_registry_fixture("${missing_amrnb_fixture}" "ff_af_volume" TRUE FALSE TRUE TRUE TRUE TRUE)
expect_missing_registry_symbol(
    "${missing_amrnb_fixture}"
    "ff_libopencore_amrnb_encoder")

set(missing_amr_muxer_fixture "${test_root}/missing-amr-muxer")
write_registry_fixture("${missing_amr_muxer_fixture}" "ff_af_volume" TRUE TRUE FALSE TRUE TRUE TRUE)
expect_missing_registry_symbol(
    "${missing_amr_muxer_fixture}"
    "ff_amr_muxer")

set(missing_aiff_muxer_fixture "${test_root}/missing-aiff-muxer")
write_registry_fixture("${missing_aiff_muxer_fixture}" "ff_af_volume" TRUE TRUE TRUE FALSE TRUE TRUE)
expect_missing_registry_symbol(
    "${missing_aiff_muxer_fixture}"
    "ff_aiff_muxer")

set(missing_pcm_s16be_fixture "${test_root}/missing-pcm-s16be")
write_registry_fixture("${missing_pcm_s16be_fixture}" "ff_af_volume" TRUE TRUE TRUE TRUE FALSE TRUE)
expect_missing_registry_symbol(
    "${missing_pcm_s16be_fixture}"
    "ff_pcm_s16be_encoder")

set(missing_wmav2_fixture "${test_root}/missing-wmav2")
write_registry_fixture("${missing_wmav2_fixture}" "ff_af_volume" TRUE TRUE TRUE TRUE TRUE FALSE)
expect_missing_registry_symbol(
    "${missing_wmav2_fixture}"
    "ff_wmav2_encoder")

set(substring_fixture "${test_root}/substring")
write_registry_fixture(
    "${substring_fixture}"
    "ff_af_volumedetect"
    TRUE
    TRUE
    TRUE
    TRUE
    TRUE
    TRUE)
execute_process(
    COMMAND "${CMAKE_COMMAND}"
        "-DSOURCE_DIR=${substring_fixture}"
        -P "${validator}"
    RESULT_VARIABLE substring_result
    OUTPUT_VARIABLE substring_output
    ERROR_VARIABLE substring_error
)
if(substring_result EQUAL 0)
    message(FATAL_ERROR
        "ff_af_volumedetect must not satisfy the ff_af_volume requirement")
endif()
set(substring_diagnostics
    "${substring_output}\n${substring_error}")
if(NOT substring_diagnostics MATCHES
        "did not register volume audio filter \\(ff_af_volume\\)")
    message(FATAL_ERROR
        "Substring rejection must identify ff_af_volume:\n"
        "${substring_diagnostics}")
endif()

file(REMOVE_RECURSE "${test_root}")
