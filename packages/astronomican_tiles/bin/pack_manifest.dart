// The tool astronomican_tiles replaces, kept so old scripts keep working:
//   dart run astronomican_tiles:pack_manifest <folder> --id <id> --version <n> …
// is `astronomican_tiles manifest` with the same flags.

import 'dart:io';

import 'package:astronomican_tiles/astronomican_tiles.dart';

Future<void> main(List<String> args) async {
  exit(await TilesRunner(TilesContext()).execute(['manifest', ...args]));
}
