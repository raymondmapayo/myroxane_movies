import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'ad_blocking.dart';

/// Diagnostic-only: records every URL a mirror's page reaches for, so the
/// filter list can be written from what the hosts actually request instead of
/// from guesswork.
///
/// WKWebView exposes no request interception, so on iOS the requests a page
/// makes are invisible to Dart. This hooks the page's own networking in every
/// frame instead and relays what it sees up to Flutter, the same way
/// [PlaybackBridge] relays playback state.
///
/// Off unless the build was started with `--dart-define=LANTAW_PROBE=true`:
/// hooking `fetch` and `XMLHttpRequest` changes how the page behaves, so it
/// must not be able to reach a normal build. Run it with:
///
/// ```sh
/// ./tool/run_lantaw.sh --dart-define=LANTAW_PROBE=true
/// ```
///
/// Then play a few minutes on each mirror and read the `PROBE` lines off the
/// log. `blocked=no` marks the requests the current list misses — those are
/// the candidates for new rules.
abstract final class RequestProbe {
  static const handlerName = 'lantawProbe';

  /// Marks the probe's own messages so relaying frames can tell them apart
  /// from whatever else the page posts around.
  static const _messageTag = 'lantaw-probe';

  /// Compile-time gate, so a normal build carries no probe at all.
  static const isEnabled = bool.fromEnvironment('LANTAW_PROBE');

  /// URLs already reported. Mirrors re-request the same endpoints on a timer,
  /// and each frame keeps its own set, so the log needs one more filter to
  /// stay readable across a whole session.
  static final _seen = <String>{};

  /// The injected script, whether or not the probe is enabled. The gate makes
  /// [script] unreachable in a normal build, so the source needs its own way
  /// out to be tested.
  @visibleForTesting
  static String get scriptSource => _source;

  static UserScript? script() => isEnabled
      ? UserScript(
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: false,
          source: _source,
        )
      : null;

  /// Handles one reported URL: dedupes it, asks the engine whether the
  /// current list already covers it, and prints one greppable line.
  static void record(List<dynamic> arguments) {
    final message = arguments.isEmpty ? null : arguments.first;
    if (message is! Map || message['tag'] != _messageTag) return;

    final frameUrl = message['frame'];
    final reportingPage = frameUrl is String ? Uri.tryParse(frameUrl) : null;

    // Layout reports describe the same page repeatedly, by design.
    if (message['kind'] == 'fullscreen') {
      final detail = message['detail'];
      if (detail is! String || detail.isEmpty) return;
      debugPrint('PROBE-FS page=${reportingPage?.host ?? '?'} $detail');
      return;
    }

    final url = message['url'];
    if (url is! String || url.isEmpty || !_seen.add(url)) return;

    final target = Uri.tryParse(url);
    if (target == null) return;
    final page = reportingPage;

    // A request is only judged against the frame that made it, because
    // first-party rules turn on exactly that relationship.
    final blocked =
        page != null &&
        AdBlocking.wouldBlock(
          url: target,
          sourceUrl: page,
          requestType: 'other',
        );

    final kind = message['kind'];
    debugPrint(
      'PROBE '
      'blocked=${blocked ? 'yes' : 'no'} '
      'kind=${kind is String && kind.isNotEmpty ? kind : '?'} '
      'page=${page?.host ?? '?'} '
      'url=$url',
    );
  }

  static const _source =
      '''
      (() => {
        const CHANNEL = '$handlerName';
        const TAG = '$_messageTag';
        const isTop = window.top === window;

        const deliver = (message) => {
          if (isTop) {
            try {
              const bridge = window.flutter_inappwebview;
              if (bridge && bridge.callHandler) {
                bridge.callHandler(CHANNEL, message);
              }
            } catch (_) {}
            return;
          }
          try { window.parent.postMessage(message, '*'); } catch (_) {}
        };

        const seen = new Set();
        const report = (kind, value) => {
          if (!value) return;
          let url;
          try {
            url = new URL(String(value), document.baseURI).href;
          } catch (_) {
            return;
          }
          if (!/^https?:/.test(url)) return;
          if (seen.has(url)) return;
          seen.add(url);
          deliver({ tag: TAG, kind: kind, url: url, frame: location.href });
        };

        window.addEventListener('message', (e) => {
          const data = e && e.data;
          if (!data || typeof data !== 'object' || data.tag !== TAG) return;
          // A child frame's find, on its way up to the main frame's bridge.
          if (e.source !== window) deliver(data);
        });

        // Fullscreen diagnostics. A player lays its video and controls out
        // against the viewport it can measure; if the platform paints that
        // element at a different size, everything lands off. These samples
        // say whether the two agree.
        const geometry = (phase) => {
          const parts = ['phase=' + phase];
          try {
            const fullscreenElement =
              document.fullscreenElement ||
              document.webkitFullscreenElement ||
              document.webkitCurrentFullScreenElement ||
              null;
            const viewport = window.visualViewport;
            const video = document.querySelector('video');
            const box = video ? video.getBoundingClientRect() : null;
            const round = (value) => Math.round(Number(value) || 0);

            parts.push('inner=' + window.innerWidth + 'x' + window.innerHeight);
            parts.push('screen=' + screen.width + 'x' + screen.height);
            parts.push(
              'visual=' +
                (viewport
                  ? round(viewport.width) +
                    'x' +
                    round(viewport.height) +
                    '@' +
                    (viewport.scale || 1)
                  : 'none'),
            );
            parts.push('dpr=' + (window.devicePixelRatio || 1));
            // The decisive pair: scroll position is what a page can control,
            // while the visual viewport's offset from the layout viewport is
            // what iOS moves on its own and no page can set.
            parts.push(
              'scroll=' + round(window.scrollX) + ',' + round(window.scrollY),
            );
            parts.push(
              'docScroll=' +
                round(
                  document.documentElement
                    ? document.documentElement.scrollTop
                    : 0,
                ),
            );
            parts.push(
              'vvOffset=' +
                (viewport
                  ? round(viewport.offsetLeft) + ',' + round(viewport.offsetTop)
                  : 'none'),
            );
            parts.push(
              'vvPage=' +
                (viewport
                  ? round(viewport.pageLeft) + ',' + round(viewport.pageTop)
                  : 'none'),
            );
            parts.push(
              'docHeight=' +
                (document.documentElement
                  ? document.documentElement.clientHeight +
                    '/' +
                    document.documentElement.scrollHeight
                  : 'none'),
            );
            parts.push(
              'fsEl=' +
                (fullscreenElement
                  ? fullscreenElement.tagName +
                    '.' +
                    String(fullscreenElement.className || '')
                      .split(' ')
                      .filter(Boolean)
                      .slice(0, 2)
                      .join('.')
                  : 'none'),
            );
            parts.push(
              'videoBox=' +
                (box
                  ? round(box.width) +
                    'x' +
                    round(box.height) +
                    '@' +
                    round(box.left) +
                    ',' +
                    round(box.top)
                  : 'none'),
            );
            parts.push(
              'videoPx=' +
                (video ? video.videoWidth + 'x' + video.videoHeight : 'none'),
            );
            parts.push(
              'orient=' +
                (screen.orientation ? screen.orientation.type : 'unknown'),
            );
          } catch (error) {
            parts.push('error=' + error);
          }
          deliver({
            tag: TAG,
            kind: 'fullscreen',
            detail: parts.join(' '),
            frame: location.href,
          });
        };

        // Which element actually carries an offset is the whole question, so
        // walk from the video up to the fullscreen container and report each
        // one's box and the properties that could be moving it.
        const chain = (phase) => {
          let video;
          try {
            video = document.querySelector('video');
          } catch (_) {
            return;
          }
          if (!video) return;

          const round = (value) => Math.round(Number(value) || 0);
          let node = video;
          let depth = 0;
          while (node && depth < 6) {
            try {
              const box = node.getBoundingClientRect();
              const computed = getComputedStyle(node);
              const name =
                node.tagName +
                (node.className
                  ? '.' +
                    String(node.className)
                      .split(' ')
                      .filter(Boolean)
                      .slice(0, 2)
                      .join('.')
                  : '');
              deliver({
                tag: TAG,
                kind: 'fullscreen',
                detail:
                  'chain=' + phase +
                  ' depth=' + depth +
                  ' el=' + name +
                  ' box=' + round(box.width) + 'x' + round(box.height) +
                  '@' + round(box.left) + ',' + round(box.top) +
                  ' pos=' + computed.position +
                  ' top=' + computed.top +
                  ' mt=' + computed.marginTop +
                  ' h=' + computed.height +
                  ' inset=' + (computed.inset || '-') +
                  ' tf=' +
                  (computed.transform === 'none'
                    ? 'none'
                    : String(computed.transform).slice(0, 32)) +
                  ' of=' + computed.objectFit +
                  ' inline=' + String(node.getAttribute('style') || '-')
                    .slice(0, 60),
                frame: location.href,
              });
            } catch (_) {}
            node = node.parentElement;
            depth++;
          }
        };

        // The platform animates the transition, so one sample right on the
        // event would only catch the geometry mid-flight.
        const sample = (phase) => {
          geometry(phase);
          setTimeout(() => geometry(phase + '+400'), 400);
          setTimeout(() => {
            geometry(phase + '+1200');
            // One settled walk per transition; every frame would be noise.
            chain(phase + '+1200');
          }, 1200);
        };

        const onFullscreenChange = () => {
          const active =
            document.fullscreenElement ||
            document.webkitFullscreenElement ||
            document.webkitCurrentFullScreenElement;
          sample(active ? 'enter' : 'exit');
        };

        document.addEventListener('fullscreenchange', onFullscreenChange);
        document.addEventListener('webkitfullscreenchange', onFullscreenChange);
        document.addEventListener(
          'webkitbeginfullscreen',
          () => sample('ios-begin'),
          true,
        );
        document.addEventListener(
          'webkitendfullscreen',
          () => sample('ios-end'),
          true,
        );
        window.addEventListener('orientationchange', () => sample('rotate'));

        // Baseline, once the player has had time to build itself.
        setTimeout(() => geometry('baseline'), 4000);

        const hook = (owner, name, kind, pick) => {
          if (!owner) return;
          const original = owner[name];
          if (typeof original !== 'function') return;
          owner[name] = function (...args) {
            try { report(kind, pick(args)); } catch (_) {}
            return original.apply(this, args);
          };
        };

        hook(window, 'fetch', 'fetch', (args) => {
          const input = args[0];
          return typeof input === 'string' ? input : input && input.url;
        });
        hook(
          window.XMLHttpRequest && XMLHttpRequest.prototype,
          'open',
          'xhr',
          (args) => args[1],
        );
        hook(navigator, 'sendBeacon', 'beacon', (args) => args[0]);

        // Popunder scripts open sockets to keep their session alive.
        try {
          const OriginalSocket = window.WebSocket;
          if (typeof OriginalSocket === 'function') {
            const Wrapped = function (url, ...rest) {
              try { report('websocket', url); } catch (_) {}
              return new OriginalSocket(url, ...rest);
            };
            Wrapped.prototype = OriginalSocket.prototype;
            window.WebSocket = Wrapped;
          }
        } catch (_) {}

        // Everything else arrives as markup: the ad frames and the scripts
        // that write them are inserted into the DOM rather than fetched.
        const SOURCE_ATTRIBUTE = {
          SCRIPT: 'src',
          IFRAME: 'src',
          IMG: 'src',
          LINK: 'href',
          EMBED: 'src',
          SOURCE: 'src',
          VIDEO: 'src',
        };
        const SELECTOR =
          'script[src],iframe[src],img[src],link[href],embed[src],' +
          'source[src],video[src]';

        const inspect = (node) => {
          if (!node || node.nodeType !== 1) return;
          const attribute = SOURCE_ATTRIBUTE[node.tagName];
          if (attribute) {
            try {
              report(node.tagName.toLowerCase(), node.getAttribute(attribute));
            } catch (_) {}
          }
          if (!node.querySelectorAll) return;
          try {
            for (const child of node.querySelectorAll(SELECTOR)) inspect(child);
          } catch (_) {}
        };

        try {
          new MutationObserver((records) => {
            for (const record of records) {
              for (const node of record.addedNodes) inspect(node);
            }
          }).observe(document.documentElement, {
            childList: true,
            subtree: true,
          });
        } catch (_) {}

        const sweep = () => {
          try { inspect(document.documentElement); } catch (_) {}
        };
        if (document.readyState === 'loading') {
          document.addEventListener('DOMContentLoaded', sweep);
        } else {
          sweep();
        }
      })();
    ''';
}
