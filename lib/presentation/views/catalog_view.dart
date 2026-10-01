import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/media.dart';
import '../viewmodels/catalog_view_model.dart';
import '../viewmodels/view_state.dart';
import '../widgets/media_widgets.dart';
import '../widgets/state_widgets.dart';
import 'navigation.dart';

class CatalogView extends StatefulWidget {
  const CatalogView({super.key, required this.title, required this.type});
  final String title;
  final MediaType type;

  @override
  State<CatalogView> createState() => _CatalogViewState();
}

class _CatalogViewState extends State<CatalogView> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  void _onScroll() {
    if (_controller.position.extentAfter < 500) {
      context.read<CatalogViewModel>().loadMore();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<CatalogViewModel>();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Center(
              child: Text(
                '${viewModel.totalResults} TITLES',
                style: AppTheme.utility(size: 8.5, color: AppColors.focus),
              ),
            ),
          ),
        ],
      ),
      body: switch (viewModel.status) {
        ViewStatus.loading || ViewStatus.idle => const PageLoader(),
        ViewStatus.error => ErrorState(
          message: viewModel.errorMessage ?? 'Unknown error',
          onRetry: viewModel.load,
        ),
        ViewStatus.empty => const EmptyState(),
        _ => RefreshIndicator(
          onRefresh: viewModel.load,
          child: CustomScrollView(
            controller: _controller,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Popular ${widget.title.toLowerCase()}',
                        style: AppTheme.display(26),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        'Page ${viewModel.page} of ${viewModel.totalPages}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.crossAxisExtent >= 900
                        ? 5
                        : constraints.crossAxisExtent >= 620
                        ? 4
                        : 2;
                    return SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 11,
                        mainAxisSpacing: 11,
                        childAspectRatio: .66,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => MediaCard(
                          media: viewModel.items[index],
                          onTap: () =>
                              openMediaDetails(context, viewModel.items[index]),
                        ),
                        childCount: viewModel.items.length,
                      ),
                    );
                  },
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: viewModel.isLoadingMore
                        ? const CircularProgressIndicator()
                        : viewModel.page >= viewModel.totalPages
                        ? const Text(
                            'You’ve reached the end',
                            style: TextStyle(color: AppColors.muted),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
            ],
          ),
        ),
      },
    );
  }
}
