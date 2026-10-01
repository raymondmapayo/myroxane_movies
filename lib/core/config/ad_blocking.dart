import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:lantaw_adblock/lantaw_adblock.dart';

/// Ad blocking backed by Brave's `adblock-rust` matching engine (via the
/// local `lantaw_adblock` Rust/FFI plugin), instead of a hand-rolled host
/// list and DOM sweep.
///
/// Filter rules live in `assets/adblock/filters.txt` (Adblock Plus /
/// uBlock Origin syntax).
///
/// Every layer runs on every platform, but network blocking needs two
/// different mechanisms to get there:
/// - Navigations (top-level redirects, click-through ads, popup attempts)
///   are checked everywhere via [shouldBlockNavigation].
/// - Cosmetic filtering (hiding leftover ad containers) is checked
///   everywhere via [cosmeticHidingScript].
/// - Per-resource network blocking (images/scripts/iframes loaded by the
///   page itself, not navigations) runs imperatively on Android/Windows via
///   [interceptRequest]. WKWebView (iOS/macOS) exposes no imperative
///   request-interception API, so there the same rules are compiled to a
///   declarative `WKContentRuleList` by [webViewContentBlockers].
abstract final class AdBlocking {
  static const _assetPath = 'assets/adblock/filters.txt';

  static List<ContentBlocker> _contentBlockers = const <ContentBlocker>[];

  /// The filter list's network rules compiled for WKWebView's declarative
  /// content blocking.
  ///
  /// On iOS/macOS this is the only thing standing between the mirror page and
  /// its advertising and popunder scripts, because [interceptRequest] cannot
  /// run there. Those scripts poll on timers and keep re-inserting frames
  /// once they are loaded, and they share a web content process with the
  /// video, so leaving them unblocked makes playback hitch every few seconds.
  /// WebKit applies these rules inside the content process before a request
  /// is issued, so unlike [interceptRequest] they cost no per-request
  /// platform-channel round trip.
  ///
  /// Empty until [ensureInitialized] completes. A WebView reads this only
  /// when it is created, so create the player's WebView after awaiting that.
  static List<ContentBlocker> get webViewContentBlockers => _contentBlockers;

  // Mirror scripts invoke window.open after the first player interaction.
  // Refuse it inside the page as well as in the native onCreateWindow hook so
  // the popup cannot briefly replace or blank the current WKWebView.
  static final popupGuardScript = UserScript(
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    // Mirror 3 places both its real player and its popunder code several
    // cross-origin frames below the provider page. WKWebView defaults this to
    // the main frame, which leaves those nested frames unprotected.
    forMainFrameOnly: false,
    source: '''
      (() => {
        // Aclib's runPop script creates this transparent, full-player element
        // (the `znid` value is its ad-zone id) to consume taps before the real
        // controls receive them. A document-start rule also catches elements
        // inserted later, without removing any of the player's own controls.
        const style = document.createElement('style');
        style.textContent =
          'html,body{background:#000!important;color-scheme:dark}' +
          '#dontfoid,[znid]{display:none!important;pointer-events:none!important}';
        document.documentElement.appendChild(style);

        const denyPopup = () => null;
        try {
          Object.defineProperty(window, 'open', {
            value: denyPopup,
            writable: false,
            configurable: false,
          });
        } catch (_) {
          try { window.open = denyPopup; } catch (_) {}
        }
      })();
    ''',
  );

  static AdblockEngine? _engine;
  static Future<void>? _initFuture;

  /// Loads the Rust library and the bundled filter list. Safe to call more
  /// than once; the work only happens on the first call.
  static Future<void> ensureInitialized() => _initFuture ??= _initialize();

  static Future<void> _initialize() async {
    await RustLib.init();
    final listText = await rootBundle.loadString(_assetPath);
    _engine = AdblockEngine.fromListText(listText: listText);
    _contentBlockers = compileContentBlockers(listText);
  }

  /// Translates the filter list's domain-anchored network rules (`||host^`
  /// and `||host/path^`) into content blocker triggers.
  ///
  /// Rules carrying wildcards, options (`$script`), exceptions (`@@`) or
  /// cosmetic syntax are skipped: `WKContentRuleList` cannot express them,
  /// and [interceptRequest] still applies them in full on the platforms that
  /// have it. A rule WebKit rejects would invalidate the whole compiled list,
  /// so only shapes that translate exactly are emitted.
  @visibleForTesting
  static List<ContentBlocker> compileContentBlockers(String listText) {
    final blockers = <ContentBlocker>[];
    final seen = <String>{};
    for (final rawLine in const LineSplitter().convert(listText)) {
      final line = rawLine.trim();
      if (!line.startsWith('||')) continue;
      if (line.contains('#') || line.contains(r'$') || line.contains('*')) {
        continue;
      }
      final urlFilter = _domainAnchorUrlFilter(line.substring(2));
      if (urlFilter == null || !seen.add(urlFilter)) continue;
      blockers.add(
        ContentBlocker(
          trigger: ContentBlockerTrigger(urlFilter: urlFilter),
          action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
        ),
      );
    }
    return List.unmodifiable(blockers);
  }

  static final _hostPattern = RegExp(r'^[a-z0-9.-]+$');

  // `/` is deliberately absent: it carries no meaning in a regular
  // expression, and WebKit is stricter than Dart about identity escapes.
  static final _regExpMetaPattern = RegExp(r'[.*+?^${}()|[\]\\]');

  static String _escapeRegExp(String value) =>
      value.replaceAllMapped(_regExpMetaPattern, (match) => '\\${match[0]}');

  /// Builds the `url-filter` regular expression for one `||...` rule body,
  /// or null when the rule is not a plain domain anchor.
  ///
  /// WebKit accepts only a restricted regular expression dialect for content
  /// rules, so this stays within character classes, groups and the three
  /// basic quantifiers.
  static String? _domainAnchorUrlFilter(String body) {
    var rule = body;
    if (rule.endsWith('^')) rule = rule.substring(0, rule.length - 1);
    if (rule.isEmpty) return null;

    final slash = rule.indexOf('/');
    final host = (slash == -1 ? rule : rule.substring(0, slash)).toLowerCase();
    final path = slash == -1 ? '' : rule.substring(slash);
    if (!_hostPattern.hasMatch(host)) return null;

    // The optional leading group covers subdomains. Because it has to end in
    // a dot, `||doubleclick.net^` still cannot match `evil-doubleclick.net`.
    final pattern = StringBuffer(r'^https?://([a-z0-9_.-]+\.)?')
      ..write(_escapeRegExp(host));
    if (path.isEmpty) {
      // Requiring a separator or the end of the URL after the host keeps the
      // rule off a longer domain that merely begins with it, such as
      // `doubleclick.net.tracker.example`.
      pattern.write(r'([/:?#].*)?$');
    } else {
      pattern.write(_escapeRegExp(path));
    }
    return pattern.toString();
  }

  static AdblockEngine get _requireEngine {
    final engine = _engine;
    assert(
      engine != null,
      'AdBlocking.ensureInitialized() must complete before use.',
    );
    return engine ?? (throw StateError('AdBlocking is not initialized.'));
  }

  // Blocked ad scripts retry the same destination on a timer. Each lookup is
  // a synchronous FFI call made from the platform's navigation callback, and
  // on iOS that callback runs on the thread platform view compositing is
  // synchronised with, so a burst of repeats stalls the video. Memoising is
  // safe because the engine never changes after it is built; map literals
  // keep insertion order, so the eviction below drops the oldest entry.
  static final _navigationDecisions = <String, bool>{};
  static const _navigationDecisionLimit = 512;

  static bool shouldBlockNavigation({
    required Uri url,
    required Uri sourceUrl,
  }) {
    if (_engine == null) return false;

    final key = '$sourceUrl\u0000$url';
    final cached = _navigationDecisions[key];
    if (cached != null) return cached;

    final blocked = _requireEngine.shouldBlock(
      url: url.toString(),
      sourceUrl: sourceUrl.toString(),
      requestType: 'document',
    );
    if (_navigationDecisions.length >= _navigationDecisionLimit) {
      _navigationDecisions.remove(_navigationDecisions.keys.first);
    }
    _navigationDecisions[key] = blocked;
    return blocked;
  }

  /// Diagnostics only: would the engine block this request as the list stands
  /// today? The request probe uses it to separate what is already covered from
  /// what a new rule would have to catch.
  static bool wouldBlock({
    required Uri url,
    required Uri sourceUrl,
    required String requestType,
  }) {
    if (_engine == null) return false;
    return _requireEngine.shouldBlock(
      url: url.toString(),
      sourceUrl: sourceUrl.toString(),
      requestType: requestType,
    );
  }

  /// Android/Windows only (see class docs): decide whether to short-circuit
  /// a sub-resource request the page itself makes.
  static WebResourceResponse? interceptRequest({
    required Uri url,
    required Uri sourceUrl,
  }) {
    if (_engine == null) return null;
    final blocked = _requireEngine.shouldBlock(
      url: url.toString(),
      sourceUrl: sourceUrl.toString(),
      requestType: 'other',
    );
    if (!blocked) return null;
    return WebResourceResponse(contentType: 'text/plain', data: Uint8List(0));
  }

  /// A UserScript that hides elements matched by cosmetic filter rules for
  /// [pageUrl]. Returns null if there's nothing to hide.
  static UserScript? cosmeticHidingScript(Uri pageUrl) {
    if (_engine == null) return null;
    final selectors = _requireEngine.cosmeticHideSelectors(
      url: pageUrl.toString(),
    );
    if (selectors.isEmpty) return null;

    final css = selectors
        .map((selector) => '$selector{display:none!important}')
        .join();
    // jsonEncode produces a double-quoted string with valid JS escaping,
    // so it's safe to splice directly into the script regardless of what
    // characters (quotes, backslashes, ...) a selector contains.
    final jsStringLiteral = jsonEncode(css);
    return UserScript(
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      // Generic cosmetic rules must reach the actual player iframe rather
      // than only the outer mirror document.
      forMainFrameOnly: false,
      source:
          '''
        (() => {
          const style = document.createElement('style');
          style.textContent = $jsStringLiteral;
          document.documentElement.appendChild(style);
        })();
      ''',
    );
  }
}
