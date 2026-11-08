vcpkg_download_distfile(ARCHIVE
    URLS "https://deb.debian.org/debian/pool/main/v/vo-amrwbenc/vo-amrwbenc_0.1.3.orig.tar.gz"
    FILENAME "vo-amrwbenc_0.1.3.orig.tar.gz"
    SHA512 5f132f798f00ec2c0619700ab1ce456897792b45631af4b538c866636af9c9de5600af5f79040c41c3dc69c17cf4be7032139a9518a46a4276431e091f3dd6a9
)
vcpkg_extract_source_archive_ex(OUT_SOURCE_PATH SOURCE_PATH ARCHIVE "${ARCHIVE}")
if(VCPKG_TARGET_IS_WINDOWS)
    file(COPY "${CMAKE_CURRENT_LIST_DIR}/CMakeLists.txt" DESTINATION "${SOURCE_PATH}")
    vcpkg_cmake_configure(SOURCE_PATH "${SOURCE_PATH}" OPTIONS -DBUILD_SHARED_LIBS=ON)
    vcpkg_cmake_install()
    vcpkg_copy_pdbs()
    file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib/pkgconfig")
    file(WRITE "${CURRENT_PACKAGES_DIR}/lib/pkgconfig/vo-amrwbenc.pc"
        "prefix=\${pcfiledir}/../..\n"
        "libdir=\${prefix}/lib\n"
        "includedir=\${prefix}/include\n"
        "Name: VisualOn AMR-WB encoder\nDescription: Adaptive Multi-Rate Wideband speech codec library\n"
        "Version: 0.1.3\nLibs: -L\${libdir} -lvo-amrwbenc\nCflags: -I\${includedir}\n")
    file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
else()
    vcpkg_configure_make(SOURCE_PATH "${SOURCE_PATH}" OPTIONS --disable-examples --disable-dependency-tracking)
    vcpkg_install_make()
endif()
vcpkg_fixup_pkgconfig()
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
