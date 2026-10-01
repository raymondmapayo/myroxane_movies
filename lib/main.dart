import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'core/config/ad_blocking.dart';
import 'core/theme/app_theme.dart';
import 'data/datasources/tmdb_remote_data_source.dart';
import 'data/repositories/tmdb_media_repository.dart';
import 'domain/entities/media.dart';
import 'domain/repositories/media_repository.dart';
import 'domain/usecases/media_usecases.dart';
import 'presentation/viewmodels/catalog_view_model.dart';
import 'presentation/viewmodels/home_view_model.dart';
import 'presentation/viewmodels/search_view_model.dart';
import 'presentation/views/browse_view.dart';
import 'presentation/views/catalog_view.dart';
import 'presentation/views/home_view.dart';
import 'presentation/views/search_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = TmdbMediaRepository(TmdbRemoteDataSource(http.Client()));
  runApp(LantawApp(repository: repository));
  unawaited(_initializeOptionalServices());
}

Future<void> _initializeOptionalServices() async {
  try {
    await AdBlocking.ensureInitialized();
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'lantaw startup',
        context: ErrorDescription('initializing the ad-block engine'),
      ),
    );
  }
}

class LantawApp extends StatelessWidget {
  const LantawApp({super.key, required this.repository});
  final MediaRepository repository;

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      Provider<GetHomeFeed>(create: (_) => GetHomeFeed(repository)),
      Provider<DiscoverMedia>(create: (_) => DiscoverMedia(repository)),
      Provider<SearchMedia>(create: (_) => SearchMedia(repository)),
      Provider<GetMediaDetails>(create: (_) => GetMediaDetails(repository)),
    ],
    child: MaterialApp(
      title: 'My Roxane Movies',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const AppShell(),
    ),
  );
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final discover = context.read<DiscoverMedia>();
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          ChangeNotifierProvider(
            create: (_) => HomeViewModel(context.read<GetHomeFeed>())..load(),
            child: HomeView(
              onOpenSearch: () => setState(() => _index = 4),
              onOpenBrowse: () => setState(() => _index = 3),
            ),
          ),
          ChangeNotifierProvider(
            create: (_) =>
                CatalogViewModel(discover, type: MediaType.movie)..load(),
            child: const CatalogView(title: 'Movies', type: MediaType.movie),
          ),
          ChangeNotifierProvider(
            create: (_) =>
                CatalogViewModel(discover, type: MediaType.tv)..load(),
            child: const CatalogView(title: 'Series', type: MediaType.tv),
          ),
          ChangeNotifierProvider(
            create: (_) =>
                CatalogViewModel(discover, type: MediaType.movie)..load(),
            child: const BrowseView(),
          ),
          ChangeNotifierProvider(
            create: (_) => SearchViewModel(context.read<SearchMedia>()),
            child: const SearchView(),
          ),
        ],
      ),
      bottomNavigationBar: _LantawNavigation(
        selectedIndex: _index,
        onSelected: (value) => setState(() => _index = value),
      ),
    );
  }
}

class _LantawNavigation extends StatelessWidget {
  const _LantawNavigation({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _items = <({String label, IconData icon, IconData activeIcon})>[
    (label: 'Home', icon: Icons.home_outlined, activeIcon: Icons.home_rounded),
    (
      label: 'Movies',
      icon: Icons.movie_outlined,
      activeIcon: Icons.movie_rounded,
    ),
    (
      label: 'Series',
      icon: Icons.live_tv_outlined,
      activeIcon: Icons.live_tv_rounded,
    ),
    (
      label: 'Browse',
      icon: Icons.grid_view_outlined,
      activeIcon: Icons.grid_view_rounded,
    ),
    (
      label: 'Search',
      icon: Icons.search_outlined,
      activeIcon: Icons.search_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.midnight,
    shadowColor: Colors.black,
    elevation: 14,
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: 66,
        child: Row(
          children: List.generate(_items.length, (index) {
            final item = _items[index];
            final selected = selectedIndex == index;
            return Expanded(
              child: Semantics(
                selected: selected,
                button: true,
                label: item.label,
                child: InkResponse(
                  containedInkWell: true,
                  highlightColor: Colors.transparent,
                  splashColor: Colors.transparent,
                  onTap: () {
                    if (selected) return;
                    HapticFeedback.selectionClick();
                    onSelected(index);
                  },
                  child: SizedBox.expand(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 160),
                          switchInCurve: Curves.easeOutBack,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(
                                  scale: Tween<double>(
                                    begin: .86,
                                    end: 1,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: Icon(
                            selected ? item.activeIcon : item.icon,
                            key: ValueKey(selected),
                            color: selected
                                ? AppColors.ink
                                : AppColors.muted.withValues(alpha: .62),
                            size: selected ? 25 : 23,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.label,
                          style: AppTheme.utility(
                            size: 9.5,
                            color: selected
                                ? AppColors.ink
                                : AppColors.muted.withValues(alpha: .62),
                            weight: selected
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    ),
  );
}
