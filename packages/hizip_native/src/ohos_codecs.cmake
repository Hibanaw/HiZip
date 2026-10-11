# Compile optional codecs for the target, never link host macOS libraries.
include(FetchContent)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(XZ_NLS OFF CACHE BOOL "" FORCE)
foreach(tool XZ XZDEC LZMADEC LZMAINFO)
  set(XZ_TOOL_${tool} OFF CACHE BOOL "" FORCE)
endforeach()
FetchContent_Declare(hizip_xz
  URL "${CMAKE_CURRENT_LIST_DIR}/../third_party/xz-5.8.4.tar.xz"
  URL_HASH SHA256=4ce24038fd4221e0d13bc1a2de7a4db56e90b92b3bf75321f6c14be73f65de4b)
FetchContent_MakeAvailable(hizip_xz)

set(ENABLE_PROGRAMS OFF CACHE BOOL "" FORCE)
set(ENABLE_TESTING OFF CACHE BOOL "" FORCE)
# The HarmonyOS SDK supplies a gcc-toolchain argument that Clang does not use.
set(MBEDTLS_FATAL_WARNINGS OFF CACHE BOOL "" FORCE)
set(USE_SHARED_MBEDTLS_LIBRARY OFF CACHE BOOL "" FORCE)
set(USE_STATIC_MBEDTLS_LIBRARY ON CACHE BOOL "" FORCE)
FetchContent_Declare(hizip_mbedtls
  URL "${CMAKE_CURRENT_LIST_DIR}/../third_party/mbedtls-3.6.7.tar.bz2"
  URL_HASH SHA256=a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6)
FetchContent_MakeAvailable(hizip_mbedtls)
set_target_properties(mbedcrypto PROPERTIES POSITION_INDEPENDENT_CODE ON)

FetchContent_Declare(hizip_bzip2
  URL "${CMAKE_CURRENT_LIST_DIR}/../third_party/bzip2-1.0.8.tar.gz"
  URL_HASH SHA256=ab5a03176ee106d3f0fa90e381da478ddae405918153cca248e682cd0c4a2269)
FetchContent_GetProperties(hizip_bzip2)
if(NOT hizip_bzip2_POPULATED)
  FetchContent_Populate(hizip_bzip2)
endif()
add_library(hizip_bz2 STATIC
  ${hizip_bzip2_SOURCE_DIR}/blocksort.c ${hizip_bzip2_SOURCE_DIR}/huffman.c
  ${hizip_bzip2_SOURCE_DIR}/crctable.c ${hizip_bzip2_SOURCE_DIR}/randtable.c
  ${hizip_bzip2_SOURCE_DIR}/compress.c ${hizip_bzip2_SOURCE_DIR}/decompress.c
  ${hizip_bzip2_SOURCE_DIR}/bzlib.c)
target_include_directories(hizip_bz2 PUBLIC "${hizip_bzip2_SOURCE_DIR}")
set_target_properties(hizip_bz2 PROPERTIES POSITION_INDEPENDENT_CODE ON)
set_target_properties(liblzma PROPERTIES POSITION_INDEPENDENT_CODE ON)

# Expose in-tree targets to libarchive's find_package calls. Its configure-time
# link probes may be unavailable until these targets build; the codecs themselves
# are verified by round trips on the emulator.
set(CMAKE_FIND_PACKAGE_PREFER_CONFIG TRUE)
set(LibLZMA_DIR "${CMAKE_CURRENT_BINARY_DIR}/hizip-codec-config")
set(BZip2_DIR "${LibLZMA_DIR}")
set(MbedTLS_DIR "${LibLZMA_DIR}")
file(MAKE_DIRECTORY "${LibLZMA_DIR}")
file(WRITE "${LibLZMA_DIR}/LibLZMAConfig.cmake"
  "set(LIBLZMA_FOUND TRUE)\nset(LIBLZMA_INCLUDE_DIR \"${hizip_xz_SOURCE_DIR}/src/liblzma/api\")\nset(LIBLZMA_INCLUDE_DIRS \"${hizip_xz_SOURCE_DIR}/src/liblzma/api\")\nset(LIBLZMA_LIBRARIES liblzma)\n")
file(WRITE "${BZip2_DIR}/BZip2Config.cmake"
  "set(BZIP2_FOUND TRUE)\nset(BZIP2_INCLUDE_DIR \"${hizip_bzip2_SOURCE_DIR}\")\nset(BZIP2_LIBRARIES hizip_bz2)\n")
file(WRITE "${MbedTLS_DIR}/MbedTLSConfig.cmake"
  "set(MBEDTLS_FOUND TRUE)\nset(MBEDTLS_INCLUDE_DIRS \"${hizip_mbedtls_SOURCE_DIR}/include\")\nset(MBEDCRYPTO_LIBRARY mbedcrypto)\n")
