cmake_minimum_required(VERSION 3.18)
project(city_katago_embed LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE RelWithDebInfo CACHE STRING "Build type" FORCE)
endif()

set(KATAGO_CPP "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/KataGo/cpp")
set(EIGEN_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../katago_deps/eigen")
set(ZLIB_SRC "${CMAKE_CURRENT_SOURCE_DIR}/../katago_deps/zlib")

if(NOT EXISTS "${KATAGO_CPP}/search/asyncbot.h")
  message(FATAL_ERROR "KataGo sources missing at ${KATAGO_CPP}. Clone tag v1.16.5 into native/third_party/KataGo.")
endif()
if(NOT EXISTS "${EIGEN_ROOT}/Eigen/Core")
  message(FATAL_ERROR "Eigen headers missing at ${EIGEN_ROOT}.")
endif()
if(NOT EXISTS "${ZLIB_SRC}/CMakeLists.txt")
  message(FATAL_ERROR "zlib sources missing at ${ZLIB_SRC}.")
endif()

# --- zlib (static) -----------------------------------------------------------------
set(ZLIB_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(SKIP_INSTALL_ALL ON CACHE BOOL "" FORCE)
add_subdirectory("${ZLIB_SRC}" "${CMAKE_BINARY_DIR}/zlib" EXCLUDE_FROM_ALL)
set(ZLIB_TARGET zlibstatic)

# --- KataGo core (static, Eigen, no CLI/tests) -------------------------------------
set(KATAGO_SOURCES
  ${KATAGO_CPP}/core/global.cpp
  ${KATAGO_CPP}/core/base64.cpp
  ${KATAGO_CPP}/core/bsearch.cpp
  ${KATAGO_CPP}/core/commandloop.cpp
  ${KATAGO_CPP}/core/config_parser.cpp
  ${KATAGO_CPP}/core/datetime.cpp
  ${KATAGO_CPP}/core/elo.cpp
  ${KATAGO_CPP}/core/fancymath.cpp
  ${KATAGO_CPP}/core/fileutils.cpp
  ${KATAGO_CPP}/core/hash.cpp
  ${KATAGO_CPP}/core/logger.cpp
  ${KATAGO_CPP}/core/mainargs.cpp
  ${KATAGO_CPP}/core/makedir.cpp
  ${KATAGO_CPP}/core/md5.cpp
  ${KATAGO_CPP}/core/multithread.cpp
  ${KATAGO_CPP}/core/parallel.cpp
  ${KATAGO_CPP}/core/rand.cpp
  ${KATAGO_CPP}/core/rand_helpers.cpp
  ${KATAGO_CPP}/core/sha2.cpp
  ${KATAGO_CPP}/core/test.cpp
  ${KATAGO_CPP}/core/threadsafecounter.cpp
  ${KATAGO_CPP}/core/threadsafequeue.cpp
  ${KATAGO_CPP}/core/timer.cpp
  ${KATAGO_CPP}/game/board.cpp
  ${KATAGO_CPP}/game/rules.cpp
  ${KATAGO_CPP}/game/boardhistory.cpp
  ${KATAGO_CPP}/game/graphhash.cpp
  ${KATAGO_CPP}/dataio/sgf.cpp
  ${KATAGO_CPP}/dataio/numpywrite.cpp
  ${KATAGO_CPP}/dataio/poswriter.cpp
  ${KATAGO_CPP}/dataio/trainingwrite.cpp
  ${KATAGO_CPP}/dataio/loadmodel.cpp
  ${KATAGO_CPP}/dataio/homedata.cpp
  ${KATAGO_CPP}/dataio/files.cpp
  ${KATAGO_CPP}/neuralnet/nninputs.cpp
  ${KATAGO_CPP}/neuralnet/sgfmetadata.cpp
  ${KATAGO_CPP}/neuralnet/modelversion.cpp
  ${KATAGO_CPP}/neuralnet/nneval.cpp
  ${KATAGO_CPP}/neuralnet/desc.cpp
  ${KATAGO_CPP}/neuralnet/eigenbackend.cpp
  ${KATAGO_CPP}/search/timecontrols.cpp
  ${KATAGO_CPP}/search/searchparams.cpp
  ${KATAGO_CPP}/search/mutexpool.cpp
  ${KATAGO_CPP}/search/search.cpp
  ${KATAGO_CPP}/search/searchnode.cpp
  ${KATAGO_CPP}/search/searchresults.cpp
  ${KATAGO_CPP}/search/searchhelpers.cpp
  ${KATAGO_CPP}/search/searchexplorehelpers.cpp
  ${KATAGO_CPP}/search/searchmirror.cpp
  ${KATAGO_CPP}/search/searchmultithreadhelpers.cpp
  ${KATAGO_CPP}/search/searchnnhelpers.cpp
  ${KATAGO_CPP}/search/searchtimehelpers.cpp
  ${KATAGO_CPP}/search/searchupdatehelpers.cpp
  ${KATAGO_CPP}/search/asyncbot.cpp
  ${KATAGO_CPP}/search/distributiontable.cpp
  ${KATAGO_CPP}/search/localpattern.cpp
  ${KATAGO_CPP}/search/searchnodetable.cpp
  ${KATAGO_CPP}/search/subtreevaluebiastable.cpp
  ${KATAGO_CPP}/search/evalcache.cpp
  ${KATAGO_CPP}/search/patternbonustable.cpp
  ${KATAGO_CPP}/search/analysisdata.cpp
  ${KATAGO_CPP}/search/reportedsearchvalues.cpp
  ${KATAGO_CPP}/program/gtpconfig.cpp
  ${KATAGO_CPP}/program/setup.cpp
  ${KATAGO_CPP}/program/playutils.cpp
  ${KATAGO_CPP}/program/playsettings.cpp
  ${KATAGO_CPP}/program/play.cpp
)

add_library(katago_core STATIC ${KATAGO_SOURCES})
target_include_directories(katago_core PUBLIC
  "${KATAGO_CPP}"
  "${KATAGO_CPP}/external"
  SYSTEM "${KATAGO_CPP}/external/tclap-1.2.5/include"
  SYSTEM "${KATAGO_CPP}/external/filesystem-1.5.8/include"
  SYSTEM "${EIGEN_ROOT}"
)
target_compile_definitions(katago_core PUBLIC
  USE_EIGEN_BACKEND
  NO_GIT_REVISION
  NO_LIBZIP
)
if(WIN32)
  target_compile_definitions(katago_core PUBLIC
    NOMINMAX
    BYTE_ORDER=1234
    LITTLE_ENDIAN=1234
    BIG_ENDIAN=4321
  )
  target_link_libraries(katago_core PUBLIC ws2_32)
endif()
if(MSVC)
  target_compile_definitions(katago_core PUBLIC _CRT_SECURE_NO_WARNINGS)
  target_compile_options(katago_core PRIVATE /bigobj /wd4244 /wd4267 /wd4018 /wd4305 /wd4996)
endif()
target_include_directories(katago_core PUBLIC $<TARGET_PROPERTY:${ZLIB_TARGET},INTERFACE_INCLUDE_DIRECTORIES>)
# zlib headers live in the source tree and the build dir (zconf.h).
target_include_directories(katago_core PUBLIC "${ZLIB_SRC}" "${CMAKE_BINARY_DIR}/zlib")
target_link_libraries(katago_core PUBLIC ${ZLIB_TARGET})

# --- C ABI shared library ----------------------------------------------------------
add_library(city_katago_native SHARED
  src/katago_c_api.cpp
)
target_include_directories(city_katago_native PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
# Resolve KataGo includes relative to cpp/ (matches upstream #include "../core/...")
target_include_directories(city_katago_native PRIVATE
  "${KATAGO_CPP}/program"
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_compile_definitions(city_katago_native PRIVATE KATAGO_EMBED_EXPORTS)
target_link_libraries(city_katago_native PRIVATE katago_core)
if(MSVC)
  target_compile_options(city_katago_native PRIVATE /bigobj)
  # Ensure search/AsyncBot thread stack headroom when loaded into Godot.
  target_link_options(city_katago_native PRIVATE "/STACK:8388608")
endif()

install(TARGETS city_katago_native
  RUNTIME DESTINATION bin
  LIBRARY DESTINATION lib
  ARCHIVE DESTINATION lib
)
install(FILES include/katago_c_api.h DESTINATION include)
