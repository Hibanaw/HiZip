cmake_minimum_required(VERSION 3.14)

# Windows 11 context-menu handler, loaded by Explorer through the sparse
# package registered from Settings. Lives next to hizip.exe.
add_library(hizip_shell SHARED hizip_shell.cpp hizip_shell.def)
target_compile_features(hizip_shell PUBLIC cxx_std_17)
target_compile_options(hizip_shell PRIVATE /W4 /WX /EHsc /utf-8)
target_compile_definitions(hizip_shell PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
target_link_libraries(hizip_shell PRIVATE shlwapi.lib ole32.lib shell32.lib)
