# The library source list from the pinned upstream makefile. Other .cpp files
# are textually included by these files and must not be compiled independently.
set(HIZIP_UNRAR_SOURCES
  rar strlist strfn pathfn smallfn global file filefn filcreat archive arcread
  unicode system crypt crc rawread encname resource match timefn rdwrfn consio
  options errhnd rarvm secpassword rijndael getbits sha1 sha256 blake2s hash
  extinfo extract volume list find unpack headers threadpool rs16 cmddata ui
  largepage filestr scantree dll qopen)
list(TRANSFORM HIZIP_UNRAR_SOURCES PREPEND "${CMAKE_CURRENT_LIST_DIR}/vendor/unrar/")
list(TRANSFORM HIZIP_UNRAR_SOURCES APPEND ".cpp")
add_library(hizip_unrar STATIC ${HIZIP_UNRAR_SOURCES})
set_target_properties(hizip_unrar PROPERTIES POSITION_INDEPENDENT_CODE ON CXX_STANDARD 11)
target_compile_definitions(hizip_unrar PRIVATE RARDLL _FILE_OFFSET_BITS=64 _LARGEFILE_SOURCE)
if(WIN32)
  target_link_libraries(hizip_unrar PRIVATE shlwapi powrprof psapi comctl32 advapi32 ole32 oleaut32 shell32 wbemuuid)
endif()
