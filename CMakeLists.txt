cmake_minimum_required (VERSION 2.8.11)
project (MoonHack_Runner)

macro(runner_add_lib lib)
	foreach(arg IN ITEMS ${ARGN})
		target_link_libraries(${arg} ${${lib}_LIBRARIES})
		target_include_directories(${arg} PUBLIC ${${lib}_INCLUDE_DIRS})
		target_compile_options(${arg} PUBLIC ${${lib}_CFLAGS_OTHER})
	endforeach()
endmacro()

find_package(PkgConfig REQUIRED)
pkg_search_module(ZMQ REQUIRED libzmq)
pkg_search_module(LUAJIT REQUIRED luajit)

add_executable (simple_master simple_master.c)
add_executable (router router.c)
add_executable (worker worker.c)
add_executable (run run.c)

runner_add_lib(ZMQ router worker run)
runner_add_lib(LUAJIT worker)
