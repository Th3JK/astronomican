import 'dart:io';

import 'package:astronomican_tiles/astronomican_tiles.dart';

Future<void> main(List<String> args) async {
  final code = await TilesRunner(TilesContext()).execute(args);
  // Close the HTTP client's idle connections so the process ends.
  exit(code);
}
