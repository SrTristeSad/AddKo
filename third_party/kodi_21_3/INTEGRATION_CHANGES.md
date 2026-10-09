# AddKo integration changes

Official libkodi binary is unchanged. Java templates generated with the original JNI package org.xbmc.kodi; imports of R use the AddKo resource namespace. Provider authorities use the AddKo package. Main.java dispatches launcher intents to AddKoCoreBridge. AddKo adds Kotlin bootstrap/profile classes, a receiver subclass, and script.addko.bridge.

Kodi addon-manifest.xml adds two optional system InputStreams and the required AddKo bridge script. InputStream native libraries are packaged in the Android native library directory, not extracted under assets. Corresponding upstream source snapshots and original licenses are included. Build recipes and dependency references are available in the full Kodi source snapshot.

AAPT asset filtering is configured to preserve underscore-prefixed directories required by Python and Kodi. Release minification/resource shrinking is disabled to preserve JNI class and method lookup. Local shared-storage access is requested only from the explicit Flutter action.

Revision 19 embeds Flutter into Main/NativeActivity in the same process. JNI JSON-RPC is the transport for directory, addon, and player operations. Main dispatches lifecycle, input, intents and permissions through AddKoFlutterHost. SurfaceView order is adapted for native video/GUI below the Flutter texture; native dialogs temporarily receive the input queue. skin.estuary/xml/Home.xml is changed to a blank background. Stock GUI internals remain present; this is not a headless recompile.
