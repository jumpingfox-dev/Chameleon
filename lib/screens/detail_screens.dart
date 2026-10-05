import 'package:material_ui/material_ui.dart';

import '../widgets/detail_page.dart';

/// A single movie's page: backdrop banner, details, Play, genres and cast.
class MovieScreen extends StatelessWidget {
  const MovieScreen({super.key, required this.movieId});

  final String movieId;

  @override
  Widget build(BuildContext context) =>
      DetailPage(load: movieDetails(movieId), layout: const MovieLayout());
}

/// A series' page: backdrop banner, details, season picker and episodes.
class SeriesScreen extends StatelessWidget {
  const SeriesScreen({super.key, required this.seriesId});

  final String seriesId;

  @override
  Widget build(BuildContext context) =>
      DetailPage(load: seriesDetails(seriesId), layout: const SeriesLayout());
}

class PersonScreen extends StatelessWidget {
  const PersonScreen({super.key, required this.personId});

  final String personId;

  @override
  Widget build(BuildContext context) =>
      DetailPage(load: personDetails(personId), layout: const PersonLayout());
}

class CollectionScreen extends StatelessWidget {
  const CollectionScreen({super.key, required this.collectionId});

  final String collectionId;

  @override
  Widget build(BuildContext context) => DetailPage(
    load: collectionDetails(collectionId),
    layout: const CollectionLayout(),
  );
}
