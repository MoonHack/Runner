cmake_minimum_required (VERSION 2.8.11)
project (MoonHack_Runner)

macro(simple_add_lib lib)
	foreach(arg IN ITEMS ${ARGN})
		target_link_libraries(${arg} ${${lib}_LIBRARIES})
		target_include_directories(${arg} PUBLIC ${${lib}_INCLUDE_DIRS})
		target_compile_options(${arg} PUBLIC ${${lib}_CFLAGS_OTHER})
	endforeach()
endmacro()

find_package(PkgConfig REQUIRED)
pkg_search_module(RABBITMQ REQUIRED librabbitmq)
pkg_search_module(LUAJIT REQUIRED luajit)

file(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/lua)
file(GLOB_RECURSE LUAFILES lua *.lua)
foreach(in_f IN LISTS LUAFILES)
	file(RELATIVE_PATH out_f ${CMAKE_CURRENT_SOURCE_DIR} ${in_f})
	get_filename_component(dir_f ${out_f} DIRECTORY)
	set(out_d ${CMAKE_CURRENT_BINARY_DIR}/${dir_f})
	set(out_f "${out_f}c")
	add_custom_command(
				OUTPUT ${out_f}
				DEPENDS ${in_f}
				COMMAND mkdir -p ${out_d}
				#COMMAND cp ${in_f} ${out_f}
				COMMAND luajit -b ${in_f} ${out_f}
				)
	list(APPEND LUAFILES_OUT ${out_f})
endforeach()

add_executable (simple_master simple_master.c)
add_executable (worker worker.c ${LUAFILES_OUT})
add_executable (run run.c)

#simple_add_lib(RABBITMQ run)
simple_add_lib(RABBITMQ worker run)
simple_add_lib(LUAJIT worker)
