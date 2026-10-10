package org.xbmc.kodi;

import com.srtristesad.addko.R;
import org.xbmc.kodi.channels.util.TvUtil;

import static android.content.pm.PackageManager.FEATURE_LEANBACK;

import android.app.NativeActivity;
import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.ResolveInfo;
import android.graphics.Color;
import android.graphics.Rect;
import android.hardware.input.InputManager;
import android.media.AudioManager;
import android.os.Build;
import android.os.Build.VERSION_CODES;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.Choreographer;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.widget.RelativeLayout;

import java.util.ArrayList;
import java.io.File;

public class Main extends NativeActivity implements Choreographer.FrameCallback
{
  private static final String TAG = "Kodi";

  public static Main MainActivity = null;
  public XBMCMainView mMainView = null;
  private com.srtristesad.addko.AddKoFlutterHost addkoHost;

  private XBMCSettingsContentObserver mSettingsContentObserver;
  private XBMCInputDeviceListener mInputDeviceListener;
  private XBMCJsonRPC mJsonRPC = null;
  private View mDecorView = null;
  private RelativeLayout mVideoLayout = null;
  private Handler handler = new Handler(Looper.myLooper());

  private class DelayedIntent
  {
    public Intent mIntent = null;
    public int mDelay = 0;

    public DelayedIntent(Intent intent, int delay) {
      mIntent = intent;
      mDelay = delay;
    }
  }
  private ArrayList<DelayedIntent> mDelayedIntents = new ArrayList<DelayedIntent>();
  private boolean mPaused = true;


  native void _onNewIntent(Intent intent);

  native void _onActivityResult(int requestCode, int resultCode, Intent resultData);

  native void _doFrame(long frameTimeNanos);

  native void _onVisibleBehindCanceled();

  private Runnable leanbackUpdateRunnable = new Runnable()
  {
    @Override
    public void run()
    {
      Log.d(TAG, "Main: Updating recommendations");
      new Thread()
      {
        public void run()
        {
          mJsonRPC.updateLeanback(Main.this);
        }
      }.start();
      handler.postDelayed(this, XBMCProperties.getIntProperty("xbmc.leanbackrefresh", 60 * 60) * 1000);
    }
  };

  public Main()
  {
    super();
    MainActivity = this;
  }

  public Rect getDisplayRect()
  {
    Rect ret = new Rect();
    ret.top = 0;
    ret.left = 0;
    ret.right = 0;
    ret.bottom = 0;

    try
    {
      ret.right = mDecorView.getRootView().getWidth();
      ret.bottom = mDecorView.getRootView().getHeight();
    }
    catch (Exception e)
    {
    }

    return ret;
  }

  public void registerMediaButtonEventReceiver()
  {
    AudioManager manager = (AudioManager) getSystemService(AUDIO_SERVICE);
    manager.registerMediaButtonEventReceiver(new ComponentName(getPackageName(), XBMCBroadcastReceiver.class.getName()));
  }

  public void unregisterMediaButtonEventReceiver()
  {
    AudioManager manager = (AudioManager) getSystemService(AUDIO_SERVICE);
    manager.unregisterMediaButtonEventReceiver(new ComponentName(getPackageName(), XBMCBroadcastReceiver.class.getName()));
  }

  @Override
  public void onCreate(Bundle savedInstanceState)
  {
    // System properties belong to a process. Bootstrap runs in the launcher
    // process, so configure the :kodi process before JNI/NativeActivity startup.
    System.setProperty("xbmc.home", new File(getCacheDir(), "apk").getAbsolutePath());
    System.setProperty("xbmc.data", new File(getFilesDir(), "kodi-profile").getAbsolutePath());
    File kodiTemp = new File(getCacheDir(), "kodi-temp");
    kodiTemp.mkdirs();
    System.setProperty("xbmc.temp", kodiTemp.getAbsolutePath());
    System.setProperty("xbmc.proploaded", "yes");
    System.loadLibrary("kodi");

    super.onCreate(savedInstanceState);

    setContentView(R.layout.activity_main);
    setVolumeControlStream(AudioManager.STREAM_MUSIC);

    mSettingsContentObserver = new XBMCSettingsContentObserver(this, handler);
    getApplicationContext().getContentResolver().registerContentObserver(android.provider.Settings.System.CONTENT_URI, true, mSettingsContentObserver);

    // Delayed Intent
    if (getIntent().getData() != null)
    {
      mDelayedIntents.add(new DelayedIntent(new Intent(getIntent()), 5000));
      getIntent().setData(null);
    }

    if (getPackageManager().hasSystemFeature(FEATURE_LEANBACK))
    {
      if (Build.VERSION.SDK_INT >= VERSION_CODES.O
          && getLauncherName().equals("com.google.android.tvlauncher"))
      {
        TvUtil.scheduleSyncingChannel(this);
      }
      else if (Build.VERSION.SDK_INT < VERSION_CODES.O
               && getLauncherName().equals("com.google.android.leanbacklauncher"))
      {
        // Leanback
        mJsonRPC = new XBMCJsonRPC();
        handler.removeCallbacks(leanbackUpdateRunnable);
        handler.postDelayed(leanbackUpdateRunnable, 30 * 1000);
      }
    }

    // register the InputDeviceListener implementation
    mInputDeviceListener = new XBMCInputDeviceListener();
    InputManager manager = (InputManager) getSystemService(INPUT_SERVICE);
    manager.registerInputDeviceListener(mInputDeviceListener, handler);

    mDecorView = getWindow().getDecorView();
    mDecorView.setBackground(null);
    getWindow().takeSurface(null);
    setContentView(R.layout.activity_main);
    mVideoLayout = (RelativeLayout) findViewById(R.id.VideoLayout);

    mMainView = new XBMCMainView(this);
    RelativeLayout.LayoutParams layoutParams = new RelativeLayout.LayoutParams(RelativeLayout.LayoutParams.MATCH_PARENT, RelativeLayout.LayoutParams.MATCH_PARENT);
    mMainView.setElevation(1);  // Always on Top
    mVideoLayout.addView(mMainView, layoutParams);

    if (Build.VERSION.SDK_INT < 30)
    {
      mDecorView.setOnSystemUiVisibilityChangeListener(new View.OnSystemUiVisibilityChangeListener()
      {
        @Override
        public void onSystemUiVisibilityChange(int visibility)
        {
          if ((visibility & View.SYSTEM_UI_FLAG_HIDE_NAVIGATION) == 0)
          {
            handler.post(new Runnable()
            {
              public void run()
              {
                // Immersive mode
                mDecorView.setSystemUiVisibility(
                        View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                                | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                                | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                                | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                                | View.SYSTEM_UI_FLAG_FULLSCREEN
                                | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
              }
            });
          }
        }
      });
    }
      startAddKoHostWhenReady();
  }

  private void startAddKoHostWhenReady()
  {
    final int[] attempts = new int[] { 0 };
    final Runnable starter = new Runnable()
    {
      @Override
      public void run()
      {
        if (isFinishing() || isDestroyed())
          return;

        // XBMCMainView is backed by the native renderer. Starting a second GPU
        // frontend while that surface is still being created is unsafe on some
        // Android/TV GPU drivers. Wait for the Kodi view before embedding Flutter.
        if (mMainView == null || !mMainView.mIsCreated)
        {
          ++attempts[0];
          if (attempts[0] == 120)
            Log.w(TAG, "AddKo: still waiting for Kodi surface; startup will continue");
          // Slow devices must not permanently lose their frontend after 12s.
          handler.postDelayed(this, attempts[0] < 120 ? 100 : 1000);
          return;
        }

        try
        {
          addkoHost = new com.srtristesad.addko.AddKoFlutterHost(Main.this, mVideoLayout);
          if (!mPaused)
          {
            addkoHost.onStart();
            addkoHost.onResume();
          }
          Log.i(TAG, "AddKo: Flutter host attached after Kodi surface became ready");
        }
        catch (Throwable error)
        {
          // A Flutter/plugin startup problem must not take the native Kodi process down.
          Log.e(TAG, "AddKo: Flutter host startup failed", error);
          try
          {
            android.widget.TextView failure = new android.widget.TextView(Main.this);
            failure.setText("AddKo: falha ao iniciar a interface Flutter\n" + error.toString());
            failure.setTextColor(android.graphics.Color.WHITE);
            failure.setBackgroundColor(android.graphics.Color.argb(220, 120, 0, 0));
            failure.setTextSize(16);
            failure.setPadding(24, 24, 24, 24);
            mVideoLayout.addView(failure, new RelativeLayout.LayoutParams(
                RelativeLayout.LayoutParams.MATCH_PARENT, RelativeLayout.LayoutParams.WRAP_CONTENT));
          }
          catch (Throwable ignored) {}
        }
      }
    };
    handler.postDelayed(starter, 250);
  }

  @Override
  protected void onNewIntent(Intent intent)
  {
    super.onNewIntent(intent);
    if (addkoHost != null) addkoHost.onNewIntent(intent);
    // Delay until after Resume
    if (mPaused)
    {
      Log.d(TAG, "Main: onNewIntent (delayed)");
      mDelayedIntents.add(new DelayedIntent(new Intent(intent), 500));
    }
    else
    {
      Log.d(TAG, "Main: onNewIntent (immediate)");
      _onNewIntent(intent);
    }
  }

  @Override
  public void onStart()
  {
    super.onStart();
    if (addkoHost != null) addkoHost.onStart();

    Choreographer.getInstance().removeFrameCallback(this);
    Choreographer.getInstance().postFrameCallback(this);
  }

  @Override
  public void onResume()
  {
    super.onResume();
    if (addkoHost != null) addkoHost.onResume();

    if (Build.VERSION.SDK_INT >= 30)
    {
      getWindow().setDecorFitsSystemWindows(false);
      WindowInsetsController controller = getWindow().getInsetsController();
      if (controller != null)
      {
        controller.hide(WindowInsets.Type.statusBars() | WindowInsets.Type.navigationBars());
        controller.setSystemBarsBehavior(WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
      }
    }
    else
    {
      // Immersive mode
      mDecorView.setSystemUiVisibility(
          View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                  | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                  | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                  | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                  | View.SYSTEM_UI_FLAG_FULLSCREEN
                  | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
    }

    // New intent ?
    for (final DelayedIntent delayedIntent : mDelayedIntents)
    {
      handler.postDelayed(new Runnable()
      {
        @Override
        public void run()
        {
          try
          {
            _onNewIntent(delayedIntent.mIntent);
          }
          catch (UnsatisfiedLinkError e)
          {
            Log.e(TAG, "Main: Native not registered");
          }
        }
      }, delayedIntent.mDelay);
    }
    mDelayedIntents.clear();
    mPaused = false;
  }

  @Override
  public void onPause()
  {
    if (addkoHost != null) addkoHost.onPause();
    super.onPause();

    if (getPackageManager().hasSystemFeature(FEATURE_LEANBACK)
        && Build.VERSION.SDK_INT >= VERSION_CODES.O
        && getLauncherName().equals("com.google.android.tvlauncher")) {
      TvUtil.scheduleSyncingChannel(this);
    }

    mPaused = true;
  }

  @Override
  public void onActivityResult(int requestCode, int resultCode,
                               Intent resultData)
  {
    super.onActivityResult(requestCode, resultCode, resultData);
    if (addkoHost != null) addkoHost.onActivityResult(requestCode, resultCode, resultData);
    _onActivityResult(requestCode, resultCode, resultData);
  }

  @Override public void onStop() {
    if (addkoHost != null) addkoHost.onStop();
    super.onStop();
  }
  @Override public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] results) {
    super.onRequestPermissionsResult(requestCode, permissions, results);
    if (addkoHost != null) addkoHost.onRequestPermissionsResult(requestCode, permissions, results);
  }
  @Override public void onBackPressed() {
    if (addkoHost != null && addkoHost.onBackPressed()) return;
    super.onBackPressed();
  }

  @Override
  public void onDestroy()
  {
    if (addkoHost != null) addkoHost.destroy();
    TvUtil.cancelAllScheduledJobs(this);

    // unregister the InputDeviceListener implementation
    InputManager manager = (InputManager) getSystemService(INPUT_SERVICE);
    manager.unregisterInputDeviceListener(mInputDeviceListener);

    getApplicationContext().getContentResolver().unregisterContentObserver(mSettingsContentObserver);
    super.onDestroy();
  }

  @Override
  public void onVisibleBehindCanceled()
  {
    _onVisibleBehindCanceled();
    super.onVisibleBehindCanceled();
  }

  @Override
  public void doFrame(long frameTimeNanos)
  {
    Choreographer.getInstance().postFrameCallback(this);
    _doFrame(frameTimeNanos);
  }

  private native void _callNative(long funcAddr, long variantAddr);

  private void runNativeOnUiThread(final long funcAddr, final long variantAddr)
  {
    runOnUiThread(new Runnable()
    {
      @Override
      public void run()
      {
        _callNative(funcAddr, variantAddr);
      }
    });
  }

  /**
   * Gets the package name of the current system launcher
   */
  private String getLauncherName() {
    final Intent intent = new Intent(Intent.ACTION_MAIN);
    intent.addCategory(Intent.CATEGORY_HOME);
    final ResolveInfo res = getPackageManager().resolveActivity(intent, 0);
    // Package visibility and vendor launchers can return no matching activity.
    // Recommendations are optional and must not crash the core startup.
    if (res == null || res.activityInfo == null || res.activityInfo.packageName == null)
      return "";
    return res.activityInfo.packageName;
  }
}
