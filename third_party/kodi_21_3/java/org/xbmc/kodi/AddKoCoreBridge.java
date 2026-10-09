package org.xbmc.kodi;

import android.os.Handler;
import android.os.Looper;
import android.content.Intent;
import android.util.Log;
import android.widget.Toast;
import org.json.JSONObject;
import org.json.JSONArray;

/** Calls Kodi's existing JNI JSON-RPC transport after the core has initialized. */
public final class AddKoCoreBridge {
    /** Uses Kodi's real JNI transport, without an HTTP server or external app. */
    public static String requestJSON(String request) {
        return new XBMCJsonRPC()._requestJSON(request);
    }
}
