cmake_minimum_required(VERSION 3.22.1)
project(addko_lua C)

set(LUA_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/vendor/lua-5.5.1/src")

if(NOT EXISTS "${LUA_ROOT}/lua.h")
    message(FATAL_ERROR "Lua 5.5.1 source is missing. Run: python tools/fetch_lua.py")
endif()

set(LUA_CORE
    ${LUA_ROOT}/lapi.c
    ${LUA_ROOT}/lcode.c
    ${LUA_ROOT}/lctype.c
    ${LUA_ROOT}/ldebug.c
    ${LUA_ROOT}/ldo.c
    ${LUA_ROOT}/ldump.c
    ${LUA_ROOT}/lfunc.c
    ${LUA_ROOT}/lgc.c
    ${LUA_ROOT}/llex.c
    ${LUA_ROOT}/lmem.c
    ${LUA_ROOT}/lobject.c
    ${LUA_ROOT}/lopcodes.c
    ${LUA_ROOT}/lparser.c
    ${LUA_ROOT}/lstate.c
    ${LUA_ROOT}/lstring.c
    ${LUA_ROOT}/ltable.c
    ${LUA_ROOT}/ltm.c
    ${LUA_ROOT}/lundump.c
    ${LUA_ROOT}/lvm.c
    ${LUA_ROOT}/lzio.c
    ${LUA_ROOT}/lauxlib.c
    ${LUA_ROOT}/lbaselib.c
    ${LUA_ROOT}/lcorolib.c
    ${LUA_ROOT}/lmathlib.c
    ${LUA_ROOT}/lstrlib.c
    ${LUA_ROOT}/ltablib.c
    ${LUA_ROOT}/lutf8lib.c
)

add_library(addko_lua SHARED
    addko_lua_bridge.c
    ${LUA_CORE}
)

target_include_directories(addko_lua PRIVATE ${LUA_ROOT})
target_compile_definitions(addko_lua PRIVATE LUA_USE_C89)
target_compile_options(addko_lua PRIVATE -fvisibility=hidden -Wall -Wextra)
