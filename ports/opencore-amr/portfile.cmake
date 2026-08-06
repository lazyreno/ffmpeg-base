vcpkg_download_distfile(ARCHIVE
    URLS "https://deb.debian.org/debian/pool/main/o/opencore-amr/opencore-amr_0.1.6.orig.tar.gz"
    FILENAME "opencore-amr_0.1.6.orig.tar.gz"
    SHA512 8955169954b09d2d5e2190888602c75771b72455290db131ab7f40b587df32ea6a60f205126b09193b90064d0fd82b7d678032e2b4c684189788e175b83d0aa7
)

vcpkg_extract_source_archive_ex(
    OUT_SOURCE_PATH SOURCE_PATH
    ARCHIVE "${ARCHIVE}"
)

vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-examples
        --disable-dependency-tracking
)
vcpkg_install_make()
vcpkg_fixup_pkgconfig()
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
