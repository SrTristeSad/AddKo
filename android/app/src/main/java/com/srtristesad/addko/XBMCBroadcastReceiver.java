package com.srtristesad.addko;
// Kodi constructs the receiver from Context.getPackageName(). Its inherited JNI method
// remains registered on the original org.xbmc.kodi class used by the official binary.
public class XBMCBroadcastReceiver extends org.xbmc.kodi.XBMCBroadcastReceiver {}
