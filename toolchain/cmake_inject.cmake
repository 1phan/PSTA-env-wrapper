# Injected at the top of the SVF/PSTA CMake projects via
# CMAKE_PROJECT_TOP_LEVEL_INCLUDES. The prebuilt LLVM's exported LLVMSupport
# target lists Terminfo::terminfo and zstd::libzstd_shared in its link interface,
# but LLVMConfig does not always recreate those imported targets. Define them
# ourselves so find_package(LLVM) succeeds. The build scripts pass -DWRAP_*_LIB
# (located via ldconfig); we fall back to find_library otherwise.
function(_wrap_import tgt cachevar)
  if(TARGET ${tgt})
    return()
  endif()
  set(_lib "")
  if(DEFINED ${cachevar} AND EXISTS "${${cachevar}}")
    set(_lib "${${cachevar}}")
  else()
    find_library(_wrap_found NAMES ${ARGN})
    if(_wrap_found)
      set(_lib "${_wrap_found}")
    endif()
    unset(_wrap_found CACHE)
  endif()
  if(_lib)
    add_library(${tgt} UNKNOWN IMPORTED GLOBAL)
    set_target_properties(${tgt} PROPERTIES IMPORTED_LOCATION "${_lib}")
    message(STATUS "wrapper: ${tgt} -> ${_lib}")
  else()
    message(WARNING "wrapper: could not locate a library for ${tgt}; LLVM link may fail")
  endif()
endfunction()

_wrap_import(Terminfo::terminfo   WRAP_TINFO_LIB tinfo tinfow ncurses ncursesw)
_wrap_import(zstd::libzstd_shared WRAP_ZSTD_LIB  zstd)
