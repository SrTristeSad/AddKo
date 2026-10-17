#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

#if defined(__GNUC__)
#define ADDKO_EXPORT __attribute__((visibility("default")))
#else
#define ADDKO_EXPORT
#endif

#define ADDKO_MEMORY_LIMIT (8u * 1024u * 1024u)
#define ADDKO_HOOK_GRANULARITY 1000
#define ADDKO_HOOK_TICKS 200
#define ADDKO_MAX_PLUGIN_ROOT 4096
#define ADDKO_MAX_MODULE_NAME 512
#define ADDKO_LOADED_MODULES "addko.loaded.modules"

typedef struct AddKoLuaRuntime {
    lua_State *state;
    size_t memory_used;
    size_t memory_limit;
    int instruction_ticks;
    char *plugin_root;
} AddKoLuaRuntime;

static void *addko_allocator(void *ud, void *ptr, size_t osize, size_t nsize) {
    AddKoLuaRuntime *runtime = (AddKoLuaRuntime *)ud;

    if (nsize == 0) {
        if (ptr != NULL) {
            free(ptr);
            if (osize <= runtime->memory_used) {
                runtime->memory_used -= osize;
            } else {
                runtime->memory_used = 0;
            }
        }
        return NULL;
    }

    if (ptr == NULL) {
        if (runtime->memory_used > runtime->memory_limit ||
            nsize > runtime->memory_limit - runtime->memory_used) {
            return NULL;
        }
        void *created = malloc(nsize);
        if (created != NULL) {
            runtime->memory_used += nsize;
        }
        return created;
    }

    if (nsize > osize) {
        const size_t growth = nsize - osize;
        if (runtime->memory_used > runtime->memory_limit ||
            growth > runtime->memory_limit - runtime->memory_used) {
            return NULL;
        }
    }

    void *resized = realloc(ptr, nsize);
    if (resized != NULL) {
        if (nsize >= osize) {
            runtime->memory_used += nsize - osize;
        } else {
            const size_t shrink = osize - nsize;
            runtime->memory_used = shrink <= runtime->memory_used
                ? runtime->memory_used - shrink
                : 0;
        }
    }
    return resized;
}

static AddKoLuaRuntime *runtime_from_state(lua_State *L) {
    void *ud = NULL;
    (void)lua_getallocf(L, &ud);
    return (AddKoLuaRuntime *)ud;
}

static void instruction_hook(lua_State *L, lua_Debug *ar) {
    (void)ar;
    AddKoLuaRuntime *runtime = runtime_from_state(L);
    runtime->instruction_ticks -= 1;
    if (runtime->instruction_ticks <= 0) {
        luaL_error(L, "instruction limit exceeded");
    }
}

static void remove_global(lua_State *L, const char *name) {
    lua_pushnil(L);
    lua_setglobal(L, name);
}

static int is_safe_module_name(const char *name) {
    size_t i;
    size_t length;

    if (name == NULL) {
        return 0;
    }

    length = strlen(name);
    if (length == 0 || length > ADDKO_MAX_MODULE_NAME) {
        return 0;
    }
    if (name[0] == '/' || name[0] == '\\' || strstr(name, "..") != NULL) {
        return 0;
    }

    for (i = 0; i < length; i += 1) {
        const char c = name[i];
        const int alpha = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
        const int digit = c >= '0' && c <= '9';
        if (!alpha && !digit && c != '_' && c != '-' && c != '.' && c != '/') {
            return 0;
        }
    }
    return 1;
}

static int module_path(
    AddKoLuaRuntime *runtime,
    const char *module,
    char *output,
    size_t output_size
) {
    char relative[ADDKO_MAX_MODULE_NAME + 5];
    size_t i;
    size_t length;
    int written;

    if (runtime == NULL || runtime->plugin_root == NULL ||
        !is_safe_module_name(module)) {
        return 0;
    }

    length = strlen(module);
    for (i = 0; i < length; i += 1) {
        relative[i] = module[i] == '.' ? '/' : module[i];
    }
    relative[length] = '\0';

    written = snprintf(
        output,
        output_size,
        "%s/%s.lua",
        runtime->plugin_root,
        relative
    );
    if (written < 0 || (size_t)written >= output_size) {
        return 0;
    }
    return 1;
}

static void push_loaded_modules(lua_State *L) {
    lua_getfield(L, LUA_REGISTRYINDEX, ADDKO_LOADED_MODULES);
    if (lua_istable(L, -1)) {
        return;
    }

    lua_pop(L, 1);
    lua_newtable(L);
    lua_pushvalue(L, -1);
    lua_setfield(L, LUA_REGISTRYINDEX, ADDKO_LOADED_MODULES);
}

static int addko_require(lua_State *L) {
    AddKoLuaRuntime *runtime = runtime_from_state(L);
    const char *module = luaL_checkstring(L, 1);
    char path[ADDKO_MAX_PLUGIN_ROOT + ADDKO_MAX_MODULE_NAME + 8];
    int status;

    if (!module_path(runtime, module, path, sizeof(path))) {
        return luaL_error(L, "unsafe or invalid module name: %s", module);
    }

    push_loaded_modules(L);
    lua_getfield(L, -1, module);
    if (!lua_isnil(L, -1)) {
        lua_remove(L, -2);
        return 1;
    }
    lua_pop(L, 1);

    status = luaL_loadfilex(L, path, NULL);
    if (status != LUA_OK) {
        return lua_error(L);
    }

    status = lua_pcall(L, 0, 1, 0);
    if (status != LUA_OK) {
        return lua_error(L);
    }

    if (lua_isnil(L, -1)) {
        lua_pop(L, 1);
        lua_pushboolean(L, 1);
    }

    lua_pushvalue(L, -1);
    lua_setfield(L, -3, module);
    lua_remove(L, -2);
    return 1;
}

static void open_safe_libraries(lua_State *L) {
    luaL_requiref(L, "_G", luaopen_base, 1);
    lua_pop(L, 1);

    remove_global(L, "dofile");
    remove_global(L, "loadfile");
    remove_global(L, "collectgarbage");

    lua_pushcfunction(L, addko_require);
    lua_setglobal(L, "require");

    luaL_requiref(L, LUA_COLIBNAME, luaopen_coroutine, 1);
    lua_pop(L, 1);
    luaL_requiref(L, LUA_TABLIBNAME, luaopen_table, 1);
    lua_pop(L, 1);
    luaL_requiref(L, LUA_STRLIBNAME, luaopen_string, 1);
    lua_pop(L, 1);
    luaL_requiref(L, LUA_MATHLIBNAME, luaopen_math, 1);
    lua_pop(L, 1);
    luaL_requiref(L, LUA_UTF8LIBNAME, luaopen_utf8, 1);
    lua_pop(L, 1);
}

static void copy_message(char *output, size_t output_size, const char *message) {
    if (output == NULL || output_size == 0) {
        return;
    }
    if (message == NULL) {
        message = "";
    }
    snprintf(output, output_size, "%s", message);
    output[output_size - 1] = '\0';
}

ADDKO_EXPORT const char *addko_lua_version(void) {
    return LUA_RELEASE;
}

ADDKO_EXPORT AddKoLuaRuntime *addko_lua_create(void) {
    AddKoLuaRuntime *runtime = (AddKoLuaRuntime *)calloc(1, sizeof(AddKoLuaRuntime));
    if (runtime == NULL) {
        return NULL;
    }

    runtime->memory_limit = ADDKO_MEMORY_LIMIT;
    runtime->state = lua_newstate(
        addko_allocator,
        runtime,
        luaL_makeseed(NULL)
    );
    if (runtime->state == NULL) {
        free(runtime);
        return NULL;
    }

    open_safe_libraries(runtime->state);
    return runtime;
}

ADDKO_EXPORT int addko_lua_set_plugin_root(
    AddKoLuaRuntime *runtime,
    const char *plugin_root
) {
    size_t length;
    char *copy;

    if (runtime == NULL || runtime->state == NULL || plugin_root == NULL) {
        return 1;
    }

    length = strlen(plugin_root);
    if (length == 0 || length > ADDKO_MAX_PLUGIN_ROOT) {
        return 2;
    }

    copy = (char *)malloc(length + 1);
    if (copy == NULL) {
        return 3;
    }
    memcpy(copy, plugin_root, length + 1);

    if (runtime->plugin_root != NULL) {
        free(runtime->plugin_root);
    }
    runtime->plugin_root = copy;

    lua_pushstring(runtime->state, plugin_root);
    lua_setglobal(runtime->state, "ADDKO_PLUGIN_ROOT");
    return 0;
}

ADDKO_EXPORT void addko_lua_destroy(AddKoLuaRuntime *runtime) {
    if (runtime == NULL) {
        return;
    }
    if (runtime->state != NULL) {
        lua_close(runtime->state);
        runtime->state = NULL;
    }
    if (runtime->plugin_root != NULL) {
        free(runtime->plugin_root);
        runtime->plugin_root = NULL;
    }
    free(runtime);
}

ADDKO_EXPORT int addko_lua_eval(
    AddKoLuaRuntime *runtime,
    const char *source,
    char *output,
    size_t output_size
) {
    if (runtime == NULL || runtime->state == NULL || source == NULL) {
        copy_message(output, output_size, "invalid runtime or source");
        return 1;
    }

    lua_State *L = runtime->state;
    lua_settop(L, 0);
    runtime->instruction_ticks = ADDKO_HOOK_TICKS;
    lua_sethook(L, instruction_hook, LUA_MASKCOUNT, ADDKO_HOOK_GRANULARITY);

    int status = luaL_loadstring(L, source);
    if (status == LUA_OK) {
        status = lua_pcall(L, 0, LUA_MULTRET, 0);
    }

    lua_sethook(L, NULL, 0, 0);

    if (status != LUA_OK) {
        copy_message(output, output_size, lua_tostring(L, -1));
        lua_settop(L, 0);
        return status;
    }

    if (lua_gettop(L) == 0) {
        copy_message(output, output_size, "");
    } else {
        size_t length = 0;
        const char *text = luaL_tolstring(L, -1, &length);
        (void)length;
        copy_message(output, output_size, text);
    }

    lua_settop(L, 0);
    return 0;
}
