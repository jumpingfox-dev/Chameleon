import 'package:material_ui/material_ui.dart';

import '../widgets/detail_page.dart';

/// A single movie's page: backdrop banner, details, Play, genres and cast.
// TODO(cleanup): movie, series, person and collection are a dozen lines each; one file would do
class MovieScreen extends StatelessWidget {
  const MovieScreen({super.key, required this.movieId});

  final String movieId;

  @override
  Widget build(BuildContext context) =>
      DetailPage(load: movieDetails(movieId), layout: const MovieLayout());
}
