cmake_minimum_required(VERSION 3.12)
project(ProjectName VERSION 0.1.0 LANGUAGES CXX)

# name of executable, change as desired
set(PROJECT_EXEC "${PROJECT_NAME}_exec")

# ------------------------------------------------------------
# Default to Release build if user did not specify
# ------------------------------------------------------------
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Build type" FORCE)
endif()

# ------------------------------------------------------------
# C++ standard settings
# ------------------------------------------------------------
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON) #allows for tools like clang-tidy to work

# ------------------------------------------------------------
# (Optional) Output directories
# ------------------------------------------------------------
#set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
#set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
#set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)

# ------------------------------------------------------------
# Include paths
# ------------------------------------------------------------
# Automatically collect all cpp files from src/
# Add your include directory (`include/`)
file(GLOB_RECURSE PROJECT_SOURCES ${PROJECT_SOURCE_DIR}/src/*.cpp)

add_executable(${PROJECT_EXEC} ${PROJECT_SOURCES})

target_include_directories(${PROJECT_EXEC}
    PRIVATE
        ${PROJECT_SOURCE_DIR}/include
)

# ------------------------------------------------------------
# Dependencies
# ------------------------------------------------------------
# ===== SYSTEM DEPENDENCIES =====
# Find and link system-wide packages here:
#
#   find_package(Eigen3 REQUIRED)
#   find_package(OpenCV REQUIRED)
#
#   target_include_directories(${PROJECT_EXEC} PRIVATE ${OpenCV_INCLUDE_DIRS})
#   target_link_libraries(${PROJECT_EXEC} PRIVATE Eigen3::Eigen ${OpenCV_LIBRARIES})
#

# ===== LOCAL / THIRD-PARTY DEPENDENCIES =====
# If you include local libraries as subdirectories:
#
#   add_subdirectory(external/mylib)
#   target_link_libraries(${PROJECT_EXEC} PRIVATE mylib)
#

# ===== OPTIONAL DEPENDENCIES =====
# Add optional dependencies behind options:
#
#   option(USE_FAST_MATH "Enable fast math" OFF)
#   if(USE_FAST_MATH)
#       target_compile_definitions(${PROJECT_EXEC} PRIVATE ENABLE_FAST_MATH)
#   endif()
#

# ------------------------------------------------------------
# Additional compile flags (optional)
# ------------------------------------------------------------
target_compile_options(${PROJECT_EXEC} PRIVATE
    -Wall
    -Wextra
    -Wpedantic
)




