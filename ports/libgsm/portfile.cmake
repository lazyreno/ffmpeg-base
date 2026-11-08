vcpkg_download_distfile(ARCHIVE
    URLS "https://www.quut.com/gsm/gsm-1.0.22.tar.gz"
    FILENAME "gsm-1.0.22.tar.gz"
    SHA512 f4284f096ed4d606ddece5c1b28edb63feacc26a0b664f1350c040dbf50113d27bedfd9896bf1620cb4fc3a6c8f6a5244955a6c625ded833dcee607c63c97dd2
)
vcpkg_extract_source_archive_ex(OUT_SOURCE_PATH SOURCE_PATH ARCHIVE "${ARCHIVE}")
file(COPY "${CMAKE_CURRENT_LIST_DIR}/CMakeLists.txt" DESTINATION "${SOURCE_PATH}")
vcpkg_cmake_configure(SOURCE_PATH "${SOURCE_PATH}" OPTIONS -DBUILD_SHARED_LIBS=ON)
vcpkg_cmake_install()
vcpkg_copy_pdbs()
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include" "${CURRENT_PACKAGES_DIR}/debug/share")
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYRIGHT")
