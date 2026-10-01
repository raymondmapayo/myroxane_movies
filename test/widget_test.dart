import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:roxane_movies/core/config/ad_blocking.dart';
import 'package:roxane_movies/core/config/mirror_fixes.dart';
import 'package:roxane_movies/core/config/playback_bridge.dart';
import 'package:roxane_movies/core/config/player_sources.dart';
import 'package:roxane_movies/core/config/request_probe.dart';
import 'package:roxane_movies/domain/entities/media.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

void main() {
  test('media exposes a safe display year', () {
    const dated = Media(
      id: 1,
      title: 'Title',
      type: MediaType.movie,
      date: '2026-08-21',
    );
    const undated = Media(id: 2, title: 'Other', type: MediaType.tv);

    expect(dated.year, '2026');
    expect(undated.year, 'TBA');
  });

  test('player sources build movie and episode mirror URLs', () {
    const imdbId = 'tt1234567';
    PlayerSource mirrorOn(String host, MediaType type) =>
        PlayerSources.forType(type).firstWhere((source) => source.host == host);

    expect(
      mirrorOn(
        'cinesrc.st',
        MediaType.movie,
      ).buildUrl(playerRequest(mediaId: 42)),
      'https://cinesrc.st/embed/movie/42',
    );
    expect(
      mirrorOn(
        'cinesrc.st',
        MediaType.tv,
      ).buildUrl(playerRequest(mediaId: 77, season: 3, episode: 5)),
      'https://cinesrc.st/embed/tv/77?s=3&e=5',
    );
    expect(
      PlayerSources.tv.first.buildUrl(
        playerRequest(mediaId: 77, season: 3, episode: 5),
      ),
      'https://vidlink.pro/tv/77/3/5?autoplay=true&nextbutton=true',
    );

    // Titles open on Mirror 1; the rest are the picker and the fallback chain.
    expect(PlayerSources.preferredFor(MediaType.movie).label, 'Mirror 1');
    expect(PlayerSources.preferredFor(MediaType.tv).label, 'Mirror 1');
    expect(PlayerSources.preferredFor(MediaType.movie).host, 'vidlink.pro');
    expect(PlayerSources.preferredFor(MediaType.tv).host, 'vidlink.pro');
    // Even where an IMDb mirror is on offer, it is not what a title opens on.
    expect(
      PlayerSources.preferredFor(MediaType.tv, imdbId: imdbId).label,
      'Mirror 1',
    );

    // The IMDb-keyed mirrors address the title by a different id, so they are
    // only offered for titles TMDB has an IMDb id for.
    expect(PlayerSources.movie, hasLength(4));
    expect(PlayerSources.tv, hasLength(4));
    expect(PlayerSources.availableFor(MediaType.movie), hasLength(3));
    expect(PlayerSources.availableFor(MediaType.tv), hasLength(3));
    expect(
      PlayerSources.availableFor(MediaType.movie, imdbId: imdbId),
      hasLength(4),
    );
    expect(
      PlayerSources.availableFor(MediaType.tv, imdbId: imdbId),
      hasLength(4),
    );
    expect(
      PlayerSources.availableFor(
        MediaType.movie,
        imdbId: imdbId,
      ).last.buildUrl(playerRequest(mediaId: 42, imdbId: imdbId)),
      'https://vidsrc.cc/v2/embed/movie/$imdbId?poster=true&autoPlay=false',
    );
    expect(
      PlayerSources.availableFor(MediaType.tv, imdbId: imdbId).last.buildUrl(
        playerRequest(mediaId: 77, imdbId: imdbId, season: 3, episode: 5),
      ),
      'https://vidsrc.cc/v2/embed/tv/$imdbId/3/5?poster=true&autoPlay=false',
    );

    final movieMirror = PlayerSources.movie.first;
    const movieRequest = (
      mediaId: 42,
      imdbId: null,
      season: 1,
      episode: 1,
      autoPlay: true,
    );
    expect(
      movieMirror.matchesPlayerUrl(
        Uri.parse(movieMirror.buildUrl(movieRequest)),
        movieRequest,
      ),
      isTrue,
    );
    expect(
      movieMirror.matchesPlayerUrl(
        Uri.parse('https://ads.example/landing'),
        movieRequest,
      ),
      isFalse,
    );

    // The autoplay parameters are playback preferences, not identity: a URL
    // carrying them still has to read as the same player document.
    expect(
      movieMirror.matchesPlayerUrl(
        Uri.parse(
          movieMirror.buildUrl(playerRequest(mediaId: 42, autoPlay: false)),
        ),
        movieRequest,
      ),
      isTrue,
    );

    // The episode does identify the document, whether the mirror keeps it in
    // the path or in the query string.
    for (final episodeMirror in [
      PlayerSources.tv.first,
      mirrorOn('cinesrc.st', MediaType.tv),
    ]) {
      expect(
        episodeMirror.matchesPlayerUrl(
          Uri.parse(
            episodeMirror.buildUrl(
              playerRequest(mediaId: 77, season: 3, episode: 4),
            ),
          ),
          playerRequest(mediaId: 77, season: 3, episode: 5),
        ),
        isFalse,
        reason: '${episodeMirror.host} must not confuse two episodes',
      );
    }
  });

  test('the request probe is compiled out of a normal build', () {
    // It hooks the page's own fetch/XHR, so it must never ship enabled: only
    // --dart-define=LANTAW_PROBE=true turns it on.
    expect(RequestProbe.isEnabled, isFalse);
    expect(RequestProbe.script(), isNull);
  });

  test('the request probe script addresses the channel it is served on', () {
    // The names reach the script through interpolation; escaping the dollar
    // by accident leaves the literal text there and the probe goes quiet.
    expect(RequestProbe.scriptSource, contains("'lantawProbe'"));
    expect(RequestProbe.scriptSource, contains("'lantaw-probe'"));
    expect(RequestProbe.scriptSource, contains(RequestProbe.handlerName));
    expect(RequestProbe.scriptSource, isNot(contains(r'$handlerName')));
    expect(RequestProbe.scriptSource, isNot(contains(r'$_messageTag')));
    // It has to reach the nested frames the mirrors load their ads into.
    expect(RequestProbe.scriptSource, contains('window.parent.postMessage'));
  });

  test('the filter list compiles to WKWebView content blockers', () {
    // WKWebView has no request interception, so on iOS these rules are the
    // only per-resource ad blocking the player gets.
    final blockers = AdBlocking.compileContentBlockers('''
! comment
||doubleclick.net^
||vidlink.pro/api/mercury^
@@||allowed.example^
||wild*card.example^
||tracker.example^\$script
##.adsbygoogle
''');
    final filters = blockers
        .map((blocker) => blocker.trigger.urlFilter)
        .toList(growable: false);

    // Exceptions, wildcards, option-carrying and cosmetic rules cannot be
    // expressed as content rules, so only the two plain anchors survive.
    expect(filters, hasLength(2));
    expect(
      blockers.every(
        (blocker) => blocker.action.type == ContentBlockerActionType.BLOCK,
      ),
      isTrue,
    );

    final host = RegExp(filters.first);
    expect(host.hasMatch('https://doubleclick.net/'), isTrue);
    expect(host.hasMatch('https://ads.g.doubleclick.net/pagead/x'), isTrue);
    expect(host.hasMatch('http://doubleclick.net:8080/'), isTrue);
    // A longer name that merely contains or begins with the rule's domain is
    // a different site and has to keep loading.
    expect(host.hasMatch('https://evil-doubleclick.net/'), isFalse);
    expect(host.hasMatch('https://doubleclick.net.tracker.example/'), isFalse);

    final path = RegExp(filters.last);
    expect(path.hasMatch('https://vidlink.pro/api/mercury'), isTrue);
    expect(path.hasMatch('https://vidlink.pro/api/mercury?id=1'), isTrue);
    expect(path.hasMatch('https://vidlink.pro/api/stream/9'), isFalse);
  });

  test('the bundled filter list yields only blocking network rules', () {
    final listText = File('assets/adblock/filters.txt').readAsStringSync();
    final blockers = AdBlocking.compileContentBlockers(listText);

    // Every `||host^` line in the list has to reach WKWebView; before these
    // were compiled, iOS enforced two hand-written rules and ignored the rest.
    final networkRules = const LineSplitter()
        .convert(listText)
        .map((line) => line.trim())
        .where((line) => line.startsWith('||'));

    expect(blockers, hasLength(networkRules.length));
    expect(
      blockers.map((blocker) => blocker.trigger.urlFilter),
      containsAll([contains('/api/mercury'), contains('/api/venus')]),
    );
    expect(
      RegExp(
        blockers
            .map((blocker) => blocker.trigger.urlFilter)
            .firstWhere((filter) => filter.contains('popads')),
      ).hasMatch('https://c1.popads.net/pop.js'),
      isTrue,
    );
  });

  test('the observed mirror rules block ads and spare the video', () {
    final blockers = AdBlocking.compileContentBlockers(
      File('assets/adblock/filters.txt').readAsStringSync(),
    );
    final filters = blockers
        .map((blocker) => RegExp(blocker.trigger.urlFilter))
        .toList(growable: false);
    bool blocks(String url) => filters.any((filter) => filter.hasMatch(url));

    // Recorded by the request probe while playing one film per mirror.
    const advertising = [
      'https://484r.com/apu.php?zoneid=11616267&var=11616229',
      'https://041gg.com/500/11064923?oo=1',
      'https://071kk.com/impression/abc?_z=11064924',
      'https://405kk.com/wrr?z=11616267',
      'https://ay267.com/ct?zoneid=11616229',
      'https://bblaa.com/ct?zoneid=11616267',
      'https://llvpn.com/tag.min.js',
      'https://luugy.com/5/11616229/?oo=1',
      'https://92mim.com/tag.min.js?z=11064923',
      'https://vr-gc.com/vignette.min.js?z=11064924',
      'https://tzegilo.com/stattag.js',
      'https://fleraprt.com/log/add?cid=1db9169f',
      'https://aichouphaugn.com/www/images/a5410f85a00aa16ad1bf14effbd8ceb3.png',
      'https://clackafshar.shop/cuid/?f=https%3A%2F%2Fvsembed.ru',
      'https://mc.yandex.ru/watch/98154677',
      'https://mc.yandex.ru/metrika/tag.js',
      'https://scripts.clarity.ms/0.8.69/clarity.js',
      'https://y.clarity.ms/collect',
      'https://static.cloudflareinsights.com/beacon.min.js/v451',
      'https://a.cineflix.st/api/event',
      'https://a2.cineflix.st/api/track',
      'https://cinesrc.st/cdn-cgi/rum?',
      'https://vidlink.pro/api/mercury',
    ];
    for (final url in advertising) {
      expect(blocks(url), isTrue, reason: '$url should be blocked');
    }

    // The other half of the recording: everything the player needs. A rule
    // that catches any of these takes the video down with the ads.
    const playback = [
      'https://nebula.bright67.online/hls/60a002d0/1080p/playlist_007.png',
      'https://nebula.bright67.online/hls/60a002d0/master.m3u8',
      'https://subs.bright67.online/search?id=936075',
      'https://noon.mooncase.online/sacdn/dash/5859222729840280400_0_0_1080'
          '_h265_409/chunk-stream0-00387.m4s',
      'https://cacdn.hakunaymatata.com/subtitle/c351ebf4.srt?Policy=abc',
      'https://cdn.jwplayer.com/libraries/KB5zFt7A.js',
      'https://cinesrc.st/_next/static/chunks/d1cc58c9a36a055b.js',
      'https://cinesrc.st/api/c/bootstrap',
      'https://cinesrc.st/embed/movie/936075',
      'https://vidlink.pro/_next/static/chunks/main-app-55bbd77d.js',
      'https://vidlink.pro/api/b/movie/AAAA?multiLang=0',
      'https://vsembed.ru/assets/sbx.js?v=1786671805',
      'https://api.themoviedb.org/3/movie/936075',
      'https://image.tmdb.org/t/p/w1280/ufSwlnECLoUbBjPrFqEQcWBzHwc.jpg',
      'https://wsrv.nl/?url=https://image.tmdb.org/t/p/w500/x.jpg',
      'https://fonts.googleapis.com/css2?family=Roboto',
    ];
    for (final url in playback) {
      expect(blocks(url), isFalse, reason: '$url must keep loading');
    }
  });

  test('flutter-side fullscreen stays on cinesrc', () {
    final source = MirrorFixes.pageFullscreen.source;

    // The gate is the hostname the page reports, checked before anything
    // else runs: on vidlink or vidsrc this script returns immediately and
    // WebKit's own fullscreen is left exactly as it is.
    expect(source, contains('location.hostname'));
    expect(source, contains("'cinesrc.st'"));
    expect(source, contains("'.cinesrc.st'"));
    expect(source, isNot(contains(r'$_cinesrcHost')));
    final gate = source.indexOf('location.hostname');
    expect(gate, greaterThanOrEqualTo(0));
    // Nothing may be patched above the gate.
    expect(source.substring(0, gate), isNot(contains('Element.prototype')));

    // It has to answer the page truthfully, or the player's own control
    // cannot toggle back out.
    expect(source, contains('requestFullscreen'));
    expect(source, contains('exitFullscreen'));
    expect(source, contains('fullscreenElement'));
    expect(source, contains('fullscreenchange'));
    expect(source, contains(MirrorFixes.fullscreenHandlerName));

    // Flutter needs a way back out for the system back gesture.
    expect(source, contains('__lantawLeaveFullscreen'));
    expect(
      MirrorFixes.leaveFullscreenScript,
      contains('__lantawLeaveFullscreen'),
    );
  });

  test('the scroll drift reset spares pages that really scroll', () {
    final source = MirrorFixes.scrollDrift.source;

    // WebKit leaves the document scrolled 32px after a fullscreen
    // transition, which drags the layout viewport and displaces everything
    // the page positions against it. Resetting the scroll is the fix.
    expect(source, contains('window.scrollTo(0, 0)'));
    expect(source, contains('fullscreenchange'));
    expect(source, contains('orientationchange'));

    // The scroll listener must only fire where there is no scroll range, so
    // a mirror with a real episode list or settings sheet keeps working.
    expect(source, contains('scrollHeight <= root.clientHeight'));
    // Rotation strands a scroll that the scroll handler declined to touch,
    // so the resize has to re-check it.
    expect(source, contains("addEventListener('resize', settleIfPinned)"));

    // Only the top document scrolls the WebView.
    expect(MirrorFixes.scrollDrift.forMainFrameOnly, isTrue);
  });

  test('the playback bridge reports from every frame', () {
    final script = PlaybackBridge.script(autoPlay: true);

    // The mirrors' video lives in a cross-origin frame, so the script has to
    // run there and relay upwards to the frame that owns the Flutter bridge.
    expect(script.forMainFrameOnly, isFalse);
    expect(script.injectionTime, UserScriptInjectionTime.AT_DOCUMENT_START);
    expect(script.source, contains(PlaybackBridge.handlerName));
    expect(script.source, contains('window.parent.postMessage'));
    expect(script.source, contains('const AUTOPLAY = true;'));
    expect(
      PlaybackBridge.script(autoPlay: false).source,
      contains('const AUTOPLAY = false;'),
    );
  });

  test('the playback bridge only accepts its own messages', () {
    expect(
      PlaybackBridge.eventName({'tag': 'lantaw-playback', 'event': 'ENDED'}),
      'ended',
    );
    expect(
      PlaybackBridge.eventName({'tag': 'lantaw-playback', 'event': 'play'}),
      'play',
    );
    // Mirrors post their own advertising traffic across frames; none of it is
    // allowed to advance the episode.
    expect(PlaybackBridge.eventName({'event': 'ended'}), isNull);
    expect(
      PlaybackBridge.eventName({'tag': 'other', 'event': 'ended'}),
      isNull,
    );
    expect(PlaybackBridge.eventName({'tag': 'lantaw-playback'}), isNull);
    expect(PlaybackBridge.eventName('ended'), isNull);
    expect(PlaybackBridge.eventName(null), isNull);
  });

  test('the popup guard runs in every frame at document start', () {
    expect(AdBlocking.popupGuardScript.source, contains("window, 'open'"));
    expect(AdBlocking.popupGuardScript.forMainFrameOnly, isFalse);
    expect(AdBlocking.popupGuardScript.source, contains('background:#000'));
    expect(AdBlocking.popupGuardScript.source, contains('#dontfoid,[znid]'));
  });
}
