import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/media.dart';
import '../viewmodels/catalog_view_model.dart';
import '../viewmodels/view_state.dart';
import '../widgets/media_widgets.dart';
import '../widgets/state_widgets.dart';
import 'navigation.dart';

class BrowseView extends StatelessWidget {
  const BrowseView({super.key});

  static const genres = <int, String>{
    28: 'Action',
    35: 'Comedy',
    18: 'Drama',
    10749: 'Romance',
    27: 'Horror',
    16: 'Animation',
  };
  static const languages = <String, String>{
    'en': 'English',
    'ko': 'Korean',
    'ja': 'Japanese',
    'tl': 'Filipino',
    'es': 'Spanish',
  };

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<CatalogViewModel>();
    return Scaffold(
      appBar: AppBar(title: const Text('Browse')),
      body: Column(
        children: [
          _Filters(viewModel: viewModel),
          const Divider(),
          Expanded(
            child: switch (viewModel.status) {
              ViewStatus.loading || ViewStatus.idle => const PageLoader(),
              ViewStatus.error => ErrorState(
                message: viewModel.errorMessage ?? 'Unknown error',
                onRetry: viewModel.load,
              ),
              ViewStatus.empty => const EmptyState(),
              _ => MediaGrid(
                items: viewModel.items,
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                onTap: (media) => openMediaDetails(context, media),
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.viewModel});
  final CatalogViewModel viewModel;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.surface.withValues(alpha: .55),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageIntro(
            eyebrow: '${viewModel.totalResults} matches',
            title: 'Find something to watch',
            detail: 'Filter by format, genre, and language.',
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: viewModel.type == MediaType.movie
                    ? FilledButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.movie_outlined),
                        label: const Text('MOVIES'),
                      )
                    : OutlinedButton.icon(
                        onPressed: () =>
                            viewModel.updateFilters(type: MediaType.movie),
                        icon: const Icon(Icons.movie_outlined),
                        label: const Text('MOVIES'),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: viewModel.type == MediaType.tv
                    ? FilledButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.live_tv_outlined),
                        label: const Text('SERIES'),
                      )
                    : OutlinedButton.icon(
                        onPressed: () =>
                            viewModel.updateFilters(type: MediaType.tv),
                        icon: const Icon(Icons.live_tv_outlined),
                        label: const Text('SERIES'),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final genre = _genrePicker();
              final language = _languagePicker();
              if (constraints.maxWidth < 390) {
                return Column(
                  children: [genre, const SizedBox(height: 10), language],
                );
              }
              return Row(
                children: [
                  Expanded(child: genre),
                  const SizedBox(width: 10),
                  Expanded(child: language),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );

  Widget _genrePicker() => DropdownButtonFormField<int?>(
    key: ValueKey('genre-${viewModel.genre}'),
    initialValue: viewModel.genre,
    isExpanded: true,
    decoration: const InputDecoration(
      labelText: 'Genre',
      prefixIcon: Icon(Icons.category_outlined),
    ),
    items: [
      const DropdownMenuItem(value: null, child: Text('All genres')),
      ...BrowseView.genres.entries.map(
        (entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ),
    ],
    onChanged: (value) =>
        viewModel.updateFilters(genre: value, clearGenre: value == null),
  );

  Widget _languagePicker() => DropdownButtonFormField<String?>(
    key: ValueKey('language-${viewModel.language}'),
    initialValue: viewModel.language,
    isExpanded: true,
    decoration: const InputDecoration(
      labelText: 'Language',
      prefixIcon: Icon(Icons.language_rounded),
    ),
    items: [
      const DropdownMenuItem(value: null, child: Text('Any language')),
      ...BrowseView.languages.entries.map(
        (entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ),
    ],
    onChanged: (value) =>
        viewModel.updateFilters(language: value, clearLanguage: value == null),
  );
}
