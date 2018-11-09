cmake_minimum_required (VERSION 2.8.11)
project (MoonHack_Runner C)

find_program(MY_C_COMPILER NAMES clang-4.0 clang)
find_program(MY_C_LTO_AR NAMES llvm-ar-4.0 llvm-ar)

set(CMAKE_C_COMPILER "${MY_C_COMPILER}")

set(CMAKE_LDFLAGS "-flto -s -fPIC -fPIE -pie -Wl,-z,relro -Wl,-z,now")
set(CMAKE_AR "${MY_C_LTO_AR}")

set(CMAKE_C_FLAGS "-Wall -Werror -O3 -flto -DNDEBUG -D_FORTIFY_SOURCE=2 -march=native -fPIC -fPIE")
set(CMAKE_C_LINK_EXECUTABLE "${MY_C_COMPILER} ${CMAKE_LDFLAGS} <FLAGS> <CMAKE_C_LINK_FLAGS> <LINK_FLAGS> <OBJECTS> -o <TARGET> <LINK_LIBRARIES>")

macro(simple_add_lib lib)
	foreach(arg IN ITEMS ${ARGN})
		target_link_libraries(${arg} ${${lib}_LIBRARIES})
		target_include_directories(${arg} PUBLIC ${${lib}_INCLUDE_DIRS})
		target_compile_options(${arg} PUBLIC ${${lib}_CFLAGS_OTHER})
	endforeach()
endmacro()

find_package(PkgConfig REQUIRED)
pkg_search_module(RABBITMQ REQUIRED librabbitmq)
pkg_search_module(UUID REQUIRED uuid)

set(luajit_dir ${CMAKE_CURRENT_SOURCE_DIR}/LuaJIT)
set(luajit_a ${luajit_dir}/src/libluajit.a)
set(luajit_exe ${luajit_dir}/src/luajit)

add_custom_command(
	OUTPUT ${luajit_a} ${luajit_exe}
	COMMAND env CMAKE_C_COMPILER=${CMAKE_C_COMPILER} CMAKE_AR=${CMAKE_AR} CMAKE_CFLAGS='-fPIC -fPIE -flto' CMAKE_LDFLAGS=${CMAKE_LDFLAGS} make -C ${luajit_dir})

file(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/lua)
file(GLOB_RECURSE LUAFILES src/lua/*.lua)
foreach(in_f IN LISTS LUAFILES)
	file(RELATIVE_PATH out_f ${CMAKE_CURRENT_SOURCE_DIR}/src ${in_f})
	get_filename_component(dir_f ${out_f} DIRECTORY)
	set(out_d ${CMAKE_CURRENT_BINARY_DIR}/${dir_f})
	set(out_f "${out_f}c")
	if (CMAKE_BUILD_TYPE MATCHES "Release")
		add_custom_command(
					OUTPUT ${out_f}
					DEPENDS ${in_f}
					DEPENDS ${luajit_exe}
					COMMAND mkdir -p ${out_d}
					COMMAND ${luajit_exe} -b ${in_f} ${out_f}
					)
	else (CMAKE_BUILD_TYPE MATCHES "Release")
		add_custom_command(
					OUTPUT ${out_f}
					DEPENDS ${in_f}
					COMMAND mkdir -p ${out_d}
					COMMAND cp ${in_f} ${out_f}
					)
	endif (CMAKE_BUILD_TYPE MATCHES "Release")
	list(APPEND LUAFILES_OUT ${out_f})
endforeach()

add_executable (simple_master src/c/simple_master.c)
add_executable (worker src/c/worker.c src/c/rmq_util.c ${LUAFILES_OUT} ${luajit_a})
add_executable (run src/c/run.c src/c/rmq_util.c)

target_include_directories(worker PUBLIC ${luajit_dir}/src)
target_link_libraries(worker ${luajit_a} dl m)

simple_add_lib(RABBITMQ worker run)
simple_add_lib(UUID worker run)
