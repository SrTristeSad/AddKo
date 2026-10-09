package com.srtristesad.addko;

/**
 * libandroidjni constructs this helper using Context.getPackageName().
 * Native callbacks are registered on the official org.xbmc.kodi class,
 * so inherit its public callbacks rather than declaring duplicate natives.
 */
public class XBMCInputDeviceListener extends org.xbmc.kodi.XBMCInputDeviceListener {}
