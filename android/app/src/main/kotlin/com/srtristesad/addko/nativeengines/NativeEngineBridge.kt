package com.srtristesad.addko.nativeengines

internal object NativeEngineBridge {
    init {
        System.loadLibrary("c++_shared")
        System.loadLibrary("elementum")
        System.loadLibrary("addko_engine_bridge")
    }

    external fun start(logPath: String, args: String): Long
}
