cmake_minimum_required(VERSION 3.17)
project(voxelcore LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(GODOTCPP_TARGET template_release CACHE STRING "" FORCE)
add_subdirectory(godot-cpp)
add_library(voxelcore SHARED src/register_types.cpp src/voxel_mesher.cpp)
target_link_libraries(voxelcore PRIVATE godot::cpp)
if(WIN32)
	set(VC_NAME "voxelcore.windows.template_release.x86_64")
else()
	set(VC_NAME "voxelcore.linux.template_release.x86_64")
endif()
set(VC_OUT "${CMAKE_SOURCE_DIR}/../game/bin")
set_target_properties(voxelcore PROPERTIES
	PREFIX "lib"
	OUTPUT_NAME "${VC_NAME}"
	LIBRARY_OUTPUT_DIRECTORY "${VC_OUT}"
	LIBRARY_OUTPUT_DIRECTORY_RELEASE "${VC_OUT}"
	RUNTIME_OUTPUT_DIRECTORY "${VC_OUT}"
	RUNTIME_OUTPUT_DIRECTORY_RELEASE "${VC_OUT}")
