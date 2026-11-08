vcpkg_download_distfile(ARCHIVE
    URLS "https://github.com/sekrit-twc/zimg/archive/refs/tags/release-3.0.5.tar.gz"
    FILENAME "zimg-release-3.0.5.tar.gz"
    SHA512 85467ec9fcf81ea1ae3489b539ce751772a1dab6c6159928b3c5aa9f1cb029f0570b4624a254d4620886f3376fbf80f9bb829a88c3fe543f99f38947951dc500
)
vcpkg_extract_source_archive_ex(OUT_SOURCE_PATH SOURCE_PATH ARCHIVE "${ARCHIVE}")
file(COPY "${CMAKE_CURRENT_LIST_DIR}/CMakeLists.txt" DESTINATION "${SOURCE_PATH}")
vcpkg_cmake_configure(SOURCE_PATH "${SOURCE_PATH}" OPTIONS -DBUILD_SHARED_LIBS=ON)
vcpkg_cmake_install()
vcpkg_copy_pdbs()
file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib/pkgconfig")
file(WRITE "${CURRENT_PACKAGES_DIR}/lib/pkgconfig/zimg.pc"
    "prefix=\${pcfiledir}/../..\n"
    "libdir=\${prefix}/lib\n"
    "includedir=\${prefix}/include\n"
    "Name: zimg\nDescription: Image scaling and colorspace conversion\n"
    "Version: 3.0.5\nLibs: -L\${libdir} -lzimg\nCflags: -I\${includedir}\n")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include" "${CURRENT_PACKAGES_DIR}/debug/share")
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
