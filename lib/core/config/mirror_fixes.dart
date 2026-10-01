import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Corrections for layout bugs inside one mirror's own page.
///
/// Every fix here gates itself on `location.hostname` from inside the script,
/// never on which mirror Flutter thinks is playing. User scripts are fixed
/// when the WebView is created, so a check on the Dart side would both miss
/// the mirror a viewer switches to later and risk applying to mirrors the fix
/// was never measured against.
abstract final class MirrorFixes {
  /// Channel the page uses to tell Flutter it wants the whole screen.
  static const fullscreenHandlerName = 'lantawFullscreen';

  /// Host whose fullscreen Flutter takes over. Nothing else is affected.
  static const _cinesrcHost = 'cinesrc.st';

  /// Puts the page back inline when Flutter leaves fullscreen first — the
  /// system back gesture, or the viewer leaving the player altogether.
  static const leaveFullscreenScript =
      'try { window.__lantawLeaveFullscreen && window.__lantawLeaveFullscreen(); }'
      ' catch (e) {}';

  /// Takes fullscreen away from WebKit on cinesrc.st and hands it to Flutter.
  ///
  /// WebKit owns the geometry of its own fullscreen presentation and will not
  /// share it. Measured on iPad: the page is given a viewport ~97pt shorter
  /// than the screen, so the bottom of the screen stays black; about half of
  /// transitions also leave the document reporting a 32px scroll that
  /// `scrollTo(0, 0)` does not clear; and the user-agent stylesheet pins the
  /// fullscreen element with `!important` rules that outrank even an inline
  /// style. None of that is reachable from the page.
  ///
  /// So the page never enters WebKit fullscreen at all. `requestFullscreen`
  /// is answered by styling the element to fill the viewport and telling
  /// Flutter to grow the WebView to the whole screen — which makes that
  /// viewport genuinely full screen. `document.fullscreenElement` and the
  /// change events are kept truthful so the player's own control still
  /// toggles.
  static final pageFullscreen = UserScript(
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    // The bridge only exists in the main frame, and this mirror builds its
    // player there.
    forMainFrameOnly: true,
    source:
        '''
      (() => {
        const host = String(location.hostname || '').toLowerCase();
        if (host !== '$_cinesrcHost' && !host.endsWith('.$_cinesrcHost')) {
          return;
        }

        const CHANNEL = '$fullscreenHandlerName';
        const FILL = 'lantaw-fullscreen';
        const LOCK = 'lantaw-fullscreen-root';
        let active = null;

        const tell = (state) => {
          try {
            const bridge = window.flutter_inappwebview;
            if (bridge && bridge.callHandler) {
              bridge.callHandler(CHANNEL, { state: state });
            }
          } catch (_) {}
        };

        const addStyle = () => {
          if (document.getElementById(FILL)) return;
          const style = document.createElement('style');
          style.id = FILL;
          style.textContent =
            '.' + FILL + '{position:fixed!important;inset:0!important;' +
            'width:100%!important;height:100%!important;' +
            'max-width:none!important;max-height:none!important;' +
            'margin:0!important;z-index:2147483647!important;' +
            'background:#000!important}' +
            '.' + LOCK + '{overflow:hidden!important;margin:0!important;' +
            'padding:0!important}';
          try {
            (document.head || document.documentElement).appendChild(style);
          } catch (_) {}
        };

        // Players swap their enter/exit control on these.
        const announce = () => {
          for (const name of ['fullscreenchange', 'webkitfullscreenchange']) {
            try {
              document.dispatchEvent(new Event(name));
            } catch (_) {}
          }
        };

        const root = () => [document.documentElement, document.body];

        const leave = () => {
          if (!active) return;
          try {
            active.classList.remove(FILL);
            for (const node of root()) {
              if (node) node.classList.remove(LOCK);
            }
          } catch (_) {}
          active = null;
          tell('exit');
          announce();
        };

        const enter = (element) => {
          if (!element || active === element) return;
          if (active) leave();
          addStyle();
          active = element;
          try {
            element.classList.add(FILL);
            for (const node of root()) {
              if (node) node.classList.add(LOCK);
            }
          } catch (_) {}
          tell('enter');
          announce();
        };

        // The player asks the document which element is fullscreen; answer
        // for the one we are filling rather than leaving it null.
        for (const name of ['fullscreenElement', 'webkitFullscreenElement']) {
          try {
            Object.defineProperty(document, name, {
              configurable: true,
              get: () => active,
            });
          } catch (_) {}
        }

        for (const name of [
          'requestFullscreen',
          'webkitRequestFullscreen',
          'webkitRequestFullScreen',
        ]) {
          try {
            Element.prototype[name] = function () {
              enter(this);
              return Promise.resolve();
            };
          } catch (_) {}
        }

        for (const name of [
          'exitFullscreen',
          'webkitExitFullscreen',
          'webkitCancelFullScreen',
        ]) {
          try {
            document[name] = function () {
              leave();
              return Promise.resolve();
            };
          } catch (_) {}
        }

        window.__lantawLeaveFullscreen = leave;
      })();
    ''',
  );

  /// Puts the document back to the top of the WebView when it has drifted.
  ///
  /// On a fresh load every mirror measures correctly — the viewport matches
  /// the WebView and the content sits at the origin. Coming back from
  /// fullscreen, WebKit leaves the page scrolled down by a constant amount
  /// (32px on iPad) and never restores it, so from then on the layout
  /// viewport that `position: fixed` resolves against sits above the visible
  /// one. Everything on the page is drawn that far too high, which is why it
  /// showed up on cinesrc and vidlink alike and only after a fullscreen
  /// round trip.
  ///
  /// This resets the scroll instead of disabling it: a mirror that genuinely
  /// needs to scroll — an episode list, a settings sheet — keeps working, and
  /// the reset only fires on the transitions that cause the drift.
  static final scrollDrift = UserScript(
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    // Only the top document scrolls the WebView itself.
    forMainFrameOnly: true,
    source: '''
      (() => {
        // A page with real scrollable content must keep scrolling; the reset
        // only fires where there is no scroll range to be at 32 in the first
        // place.
        const settleIfPinned = () => {
          try {
            const root = document.documentElement;
            if (!root) return;
            if (root.scrollHeight <= root.clientHeight + 1) settle();
          } catch (_) {}
        };

        const settle = () => {
          try {
            if (window.scrollY !== 0 || window.scrollX !== 0) {
              window.scrollTo(0, 0);
            }
          } catch (_) {}
        };

        // WebKit applies the drift partway through the transition and holds
        // the offset without emitting a scroll event, so neither listener
        // below gets a chance at it. Fixed timers raced that: whether they
        // caught it depended on when in the animation the drift landed.
        // Watching for a short while instead catches it whenever it appears.
        let watchTimer = null;
        const settleUntil = (durationMs) => {
          if (watchTimer) clearInterval(watchTimer);
          const deadline = Date.now() + durationMs;
          settleIfPinned();
          watchTimer = setInterval(() => {
            settleIfPinned();
            if (Date.now() >= deadline) {
              clearInterval(watchTimer);
              watchTimer = null;
            }
          }, 100);
        };

        const settleSoon = () => settleUntil(2000);

        window.addEventListener('scroll', settleIfPinned, { passive: true });
        // Rotating scrolls the document while it still has room to scroll, so
        // the check above rightly declines. A moment later the document has
        // resized to fit and the scroll is stranded, with no further scroll
        // event to catch it — this is what notices that.
        window.addEventListener('resize', settleIfPinned);

        document.addEventListener('fullscreenchange', settleSoon);
        document.addEventListener('webkitfullscreenchange', settleSoon);
        document.addEventListener('webkitendfullscreen', settleSoon, true);
        window.addEventListener('orientationchange', settleSoon);
      })();
    ''',
  );
}
