import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/config/ad_blocking.dart';
import '../../core/config/playback_bridge.dart';
import '../../core/config/mirror_fixes.dart';
import '../../core/config/player_sources.dart';
import '../../core/config/request_probe.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/media.dart';
import '../../domain/entities/media_details.dart';
import '../widgets/media_widgets.dart';
import 'navigation.dart';

class PlayerView extends StatefulWidget {
  const PlayerView({super.key, required this.details});
  final MediaDetails details;

  @override
  State<PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends State<PlayerView> {
  InAppWebViewController? _controller;
  final GlobalKey _webViewKey = GlobalKey();
  final ValueNotifier<int> _loadingProgress = ValueNotifier(0);
  late final List<PlayerSource> _sources;
  late PlayerSource _source;
  late int _season;
  int _episode = 1;
  int _navigationSerial = 0;
  bool _isPlayerDocumentLoading = true;
  String? _playerError;
  final Set<String> _failedSources = {};
  bool _adBlockingReady = false;
  UnmodifiableListView<UserScript> _initialUserScripts = UnmodifiableListView(
    const <UserScript>[],
  );

  /// Whether the mirror's player has asked for the whole screen. It is
  /// Flutter's job on cinesrc; see [MirrorFixes.pageFullscreen].
  bool _pageFullscreen = false;

  /// Roll on to the next episode when the current one finishes. Series only;
  /// there is nothing to advance to after a film.
  bool _autoPlayNext = true;
  ({int season, int episode})? _upNext;
  int _upNextSeconds = 0;
  Timer? _upNextTimer;

  static const _upNextDelay = 8;

  MediaDetails get details => widget.details;
  Media get media => details.media;

  @override
  void initState() {
    super.initState();
    _sources = PlayerSources.availableFor(media.type, imdbId: details.imdbId);
    _source = PlayerSources.preferredFor(media.type, imdbId: details.imdbId);
    _season = details.seasonList.firstOrNull?.number ?? 1;
    unawaited(_prepareAdBlocking());
  }

  /// Content blockers and user scripts are read once, when the WebView is
  /// created, so the filter list has to be compiled before that happens.
  /// Creating the player early would leave the mirror's advertising and
  /// popunder scripts unblocked for the whole session — the thing that makes
  /// playback stutter on iOS, where there is no request interception to fall
  /// back on. The engine is already warming up from `main`, so in practice
  /// this resolves before the first frame of the player is shown.
  Future<void> _prepareAdBlocking() async {
    try {
      await AdBlocking.ensureInitialized();
    } catch (error) {
      debugPrint('Ad blocking unavailable, playing unfiltered: $error');
    }
    if (!mounted) return;
    setState(() {
      _initialUserScripts = UnmodifiableListView([
        AdBlocking.popupGuardScript,
        MirrorFixes.scrollDrift,
        MirrorFixes.pageFullscreen,
        ?AdBlocking.cosmeticHidingScript(_playerUri),
        ?RequestProbe.script(),
        PlaybackBridge.script(autoPlay: true),
      ]);
      _adBlockingReady = true;
    });
  }

  int get _episodeCount =>
      details.seasonList
          .where((season) => season.number == _season)
          .firstOrNull
          ?.episodeCount ??
      1;

  PlayerRequest get _request => playerRequest(
    mediaId: media.id,
    imdbId: details.imdbId,
    season: _season,
    episode: _episode,
  );

  Uri get _playerUri => Uri.parse(_source.buildUrl(_request));

  Future<void> _loadPlayer() async {
    _cancelUpNext();
    _isPlayerDocumentLoading = true;
    _loadingProgress.value = 0;
    if (_playerError != null) setStateIfMounted(() => _playerError = null);
    await _controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri(_playerUri.toString())),
    );
  }

  @override
  void dispose() {
    _upNextTimer?.cancel();
    _loadingProgress.dispose();
    if (_pageFullscreen) {
      // Leaving the player mid-fullscreen must not strand the rest of the app
      // without its status bar.
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    super.dispose();
  }

  /// The page has taken, or given back, the whole screen.
  ///
  /// WebKit's own fullscreen is unusable here — it hands the page a viewport
  /// shorter than the screen and pins the element with user-agent rules no
  /// author style can outrank — so on cinesrc the page fills the WebView
  /// instead and Flutter grows the WebView to the screen. The WebView keeps
  /// its [_webViewKey], so moving between the two layouts resizes the
  /// platform view rather than rebuilding it and reloading the mirror.
  void _handlePageFullscreen(List<dynamic> arguments) {
    final message = arguments.isEmpty ? null : arguments.first;
    if (message is! Map) return;
    final entering = message['state'] == 'enter';
    if (!mounted || entering == _pageFullscreen) return;

    setState(() => _pageFullscreen = entering);
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        entering ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      ),
    );
  }

  /// Back gesture: put the page back inline, then follow it in Flutter.
  void _leavePageFullscreen() {
    unawaited(
      _controller
          ?.evaluateJavascript(source: MirrorFixes.leaveFullscreenScript)
          .catchError((Object error) {
            debugPrint('Could not leave the page fullscreen: $error');
            return null;
          }),
    );
    if (mounted && _pageFullscreen) {
      setState(() => _pageFullscreen = false);
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
  }

  void setStateIfMounted(VoidCallback change) {
    if (mounted) setState(change);
  }

  void _selectSource(PlayerSource value) {
    if (value.id == _source.id) return;
    setState(() {
      _source = value;
      _failedSources.remove(value.id);
    });
    _loadPlayer();
  }

  void _selectSeason(int value) {
    if (value == _season) return;
    setState(() {
      _season = value;
      _episode = 1;
      _failedSources.clear();
    });
    _loadPlayer();
  }

  void _selectEpisode(int value) {
    if (value == _episode) return;
    setState(() {
      _episode = value;
      _failedSources.clear();
    });
    _loadPlayer();
  }

  /// Playback state reported by the page's bridge script. Mirrors repeat the
  /// last second of a video, so only the first end of a given episode counts.
  void _handlePlaybackEvent(List<dynamic> arguments) {
    final event = PlaybackBridge.eventName(arguments.firstOrNull);
    switch (event) {
      case 'ended':
        _startUpNext();
      case 'play':
        // A mirror that restarts the same file (a quality switch, a rewind)
        // must not drag the viewer into the next episode.
        _cancelUpNext();
    }
  }

  /// The episode that follows the current one, rolling over into the next
  /// season, or null at the end of the series.
  ({int season, int episode})? _nextEpisodeSlot() {
    if (media.type != MediaType.tv) return null;
    if (_episode < _episodeCount) {
      return (season: _season, episode: _episode + 1);
    }
    final following = details.seasonList
        .where((season) => season.number > _season && season.episodeCount > 0)
        .fold<Season?>(
          null,
          (best, season) =>
              best == null || season.number < best.number ? season : best,
        );
    return following == null ? null : (season: following.number, episode: 1);
  }

  void _startUpNext() {
    if (!mounted || !_autoPlayNext || _upNext != null) return;
    final next = _nextEpisodeSlot();
    if (next == null) return;

    setState(() {
      _upNext = next;
      _upNextSeconds = _upNextDelay;
    });
    _upNextTimer?.cancel();
    _upNextTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_upNextSeconds <= 1) {
        timer.cancel();
        _playUpNext();
        return;
      }
      setState(() => _upNextSeconds--);
    });
  }

  void _cancelUpNext() {
    _upNextTimer?.cancel();
    _upNextTimer = null;
    if (_upNext != null) setStateIfMounted(() => _upNext = null);
  }

  void _playUpNext() {
    final next = _upNext;
    if (next == null) return;
    _cancelUpNext();
    setState(() {
      _season = next.season;
      _episode = next.episode;
      _failedSources.clear();
    });
    _loadPlayer();
  }

  void _tryNextMirror(PlayerSource failed, String reason) {
    // WebView can deliver an error from an earlier navigation after a new
    // mirror is already active. Never let that stale callback fail the new
    // source.
    if (!mounted ||
        failed.id != _source.id ||
        _failedSources.contains(failed.id)) {
      return;
    }
    _failedSources.add(failed.id);
    final available = _sources
        .where((source) => !_failedSources.contains(source.id))
        .firstOrNull;
    debugPrint('Player mirror ${failed.id} failed: $reason');
    if (available == null) {
      _isPlayerDocumentLoading = false;
      _loadingProgress.value = 100;
      setState(() => _playerError = 'Every mirror failed to load.');
      return;
    }
    setState(() => _source = available);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${failed.label} failed. Trying ${available.label}…'),
        duration: const Duration(seconds: 2),
      ),
    );
    _loadPlayer();
  }

  Future<void> _checkPlayerHealth(WebUri? loadedUrl) async {
    if (loadedUrl == null || !_isPlayerDocument(loadedUrl)) return;

    final sourceId = _source.id;
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted || sourceId != _source.id) return;

    try {
      final hasFatalPage = await _controller?.evaluateJavascript(
        source: '''
            (() => {
              const text = (document.body?.textContent || '')
                .slice(0, 4096)
                .toLowerCase();
              return text.includes('application error: a client-side exception has occurred') ||
                  text.includes('this page could not be found');
            })();
          ''',
      );
      if (hasFatalPage == true && mounted && sourceId == _source.id) {
        _tryNextMirror(
          _source,
          'the embedded player reported a fatal page error',
        );
      }
    } catch (error) {
      debugPrint('Could not inspect player health: $error');
    }
  }

  Future<void> _handlePlayerLoadStop(WebUri? loadedUrl) async {
    if (loadedUrl == null || !_isPlayerDocument(loadedUrl)) return;
    if (!_isPlayerDocumentLoading) return;

    final sourceId = _source.id;
    final navigationSerial = _navigationSerial;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted ||
        sourceId != _source.id ||
        navigationSerial != _navigationSerial) {
      return;
    }

    _isPlayerDocumentLoading = false;
    _loadingProgress.value = 100;
    unawaited(_checkPlayerHealth(loadedUrl));
  }

  @override
  Widget build(BuildContext context) {
    if (_pageFullscreen) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _leavePageFullscreen();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SizedBox.expand(child: _playerSurface()),
        ),
      );
    }
    return _page();
  }

  Widget _page() => Scaffold(
    appBar: AppBar(title: const Text('Now playing')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text(media.title, style: AppTheme.display(30)),
        const SizedBox(height: 11),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            SoftChip(label: media.year),
            if (media.type == MediaType.tv)
              SoftChip(label: 'S$_season · E$_episode'),
          ],
        ),
        const SizedBox(height: 17),
        _mirrorPicker(),
        const SizedBox(height: 12),
        _player(),
        if (media.type == MediaType.tv) ...[
          const Divider(height: 42),
          _episodePicker(),
        ],
        const Divider(height: 42),
        const ViewfinderLabel(label: 'About this title'),
        const SizedBox(height: 8),
        Text('About', style: AppTheme.display(25)),
        const SizedBox(height: 7),
        if (media.overview.isNotEmpty)
          Text(
            media.overview,
            style: const TextStyle(color: AppColors.muted, height: 1.55),
          ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...details.genres.map((genre) => SoftChip(label: genre)),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.info_outline_rounded),
              label: const Text('BACK TO DETAILS'),
            ),
          ],
        ),
        if (details.recommendations.isNotEmpty) ...[
          const Divider(height: 46),
          MediaRail(
            title: 'Watch next',
            items: details.recommendations,
            type: media.type,
            onTap: (item) => openMediaDetails(context, item),
          ),
        ],
      ],
    ),
  );

  Widget _mirrorPicker() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Streaming source', style: AppTheme.utility(size: 10)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _sources
            .map(
              (source) => source.id == _source.id
                  ? FilledButton(
                      onPressed: () => _selectSource(source),
                      child: Text(source.label.toUpperCase()),
                    )
                  : OutlinedButton(
                      onPressed: () => _selectSource(source),
                      child: Text(source.label.toUpperCase()),
                    ),
            )
            .toList(growable: false),
      ),
      const SizedBox(height: 7),
      Text(
        'Source: ${_source.host}',
        style: const TextStyle(color: AppColors.muted, fontSize: 11),
      ),
    ],
  );

  Widget _player() => Container(
    foregroundDecoration: BoxDecoration(
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(6),
    ),
    child: ColoredBox(
      color: Colors.black,
      child: AspectRatio(aspectRatio: 16 / 9, child: _playerSurface()),
    ),
  );

  /// The WebView and everything stacked over it.
  Widget _playerSurface() => ColoredBox(
    color: Colors.black,
    child: Stack(
      fit: StackFit.expand,
      children: [
        if (_playerError == null && _adBlockingReady)
          RepaintBoundary(
            child: InAppWebView(
              key: _webViewKey,
              initialUrlRequest: URLRequest(url: WebUri(_playerUri.toString())),
              initialUserScripts: _initialUserScripts,
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                allowsAirPlayForMediaPlayback: true,
                allowsPictureInPictureMediaPlayback: true,
                supportMultipleWindows: true,
                javaScriptCanOpenWindowsAutomatically: false,
                useShouldOverrideUrlLoading: true,
                useShouldInterceptRequest: true,
                contentBlockers: AdBlocking.webViewContentBlockers,
                disableContextMenu: true,
                supportZoom: false,
                verticalScrollBarEnabled: false,
                horizontalScrollBarEnabled: false,
                thirdPartyCookiesEnabled: true,
                // Let the black Flutter surface show before the mirror's
                // document paints instead of exposing WebView's white
                // initialization canvas.
                transparentBackground: true,
                hardwareAcceleration: true,
                useHybridComposition: true,
                offscreenPreRaster: true,
              ),
              onWebViewCreated: (controller) {
                _controller = controller;
                controller.addJavaScriptHandler(
                  handlerName: PlaybackBridge.handlerName,
                  callback: _handlePlaybackEvent,
                );
                controller.addJavaScriptHandler(
                  handlerName: MirrorFixes.fullscreenHandlerName,
                  callback: _handlePageFullscreen,
                );
                if (RequestProbe.isEnabled) {
                  controller.addJavaScriptHandler(
                    handlerName: RequestProbe.handlerName,
                    callback: RequestProbe.record,
                  );
                }
              },
              onLoadStart: (_, _) {
                if (!mounted || !_isPlayerDocumentLoading) return;
                _navigationSerial++;
                _loadingProgress.value = 0;
              },
              onProgressChanged: (_, progress) {
                if (!mounted || !_isPlayerDocumentLoading) return;
                _loadingProgress.value = progress >= 95 ? 95 : progress;
              },
              onLoadStop: (_, url) => _handlePlayerLoadStop(url),
              onReceivedError: (_, request, error) {
                if (!mounted || request.isForMainFrame != true) return;

                final failed = _sourceForPlayerDocument(request.url);
                if (failed == null || failed.id != _source.id) {
                  debugPrint('Ignored stale player error from ${request.url}');
                  return;
                }

                final description = error.description.toLowerCase();
                final wasCancelled =
                    error.type.toValue() ==
                        WebResourceErrorType.CANCELLED.toValue() ||
                    description.contains('err_aborted') ||
                    description.contains('cancelled') ||
                    description.contains('canceled');
                if (wasCancelled) {
                  debugPrint(
                    'Ignored cancelled player navigation: '
                    '${error.description}',
                  );
                  return;
                }

                _tryNextMirror(failed, error.description);
              },
              onReceivedHttpError: (_, request, response) {
                if (request.isForMainFrame != true ||
                    (response.statusCode ?? 0) < 400) {
                  return;
                }
                final failed = _sourceForPlayerDocument(request.url);
                if (failed == null || failed.id != _source.id) return;
                _tryNextMirror(failed, 'HTTP ${response.statusCode}');
              },
              // Android/Windows only; see AdBlocking's class docs for why
              // WKWebView (iOS/macOS) can't be covered the same way.
              shouldInterceptRequest: (_, request) async =>
                  AdBlocking.interceptRequest(
                    url: request.url,
                    sourceUrl: _playerUri,
                  ),
              onCreateWindow: (_, _) async => false,
              shouldOverrideUrlLoading: (_, navigation) async {
                final url = navigation.request.url;
                if (url == null) return NavigationActionPolicy.CANCEL;

                if (AdBlocking.shouldBlockNavigation(
                  url: url,
                  sourceUrl: _playerUri,
                )) {
                  debugPrint('Blocked ad navigation: $url');
                  return NavigationActionPolicy.CANCEL;
                }

                final scheme = url.scheme.toLowerCase();
                if (!{
                  'http',
                  'https',
                  'about',
                  'data',
                  'blob',
                }.contains(scheme)) {
                  return NavigationActionPolicy.CANCEL;
                }

                if ({'about', 'data', 'blob'}.contains(scheme)) {
                  return NavigationActionPolicy.ALLOW;
                }

                final isPlayerDocument = _isPlayerDocument(url);
                final userInitiated =
                    navigation.hasGesture == true ||
                    navigation.navigationType == NavigationType.LINK_ACTIVATED;

                // Video controls use JavaScript/media APIs and don't need a
                // page navigation. Click-through ads do, often from an
                // iframe, so cancel every user-initiated HTTP navigation.
                if (userInitiated &&
                    {'http', 'https'}.contains(scheme) &&
                    !isPlayerDocument) {
                  debugPrint('Blocked player click-through: $url');
                  return NavigationActionPolicy.CANCEL;
                }

                // Never let an automatic redirect replace the top-level
                // player with an advertising landing page.
                if (navigation.isForMainFrame && !isPlayerDocument) {
                  debugPrint('Blocked top-level player redirect: $url');
                  return NavigationActionPolicy.CANCEL;
                }

                return NavigationActionPolicy.ALLOW;
              },
              onJsAlert: (_, _) async => JsAlertResponse(
                handledByClient: true,
                action: JsAlertResponseAction.CONFIRM,
              ),
              onJsConfirm: (_, _) async => JsConfirmResponse(
                handledByClient: true,
                action: JsConfirmResponseAction.CANCEL,
              ),
            ),
          )
        else if (_playerError != null)
          ColoredBox(
            color: Colors.black,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: AppColors.muted,
                    ),
                    const SizedBox(height: 8),
                    const Text('This mirror could not load.'),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _loadPlayer,
                      child: const Text('RETRY'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ValueListenableBuilder<int>(
          valueListenable: _loadingProgress,
          builder: (context, progress, _) => progress < 100
              ? ColoredBox(
                  color: Colors.black,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox.square(
                              dimension: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: AppColors.brand,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Loading ${_source.label}',
                              style: AppTheme.utility(
                                size: 10,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Align(
                        alignment: Alignment.topCenter,
                        child: LinearProgressIndicator(
                          value: progress / 100,
                          minHeight: 2,
                          color: AppColors.brand,
                          backgroundColor: AppColors.raised,
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
        if (_upNext case final next?) _upNextOverlay(next),
      ],
    ),
  );

  Widget _upNextOverlay(({int season, int episode}) next) => ColoredBox(
    color: Colors.black.withValues(alpha: .84),
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Up next', style: AppTheme.utility(size: 10)),
            const SizedBox(height: 7),
            Text(
              'S${next.season} · E${next.episode}',
              textAlign: TextAlign.center,
              style: AppTheme.display(23),
            ),
            const SizedBox(height: 5),
            Text(
              'Playing in $_upNextSeconds s',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 13),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _playUpNext,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('PLAY NOW'),
                ),
                OutlinedButton(
                  onPressed: _cancelUpNext,
                  child: const Text('CANCEL'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  bool _isPlayerDocument(WebUri url) => _source.matchesPlayerUrl(url, _request);

  PlayerSource? _sourceForPlayerDocument(WebUri url) => _sources
      .where((source) => source.matchesPlayerUrl(url, _request))
      .firstOrNull;

  Widget _episodePicker() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ViewfinderLabel(label: 'Episodes'),
                const SizedBox(height: 7),
                Text('Season picker', style: AppTheme.display(25)),
                Text(
                  'Season $_season · $_episodeCount episodes',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          DropdownButton<int>(
            value: _season,
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(12),
              bottomLeft: Radius.circular(12),
            ),
            items: details.seasonList
                .map(
                  (season) => DropdownMenuItem(
                    value: season.number,
                    child: Text('Season ${season.number}'),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value != null) _selectSeason(value);
            },
          ),
        ],
      ),
      const SizedBox(height: 4),
      SwitchListTile.adaptive(
        value: _autoPlayNext,
        onChanged: (value) {
          setState(() => _autoPlayNext = value);
          if (!value) _cancelUpNext();
        },
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text(
          'Autoplay next episode',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        subtitle: const Text(
          'Rolls on when the current episode ends.',
          style: TextStyle(color: AppColors.muted, fontSize: 11),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 7,
        runSpacing: 7,
        children: List.generate(_episodeCount, (index) {
          final number = index + 1;
          return number == _episode
              ? FilledButton.tonal(
                  onPressed: () => _selectEpisode(number),
                  child: Text('EP $number'),
                )
              : OutlinedButton(
                  onPressed: () => _selectEpisode(number),
                  child: Text('EP $number'),
                );
        }),
      ),
    ],
  );
}
