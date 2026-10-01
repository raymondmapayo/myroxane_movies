import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/media.dart';
import '../../domain/usecases/media_usecases.dart';
import '../viewmodels/details_view_model.dart';
import 'details_view.dart';

void openMediaDetails(BuildContext context, Media media) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ChangeNotifierProvider(
        create: (context) => DetailsViewModel(
          context.read<GetMediaDetails>(),
          type: media.type,
          id: media.id,
        )..load(),
        child: const DetailsView(),
      ),
    ),
  );
}
