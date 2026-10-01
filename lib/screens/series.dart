import 'package:material_ui/material_ui.dart';

import '../widgets/detail_page.dart';

/// A series' page: backdrop banner, details, season picker and episodes.
class SeriesScreen extends StatelessWidget {
  const SeriesScreen({super.key, required this.seriesId});

  final String seriesId;

  @override
  Widget build(BuildContext context) =>
      DetailPage(load: seriesDetails(seriesId), layout: const SeriesLayout());
}
