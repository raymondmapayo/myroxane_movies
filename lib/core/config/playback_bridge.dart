import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Bridges playback state out of the mirror's page so the player can start
/// titles by itself and roll on to the next episode when one finishes.
///
/// The mirrors bury their `<video>` several cross-origin frames deep, so the
/// script runs in every frame: a frame that owns a video reports on it, and
/// frames in between relay the message up until the main frame — the only one
/// with the InAppWebView JavaScript bridge — hands it to Flutter.
abstract final class PlaybackBridge {
  static const handlerName = 'lantawPlayback';

  /// Marks messages this script sends, so relaying frames can tell them apart
  /// from the advertising chatter mirrors post at each other.
  static const _messageTag = 'lantaw-playback';

  static UserScript script({required bool autoPlay}) => UserScript(
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    forMainFrameOnly: false,
    source:
        '''
      (() => {
        const CHANNEL = '$handlerName';
        const TAG = '$_messageTag';
        const AUTOPLAY = $autoPlay;
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

        const report = (event, currentTime, duration) => deliver({
          tag: TAG,
          event: event,
          currentTime: Number(currentTime) || 0,
          duration: Number(duration) || 0,
        });

        window.addEventListener('message', (e) => {
          const data = e && e.data;
          if (!data || typeof data !== 'object') return;

          if (data.tag === TAG) {
            // One of our own frames; pass it one level closer to Flutter.
            if (e.source !== window) deliver(data);
            return;
          }

          // cinesrc and vidlink publish their player state as postMessage
          // events. Reading them is more reliable than reaching into the
          // cross-origin document, which the browser forbids anyway.
          const type = String(data.type || '').toUpperCase();
          if (type !== 'PLAYER_EVENT' && type !== 'MEDIA_DATA') return;
          const payload =
            data.data && typeof data.data === 'object' ? data.data : data;
          const name = String(payload.event || payload.state || '')
            .toLowerCase();
          if (!name) return;
          report(name, payload.currentTime, payload.duration);
        });

        const tracked = new WeakSet();
        const mutedForPolicy = [];

        const attemptPlay = (video) => {
          let promise;
          try { promise = video.play(); } catch (_) { return; }
          if (!promise || !promise.catch) return;
          promise.catch(() => {
            // Some engines still demand a gesture for audible playback. Start
            // muted and lift it on the first touch rather than leaving the
            // viewer on a frozen first frame.
            try { video.muted = true; } catch (_) {}
            mutedForPolicy.push(video);
            let retry;
            try { retry = video.play(); } catch (_) { return; }
            if (retry && retry.catch) retry.catch(() => {});
          });
        };

        const unmute = () => {
          while (mutedForPolicy.length) {
            const video = mutedForPolicy.pop();
            try { video.muted = false; } catch (_) {}
          }
        };
        ['touchstart', 'click', 'keydown'].forEach((type) => {
          document.addEventListener(type, unmute, {
            capture: true,
            passive: true,
          });
        });

        const track = (video) => {
          if (tracked.has(video)) return;
          tracked.add(video);

          const finish = () => {
            if (video.lantawEnded) return;
            video.lantawEnded = true;
            report('ended', video.currentTime, video.duration);
          };

          video.addEventListener('ended', finish);
          video.addEventListener('play', () => {
            video.lantawEnded = false;
            report('play', video.currentTime, video.duration);
          });
          video.addEventListener('timeupdate', () => {
            const duration = video.duration;
            if (!isFinite(duration) || duration <= 0) return;
            // Several mirrors tear the element down before firing `ended`.
            if (duration - video.currentTime <= 0.75) finish();
          });

          if (AUTOPLAY) attemptPlay(video);
        };

        const scan = () => {
          const videos = document.getElementsByTagName('video');
          for (let i = 0; i < videos.length; i++) track(videos[i]);
        };

        const start = () => {
          scan();
          try {
            new MutationObserver(scan).observe(document.documentElement, {
              childList: true,
              subtree: true,
            });
          } catch (_) {}
          // Mirrors mount the video long after DOMContentLoaded and rebuild it
          // on quality switches, so keep looking for a while.
          let ticks = 0;
          const timer = setInterval(() => {
            scan();
            if (++ticks > 60) clearInterval(timer);
          }, 500);
        };

        if (document.readyState === 'loading') {
          document.addEventListener('DOMContentLoaded', start);
        } else {
          start();
        }
      })();
    ''',
  );

  /// Normalizes one bridge message into the event name it reports, or null
  /// when the payload is not one of ours.
  static String? eventName(Object? message) {
    if (message is! Map) return null;
    if (message['tag'] != _messageTag) return null;
    final event = message['event'];
    return event is String && event.isNotEmpty ? event.toLowerCase() : null;
  }
}
