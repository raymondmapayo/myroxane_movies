import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:roxane_movies/core/theme/app_theme.dart';
import 'package:roxane_movies/domain/entities/media.dart';
import 'package:roxane_movies/domain/entities/media_details.dart';
import 'package:roxane_movies/domain/repositories/media_repository.dart';
import 'package:roxane_movies/domain/usecases/media_usecases.dart';
import 'package:roxane_movies/presentation/viewmodels/details_view_model.dart';
import 'package:roxane_movies/presentation/views/details_view.dart';

/// Long enough to wrap next to the poster on every phone — the case that used
/// to lose its first line behind the header.
const _longTitle = 'Spider-Man: No Way Home';

const _film = MediaDetails(
  media: Media(
    id: 634649,
    title: _longTitle,
    type: MediaType.movie,
    overview:
        'Peter Parker is unmasked and no longer able to separate his '
        'normal life from the high-stakes of being a super-hero.',
    rating: 7.9,
    date: '2021-12-15',
  ),
  voteCount: 1900,
  genres: ['Action', 'Adventure', 'Science Fiction'],
  countries: ['US'],
  cast: [
    CastMember(id: 1, name: 'Tom Holland', character: 'Peter Parker'),
    CastMember(id: 2, name: 'Zendaya', character: 'MJ'),
  ],
  seasonList: [],
  recommendations: [],
  runtime: 148,
  trailerKey: 'JfVOs4VSpmA',
);

/// A series carries the widest chip the deck ever shows: its season and
/// episode counts sit in the same narrow column as the title.
const _series = MediaDetails(
  media: Media(
    id: 1396,
    title: _longTitle,
    type: MediaType.tv,
    overview: 'A long-running series with a great many episodes.',
    rating: 8.9,
    date: '2008-01-20',
  ),
  voteCount: 12000,
  genres: ['Drama', 'Crime', 'Science Fiction'],
  countries: ['US'],
  cast: [CastMember(id: 1, name: 'Bryan Cranston', character: 'Walter White')],
  seasonList: [],
  recommendations: [],
  seasons: 13,
  episodes: 300,
  lastAirDate: '2021-09-30',
  trailerKey: 'HhesaQXLuRY',
);

class _StubRepository implements MediaRepository {
  const _StubRepository(this._details);
  final MediaDetails _details;

  static const _emptyPage = MediaPage(
    items: [],
    page: 1,
    totalPages: 1,
    totalResults: 0,
  );

  @override
  Future<MediaPage> discover(
    MediaType type, {
    int page = 1,
    String sortBy = 'popularity.desc',
    int? genre,
    String? language,
    int? minimumVotes,
  }) async => _emptyPage;

  @override
  Future<MediaPage> search(String query, {int page = 1}) async => _emptyPage;

  @override
  Future<MediaDetails> details(MediaType type, int id) async => _details;
}

Future<void> _pumpDetails(
  WidgetTester tester,
  Size size,
  MediaDetails details,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final viewModel = DetailsViewModel(
    GetMediaDetails(_StubRepository(details)),
    type: details.media.type,
    id: details.media.id,
  );
  await viewModel.load();

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: ChangeNotifierProvider.value(
        value: viewModel,
        child: const DetailsView(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  const sizes = <Size>[
    Size(320, 640), // the smallest phone still in circulation
    Size(390, 844), // iPhone 15
    Size(430, 932), // iPhone 15 Pro Max, the device in the report
    Size(834, 1112), // tablet
  ];

  for (final size in sizes) {
    for (final details in [_film, _series]) {
      final kind = details.media.type == MediaType.movie ? 'film' : 'series';
      testWidgets('$kind details fit ${size.width.toInt()} px wide', (
        tester,
      ) async {
        await _pumpDetails(tester, size, details);

        // Overflowing rows and failed layouts surface here.
        expect(tester.takeException(), isNull);

        // The deck's title has to start below the header: the scroll view
        // clips anything painted above its first sliver, which is how the
        // first line of a wrapping title went missing.
        final deckTitle = tester.renderObject<RenderBox>(
          find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.data == _longTitle &&
                widget.maxLines == 4,
          ),
        );
        final header = tester.renderObject<RenderBox>(
          find.byType(FlexibleSpaceBar),
        );
        final headerBottom =
            header.localToGlobal(Offset.zero).dy + header.size.height;
        final titleTop = deckTitle.localToGlobal(Offset.zero).dy;

        expect(titleTop, greaterThanOrEqualTo(headerBottom));
        expect(
          titleTop + deckTitle.size.height,
          lessThanOrEqualTo(size.height),
        );

        // Both actions stay reachable at every width.
        expect(find.text('WATCH NOW'), findsOneWidget);
        expect(find.text('TRAILER'), findsOneWidget);
      });
    }
  }
}
