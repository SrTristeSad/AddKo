#include <jni.h>
#include <android/log.h>
#include <dlfcn.h>
#include <stdint.h>

#define LOG_TAG "AddKoNativeEngine"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

typedef int64_t (*start_with_log_and_args_fn)(char *log_path, char *args);

JNIEXPORT jlong JNICALL
Java_com_srtristesad_addko_nativeengines_NativeEngineBridge_start(
    JNIEnv *env,
    jobject thiz,
    jstring log_path,
    jstring args
) {
    (void)thiz;

    void *handle = dlopen("libelementum.so", RTLD_NOW | RTLD_LOCAL);
    if (handle == NULL) {
        LOGE("Bundled native module not found: %s", dlerror());
        return (jlong)-102;
    }
    void *symbol = dlsym(handle, "startWithLogAndArgs");
    if (symbol == NULL) {
        LOGE("Elementum symbol startWithLogAndArgs not found: %s", dlerror());
        dlclose(handle);
        return (jlong)-100;
    }

    start_with_log_and_args_fn start_fn = (start_with_log_and_args_fn)symbol;
    const char *log_chars = (*env)->GetStringUTFChars(env, log_path, NULL);
    const char *args_chars = (*env)->GetStringUTFChars(env, args, NULL);

    if (log_chars == NULL || args_chars == NULL) {
        if (log_chars != NULL) {
            (*env)->ReleaseStringUTFChars(env, log_path, log_chars);
        }
        if (args_chars != NULL) {
            (*env)->ReleaseStringUTFChars(env, args, args_chars);
        }
        dlclose(handle);
        return (jlong)-101;
    }

    LOGI("Starting embedded Elementum shared library");
    const int64_t code = start_fn((char *)log_chars, (char *)args_chars);
    LOGI("Embedded Elementum stopped with code %lld", (long long)code);

    (*env)->ReleaseStringUTFChars(env, log_path, log_chars);
    (*env)->ReleaseStringUTFChars(env, args, args_chars);
    dlclose(handle);
    return (jlong)code;
}
