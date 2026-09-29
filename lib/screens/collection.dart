import 'package:material_ui/material_ui.dart';

import '../widgets/detail_page.dart';

class CollectionScreen extends StatelessWidget {
  const CollectionScreen({super.key, required this.collectionId});

  final String collectionId;

  @override
  Widget build(BuildContext context) => DetailPage(load: collectionDetails(collectionId), layout: const CollectionLayout());
}