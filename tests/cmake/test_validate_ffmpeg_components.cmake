cmake_minimum_required(VERSION 3.21)
set(root "${CMAKE_CURRENT_LIST_DIR}/../..")
set(validator "${root}/scripts/validate-ffmpeg-components.cmake")
set(fixture "${root}/build/test-validate-ffmpeg-components")
file(REMOVE_RECURSE "${fixture}")
file(MAKE_DIRECTORY "${fixture}/libavformat" "${fixture}/libavcodec" "${fixture}/libavfilter" "${fixture}/libavdevice")

function(write_symbols path)
    file(WRITE "${fixture}/${path}" "")
    foreach(symbol IN LISTS ARGN)
        file(APPEND "${fixture}/${path}" "&${symbol},\n")
    endforeach()
endfunction()

write_symbols(libavformat/demuxer_list.c
    ff_pcm_s16le_demuxer ff_pcm_s24le_demuxer ff_pcm_s32le_demuxer ff_pcm_f32le_demuxer
    ff_libopenmpt_demuxer ff_libgme_demuxer)
write_symbols(libavformat/muxer_list.c ff_pcm_f32le_muxer ff_amr_muxer ff_aiff_muxer)
write_symbols(libavcodec/codec_list.c
    ff_mjpeg_encoder ff_rawvideo_decoder ff_rawvideo_encoder ff_prores_decoder
    ff_prores_ks_encoder ff_adpcm_ima_wav_decoder ff_libx264_encoder ff_libx265_encoder
    ff_pcm_s16le_decoder ff_pcm_s16le_encoder ff_pcm_s24le_decoder ff_pcm_s24le_encoder
    ff_pcm_s32le_decoder ff_pcm_s32le_encoder ff_pcm_f32le_decoder ff_pcm_f32le_encoder
    ff_alac_encoder ff_libopencore_amrnb_encoder ff_pcm_s16be_encoder ff_wmav2_encoder
    ff_libvpx_vp9_encoder ff_libdav1d_decoder ff_libgsm_decoder ff_libgsm_encoder
    ff_libjxl_encoder ff_libopenjpeg_encoder ff_libopencore_amrwb_decoder
    ff_libspeex_encoder ff_libsvtav1_encoder ff_libvo_amrwbenc_encoder
    ff_libwebp_encoder ff_h264_videotoolbox_encoder ff_h264_mf_encoder)
write_symbols(libavfilter/filter_list.c
    ff_af_adelay ff_af_afftdn ff_af_aformat ff_af_amix ff_af_aresample
    ff_af_pan ff_af_volume ff_af_rubberband ff_vf_zscale ff_vf_subtitles ff_vf_drawtext)
write_symbols(libavdevice/indev_list.c
    ff_lavfi_demuxer ff_avfoundation_demuxer ff_dshow_demuxer ff_gdigrab_demuxer)
write_symbols(libavdevice/outdev_list.c ff_audiotoolbox_muxer)
file(WRITE "${fixture}/config.h" "#define CONFIG_D3D11VA 1\n#define CONFIG_DXVA2 1\n")

function(check platform arch expected_result expected_message)
    execute_process(COMMAND "${CMAKE_COMMAND}" "-DSOURCE_DIR=${fixture}"
        "-DSDK_PLATFORM=${platform}" "-DSDK_ARCH=${arch}" -P "${validator}"
        RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
    if(expected_result STREQUAL "pass" AND NOT result EQUAL 0)
        message(FATAL_ERROR "${platform}/${arch} fixture failed:\n${output}\n${error}")
    elseif(expected_result STREQUAL "fail")
        if(result EQUAL 0 OR NOT "${output}${error}" MATCHES "${expected_message}")
            message(FATAL_ERROR "Expected ${expected_message} failure:\n${output}\n${error}")
        endif()
    endif()
endfunction()

check(macos arm64 pass "")
check(windows x86_64 pass "")
check(windows arm64 pass "")
file(READ "${fixture}/libavcodec/codec_list.c" codecs)
string(REPLACE "&ff_prores_decoder,\n" "" codecs "${codecs}")
file(WRITE "${fixture}/libavcodec/codec_list.c" "${codecs}")
check(macos arm64 fail "ff_prores_decoder")
file(REMOVE_RECURSE "${fixture}")
