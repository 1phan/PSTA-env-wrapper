# Force-include <cstdint>/<cstddef> into every C++ TU of the PSTA build.
# A couple of PSTA sources include LLVM's <SmallVector.h> before any <cstdint>,
# and newer libstdc++ (>=14) no longer provides uint32_t/uint64_t/size_t
# transitively, so those headers fail to compile. No source edits needed.
add_compile_options("$<$<COMPILE_LANGUAGE:CXX>:SHELL:-include cstdint>"
                    "$<$<COMPILE_LANGUAGE:CXX>:SHELL:-include cstddef>")
