cmake_minimum_required(VERSION 3.22)

set(repo_root "${CMAKE_CURRENT_LIST_DIR}/../..")
set(validator "${repo_root}/scripts/validate-ffmpeg-components.cmake")
set(test_root "${repo_root}/build/test-validate-ffmpeg-components")

function(write_registry_fixture fixture_root volume_symbol)
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
    file(WRITE "${fixture_root}/libavfilter/filter_list.c" "
&ff_af_adelay,
&ff_af_aformat,
&ff_af_amix,
&ff_af_aresample,
&ff_af_pan,
&${volume_symbol},
")
endfunction()

file(REMOVE_RECURSE "${test_root}")

set(valid_fixture "${test_root}/valid")
write_registry_fixture("${valid_fixture}" "ff_af_volume")
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

set(substring_fixture "${test_root}/substring")
write_registry_fixture(
    "${substring_fixture}"
    "ff_af_volumedetect")
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
