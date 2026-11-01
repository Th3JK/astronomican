import 'dart:async';

import 'package:astronomican_maplibre/astronomican_maplibre.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../demo_data.dart';
import '../support/demo_pack_server.dart';
import '../support/demo_scope.dart';

/// Both kinds of download.
///
/// **A newer pack.** A little server on the phone offers version 2 of the
/// Strakonice pack: a new style, and every other file unchanged. Downloading
/// it fetches the style and reuses the rest from the installed version;
/// cancel it halfway and download again to see it resume. Demo 2 then draws
/// version 2, and keeps drawing it even though the app still bundles version
/// 1.
///
/// **An offline area.** MapLibre downloads the OpenFreeMap style's tiles for
/// the town into its own database; demo 1 then draws the town with the
/// network off.
class DownloadsPage extends StatefulWidget {
  /// The page.
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  static const String _style = 'https://tiles.openfreemap.org/styles/liberty';

  late MapPackManager _packs;
  DemoPackServer? _server;
  InstalledPack? _installed;
  PackDownload? _download;
  PackProgress? _progress;
  String? _message;
  bool _slow = true;

  final OfflineRegions _regions = OfflineRegions();
  List<OfflineArea> _areas = const [];
  OfflineDownload? _area;
  OfflineProgress? _areaProgress;
  bool _offline = false;

  bool get _regionsSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_server != null) return;
    _packs = DemoScope.packsOf(context);
    unawaited(_start());
  }

  Future<void> _start() async {
    final server = await DemoPackServer.start();
    if (!mounted) {
      await server.close();
      return;
    }
    _server = server..bytesPerSecond = _slow ? 48 * 1024 : 4 * 1024 * 1024;
    await _refresh();
  }

  Future<void> _refresh() async {
    final installed = await _packs.installed('strakonice');
    final areas = _regionsSupported
        ? await _regions.list()
        : const <OfflineArea>[];
    if (!mounted) return;
    setState(() {
      _installed = installed;
      _areas = areas;
    });
  }

  @override
  void dispose() {
    _download?.cancel();
    unawaited(_server?.close());
    super.dispose();
  }

  // Packs.

  Future<void> _check() async {
    final server = _server;
    if (server == null) return;
    try {
      final newer = await _packs.checkForUpdate(server.strakoniceManifest);
      setState(
        () => _message = newer == null
            ? 'Up to date.'
            : 'Version ${newer.version} is available '
                  '(${(newer.totalBytes / 1024).round()} kB in all).',
      );
    } catch (e) {
      setState(() => _message = '$e');
    }
  }

  void _downloadPack() {
    final server = _server;
    if (server == null) return;
    final task = _packs.download(server.strakoniceManifest);
    setState(() {
      _download = task;
      _progress = null;
      _message = null;
    });
    task.progress.listen((p) {
      if (mounted) setState(() => _progress = p);
    });
    task.result.then(
      (pack) {
        if (!mounted) return;
        setState(() {
          _download = null;
          _message = _progress?.phase == PackPhase.upToDate
              ? 'Already up to date.'
              : 'Installed version ${pack.version}.';
        });
        unawaited(_refresh());
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _download = null;
          _message = e is PackCancelledException
              ? 'Cancelled. Download again to resume where it stopped.'
              : '$e';
        });
      },
    );
  }

  Future<void> _reset() async {
    await _packs.remove('strakonice');
    await _packs.ensureBundled(strakonicePack);
    setState(() => _message = 'Back to the bundled version.');
    await _refresh();
  }

  // Offline areas.

  void _downloadArea() {
    final task = _regions.download(
      const OfflineAreaRequest(
        styleUrl: _style,
        bounds: strakoniceBounds,
        minZoom: 12,
        maxZoom: 15,
        name: 'Strakonice',
      ),
    );
    setState(() {
      _area = task;
      _areaProgress = null;
    });
    task.progress.listen((p) {
      if (mounted) setState(() => _areaProgress = p);
    });
    task.result.then(
      (_) {
        if (!mounted) return;
        setState(() => _area = null);
        unawaited(_refresh());
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _area = null;
          _message = '$e';
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final installed = _installed;
    final download = _download;
    final estimate = OfflineRegions.estimateTileCount(strakoniceBounds, 12, 15);
    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Map pack', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text(
              installed == null
                  ? 'Not installed'
                  : '${installed.manifest.name ?? installed.id} · v${installed.version}',
            ),
            subtitle: Text(
              installed == null
                  ? 'Open demo 2, or reset below.'
                  : '${installed.origin.name}, in ${installed.directory.path}',
            ),
          ),
          if (download != null) ...[
            LinearProgressIndicator(value: _progress?.fraction),
            const SizedBox(height: 4),
            Text(
              '${_progress?.phase.name ?? 'starting'} '
              '${_progress?.file ?? ''} '
              '${((_progress?.bytesDone ?? 0) / 1024).round()} / '
              '${((_progress?.bytesTotal ?? 0) / 1024).round()} kB',
            ),
          ],
          if (_message case final message?)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(message),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Slow server'),
            subtitle: const Text('So there is time to cancel.'),
            value: _slow,
            onChanged: (v) => setState(() {
              _slow = v;
              _server?.bytesPerSecond = v ? 48 * 1024 : 4 * 1024 * 1024;
            }),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _server == null ? null : _check,
                child: const Text('Check'),
              ),
              FilledButton(
                onPressed: _server == null || download != null
                    ? null
                    : _downloadPack,
                child: const Text('Download'),
              ),
              OutlinedButton(
                onPressed: download?.cancel,
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: download != null ? null : _reset,
                child: const Text('Reset to bundled'),
              ),
            ],
          ),
          const Divider(height: 40),
          Text('Offline area', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (!_regionsSupported)
            const Text('MapLibre\'s offline database is on Android and iOS.')
          else ...[
            Text(
              'OpenFreeMap around Strakonice, zoom 12 to 15: about $estimate '
              'tiles per source.',
            ),
            const SizedBox(height: 8),
            if (_area != null) ...[
              LinearProgressIndicator(value: _areaProgress?.fraction),
              const SizedBox(height: 4),
              Text(
                '${_areaProgress?.completedResources ?? 0} of '
                '${_areaProgress?.requiredResources ?? '?'} resources',
              ),
            ],
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: _area == null ? _downloadArea : null,
                  child: const Text('Download area'),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Work offline'),
              subtitle: const Text('Maps draw only what is stored.'),
              value: _offline,
              onChanged: (v) async {
                await _regions.setOffline(offline: v);
                setState(() => _offline = v);
              },
            ),
            for (final area in _areas)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.map_outlined),
                title: Text(area.name ?? area.styleUrl),
                subtitle: Text(
                  'zoom ${area.minZoom.round()}–${area.maxZoom.round()}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await _regions.delete(area, clearAmbientCache: true);
                    await _refresh();
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }
}
