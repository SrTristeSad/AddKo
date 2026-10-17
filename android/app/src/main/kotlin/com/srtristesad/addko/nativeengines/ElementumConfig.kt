package com.srtristesad.addko.nativeengines

import android.content.Context
import org.json.JSONObject
import java.io.File

internal data class EngineRuntime(
    val root: File,
    val profile: File,
    val temp: File,
    val torrents: File,
    val library: File,
    val downloads: File,
    val addon: File,
    val config: File,
    val log: File,
) {
    fun args(): String = listOf(
        "-configPath=${config.absolutePath}",
        "-addonPath=${addon.absolutePath}",
        "-profilePath=${profile.absolutePath}",
        "-tempPath=${temp.absolutePath}",
        "-torrentsPath=${torrents.absolutePath}",
        "-libraryPath=${library.absolutePath}",
        "-downloadsPath=${downloads.absolutePath}",
        "-logPath=${log.absolutePath}",
        "-localHost=127.0.0.1",
        "-localPort=65220",
        "-remoteHost=127.0.0.1",
        "-remotePort=65221",
        "-disableParentProcessWatcher",
        "-disableLibrarySync",
    ).joinToString(" ")
}

internal object ElementumConfig {
    fun prepare(context: Context): EngineRuntime {
        val root = File(context.filesDir, "elementum").apply { mkdirs() }
        val profile = File(root, "profile").apply { mkdirs() }
        val temp = File(context.cacheDir, "elementum").apply { mkdirs() }
        val torrents = File(root, "torrents").apply { mkdirs() }
        val library = File(root, "library").apply { mkdirs() }
        val downloads = File(root, "downloads").apply { mkdirs() }
        val addon = File(root, "addon").apply { mkdirs() }
        val config = File(root, "elementum-config.json")
        val log = File(root, "elementum.log")

        val runtime = EngineRuntime(
            root = root,
            profile = profile,
            temp = temp,
            torrents = torrents,
            library = library,
            downloads = downloads,
            addon = addon,
            config = config,
            log = log,
        )

        config.writeText(buildJson(runtime).toString())
        return runtime
    }

    private fun buildJson(paths: EngineRuntime): JSONObject {
        val info = JSONObject()
            .put("Author", "SrTristeSad")
            .put("Description", "Approved Elementum engine bundled by AddKo")
            .put("Disclaimer", "")
            .put("Fanart", "")
            .put("Home", paths.root.absolutePath)
            .put("Icon", "")
            .put("ID", "io.addko.luelement.engine")
            .put("Name", "AddKo approved native engine")
            .put("Path", paths.addon.absolutePath)
            .put("Profile", paths.profile.absolutePath)
            .put("TempPath", paths.temp.absolutePath)
            .put("Stars", "")
            .put("Summary", "Embedded Elementum engine for Luelement")
            .put("Type", "service")
            .put("Version", "0.1.0-dev")
            .put("Xbmc", "")

        val platform = JSONObject()
            .put("OS", "android")
            .put("Arch", "arm64")
            .put("Version", android.os.Build.VERSION.RELEASE ?: "")
            .put("Kodi", 20)
            .put("Build", "AddKoEngine")

        val settings = JSONObject()
            .put("download_path", paths.downloads.absolutePath)
            .put("library_path", paths.library.absolutePath)
            .put("torrents_path", paths.torrents.absolutePath)

            .put("play_resume_action", 1)
            .put("play_resume_back", 0)

            .put("download_storage", 1)
            .put("download_file_strategy", 0)
            .put("keep_downloading", 1)
            .put("keep_files_playing", 1)
            .put("keep_files_finished", 1)

            .put("auto_memory_size", true)
            .put("auto_memory_size_strategy", 1)
            .put("memory_size", 100)
            .put("auto_adjust_memory_size", true)
            .put("auto_kodi_buffer_size", false)
            .put("auto_adjust_buffer_size", false)
            .put("min_candidate_size", 100)
            .put("min_candidate_show_size", 4)
            .put("buffer_size", 20)
            .put("end_buffer_size", 4)
            .put("buffer_timeout", 60)

            .put("use_torrent_history", true)
            .put("torrent_history_size", 50)
            .put("autoload_torrents", true)
            .put("autoload_torrents_paused", true)
            .put("silent_stream_start", false)
            .put("autoyes_enabled", true)
            .put("autoyes_timeout", 5)

            .put("use_cache_selection", true)
            .put("use_cache_search", true)
            .put("use_cache_torrents", true)
            .put("cache_search_duration", 24)
            .put("show_files_watched", true)

            .put("results_per_page", 20)
            .put("greeting_enabled", false)
            .put("enable_overlay_status", false)
            .put("disable_bg_progress", true)
            .put("disable_bg_progress_playback", true)
            .put("add_episode_numbers", true)
            .put("seasons_all", true)
            .put("seasons_order", 0)
            .put("seasons_specials", true)
            .put("show_unwatched_episodes_number", true)
            .put("playback_percent", 85)

            .put("choose_stream_auto_movie", false)
            .put("choose_stream_auto_show", false)
            .put("choose_stream_auto_search", false)
            .put("force_link_type", false)
            .put("add_specials", false)
            .put("unaired_seasons", false)
            .put("unaired_episodes", false)
            .put("show_episodes_on_release_day", false)
            .put("smart_episode_match", true)
            .put("smart_episode_start", true)
            .put("smart_episode_choose", true)

            .put("library_enabled", false)
            .put("library_sync_enabled", false)
            .put("library_sync_playback_enabled", false)
            .put("library_update", 0)
            .put("library_update_delay", 300)
            .put("library_update_frequency", 6)
            .put("library_nfo_movies", false)
            .put("library_nfo_shows", false)
            .put("strm_language", "")

            .put("seed_forever", false)
            .put("share_ratio_limit", 200)
            .put("seed_time_ratio_limit", 700)
            .put("seed_time_limit", 24)

            .put("disable_upload", false)
            .put("disable_lsd", false)
            .put("disable_dht", false)
            .put("disable_tcp", false)
            .put("disable_utp", false)
            .put("disable_upnp", false)
            .put("disable_natpmp", false)
            .put("listen_autodetect_ip", true)
            .put("listen_autodetect_port", true)
            .put("listen_port_min", 6881)
            .put("listen_port_max", 6891)
            .put("listen_interfaces", "")
            .put("outgoing_interfaces", "")
            .put("encryption_policy", 0)
            .put("spoof_user_agent", 0)

            .put("max_upload_rate", 0)
            .put("max_download_rate", 0)
            .put("limit_after_buffering", false)
            .put("connections_limit", 0)
            .put("conntracker_limit_auto", true)
            .put("conntracker_limit", 0)
            .put("session_save", 15)

            .put("tuned_storage", true)
            .put("disk_cache_size", 12)
            .put("use_libtorrent_config", false)
            .put("use_libtorrent_logging", false)
            .put("use_libtorrent_deadline", true)
            .put("use_libtorrent_pauseresume", true)
            .put("libtorrent_profile", 0)
            .put("magnet_resolve_timeout", 30)
            .put("add_extra_trackers", 0)
            .put("remove_original_trackers", false)
            .put("modify_trackers_strategy", 0)

            .put("force_use_trakt", false)
            .put("trakt_username", "")
            .put("trakt_token", "")
            .put("trakt_refresh_token", "")
            .put("trakt_token_expiry", 0)
            .put("trakt_scrobble", false)
            .put("trakt_sync_enabled", false)
            .put("trakt_sync_playback_enabled", false)
            .put("trakt_sync_frequency_min", 5)
            .put("trakt_sync_collections", false)
            .put("trakt_sync_watchlist", false)
            .put("trakt_sync_userlists", false)
            .put("trakt_sync_playback_progress", false)
            .put("trakt_sync_hidden", false)
            .put("trakt_sync_watched", false)
            .put("trakt_sync_watchedback", false)
            .put("trakt_sync_added_movies", false)
            .put("trakt_sync_added_movies_location", 0)
            .put("trakt_sync_added_movies_list", 0)
            .put("trakt_sync_added_shows", false)
            .put("trakt_sync_added_shows_location", 0)
            .put("trakt_sync_added_shows_list", 0)
            .put("trakt_sync_removed_movies", false)
            .put("trakt_sync_removed_movies_back", false)
            .put("trakt_sync_removed_movies_location", 0)
            .put("trakt_sync_removed_movies_list", 0)
            .put("trakt_sync_removed_shows", false)
            .put("trakt_sync_removed_shows_back", false)
            .put("trakt_sync_removed_shows_location", 0)
            .put("trakt_sync_removed_shows_list", 0)
            .put("trakt_progress_hide_unaired", false)
            .put("trakt_progress_sort", 0)
            .put("trakt_progress_date_format", "")
            .put("trakt_progress_color_date", "")
            .put("trakt_progress_color_show", "")
            .put("trakt_progress_color_episode", "")
            .put("trakt_progress_color_unaired", "")
            .put("trakt_calendars_hide_watched", false)
            .put("trakt_calendars_date_format", "")
            .put("trakt_calendars_color_date", "")
            .put("trakt_calendars_color_show", "")
            .put("trakt_calendars_color_episode", "")
            .put("trakt_calendars_color_unaired", "")
            .put("trakt_use_lowest_release_date", false)

            .put("use_fanart_tv", false)
            .put("tmdb_api_key", "")
            .put("tmdb_images_quality", 1)
            .put("tmdb_show_use_prod_company_as_studio", false)

            .put("opensubtitles_token", "")
            .put("opensubtitles_token_expiry", 0)
            .put("opensubtitles_user", "")
            .put("opensubtitles_pass", "")
            .put("osdb_language", "")
            .put("osdb_auto_language", true)
            .put("osdb_auto_load", false)
            .put("osdb_auto_load_count", 0)
            .put("osdb_auto_load_delete", false)
            .put("osdb_auto_load_skipexists", true)
            .put("osdb_included_enabled", false)
            .put("osdb_included_skipexists", true)

            .put("sorting_mode_movies", 0)
            .put("sorting_mode_shows", 0)
            .put("resolution_preference_movies", 0)
            .put("resolution_preference_shows", 0)
            .put("percentage_additional_seeders", 0)

            .put("custom_provider_timeout_enabled", false)
            .put("custom_provider_timeout", 0)
            .put("provider_use_lowest_release_date", false)

            .put("proxy_type", 0)
            .put("proxy_enabled", false)
            .put("proxy_host", "")
            .put("proxy_port", 0)
            .put("proxy_login", "")
            .put("proxy_password", "")
            .put("use_proxy_http", false)
            .put("use_proxy_tracker", false)
            .put("use_proxy_download", false)
            .put("proxy_force", false)

            .put("internal_proxy_enabled", false)
            .put("internal_proxy_logging", false)
            .put("internal_proxy_logging_body", false)

            .put("internal_dns_enabled", false)
            .put("internal_dns_skip_ipv6", false)
            .put("internal_dns_opennic_use", false)
            .put("internal_dns_server", "")
            .put("internal_dns_server_custom", "")

            .put("antizapret_enabled", false)
            .put("antizapret_pac_url", "")

            .put("completed_move", false)
            .put("completed_movies_path", "")
            .put("completed_shows_path", "")

            .put("skip_burst_search", false)
            .put("skip_repository_search", true)

            .put("local_only_client", false)
            .put("log_level", 2)

        return JSONObject()
            .put("Info", info)
            .put("Platform", platform)
            .put("Settings", settings)
            .put("Language", "pt")
            .put("SecondLanguage", "en")
            .put("Region", "BR")
    }
}
