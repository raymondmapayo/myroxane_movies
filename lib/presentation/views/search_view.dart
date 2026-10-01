import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../viewmodels/search_view_model.dart';
import '../viewmodels/view_state.dart';
import '../widgets/media_widgets.dart';
import '../widgets/state_widgets.dart';
import 'navigation.dart';

class SearchView extends StatefulWidget {
  const SearchView({super.key});

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: context.read<SearchViewModel>().query,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<SearchViewModel>();
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
            child: TextField(
              controller: _controller,
              autofocus: viewModel.query.isEmpty,
              textInputAction: TextInputAction.search,
              onChanged: viewModel.updateQuery,
              onSubmitted: viewModel.search,
              decoration: InputDecoration(
                hintText: 'Search movies, series, and people',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _controller.clear();
                          viewModel.updateQuery('');
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          const Divider(),
          Expanded(child: _results(viewModel)),
        ],
      ),
    );
  }

  Widget _results(SearchViewModel viewModel) => switch (viewModel.status) {
    ViewStatus.idle => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const ShapeDecoration(
                color: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(36)),
                  side: BorderSide(color: AppColors.border),
                ),
              ),
              child: const Icon(
                Icons.search_rounded,
                size: 32,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 18),
            Text('Find your next watch', style: AppTheme.display(25)),
            const SizedBox(height: 9),
            const Text(
              'Search by title, actor, or franchise.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, height: 1.5),
            ),
          ],
        ),
      ),
    ),
    ViewStatus.loading => const PageLoader(),
    ViewStatus.empty => const EmptyState(search: true),
    ViewStatus.error => ErrorState(
      message: viewModel.errorMessage ?? 'Unknown error',
      onRetry: () => viewModel.search(viewModel.query),
    ),
    _ => MediaGrid(
      items: viewModel.results,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      onTap: (media) => openMediaDetails(context, media),
    ),
  };
}
