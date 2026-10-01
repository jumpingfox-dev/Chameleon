import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:material_ui/material_ui.dart';

import '../widgets/detail_page.dart';

class PersonScreen extends StatelessWidget {
  const PersonScreen({super.key, required this.personId});

  final String personId;

  @override
  Widget build(BuildContext context) =>
      DetailPage(load: personDetails(personId), layout: const PersonLayout());
}
