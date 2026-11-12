import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'model.dart';
import 'services.dart';

Json decodeCatalog(String text) {
  if (utf8.encode(text).length > 65536)
    throw const FormatException('Content exceeds the supported size.');
  final value = jsonDecode(text);
  if (value is! Map<String, dynamic> ||
      value['format'] != 'OneStepContent' ||
      value['schema'] != 1 ||
      value['revision'] is! int ||
      value['revision'] < 1 ||
      value['message'] is! String ||
      (value['message'] as String).length > 500 ||
      value['packs'] is! List ||
      (value['packs'] as List).length > 50 ||
      value['minAppVersion'] is! String)
    throw const FormatException('Unsupported content.');
  final version = (value['minAppVersion'] as String)
      .split('.')
      .map(int.tryParse)
      .toList();
  if (version.length != 3 ||
      version.any((v) => v == null || v < 0) ||
      version[0]! > 0 ||
      (version[0] == 0 && version[1]! > 5) ||
      (version[1] == 5 && version[2]! > 0))
    throw const FormatException('This content needs a newer app.');
  final ids = <String>{};
  for (final raw in value['packs'] as List) {
    if (raw is! Map<String, dynamic>)
      throw const FormatException('Invalid content pack.');
    final id = raw['id'],
        title = raw['title'],
        description = raw['description'],
        steps = raw['steps'];
    if (id is! String ||
        !RegExp(r'^[a-zA-Z0-9-]{1,60}$').hasMatch(id) ||
        !ids.add(id) ||
        title is! String ||
        title.isEmpty ||
        title.length > 100 ||
        description is! String ||
        description.length > 500 ||
        steps is! List ||
        steps.isEmpty ||
        steps.length > 30)
      throw const FormatException('Invalid content pack.');
    for (final s in steps) {
      if (s is! Map ||
          s['title'] is! String ||
          (s['title'] as String).isEmpty ||
          (s['title'] as String).length > 200 ||
          s['hour'] is! int ||
          s['hour'] < 0 ||
          s['hour'] > 23 ||
          s['minute'] is! int ||
          s['minute'] < 0 ||
          s['minute'] > 59 ||
          ![
            'blue',
            'violet',
            'mint',
            'coral',
            'rose',
            'amber',
          ].contains(s['colorName']))
        throw const FormatException('Invalid routine content.');
    }
  }
  return value;
}

Json installPack(Json original, Json catalog, Json pack) {
  decodeCatalog(jsonEncode(catalog));
  final state = clone(original),
      installed = List<String>.from(state['contentPacks'] as List? ?? []);
  if (!rows(catalog, 'packs').any((p) => jsonEncode(p) == jsonEncode(pack)) ||
      installed.contains(pack['id']))
    return state;
  final routines = rows(state, 'routines');
  if (routines.length + rows(pack, 'steps').length > 1000)
    throw const FormatException('Too many routine steps.');
  var position =
      routines.fold<int>(
        -1,
        (n, s) => n > (s['position'] as int) ? n : s['position'] as int,
      ) +
      1;
  for (final step in rows(pack, 'steps')) {
    routines.add({
      ...step,
      'id': uuid.v4().toUpperCase(),
      'position': position++,
    });
  }
  state['routines'] = routines;
  state['contentPacks'] = [...installed, pack['id']];
  return state;
}

class ContentCache {
  final Directory directory;
  ContentCache(this.directory);
  static final feed = Uri.parse(
    'https://raw.githubusercontent.com/sillytira/onestep-ios/main/content/catalog.json',
  );
  File get file => File('${directory.path}/OneStep-content.json');
  Future<Json?> read() async {
    try {
      return decodeCatalog(await file.readAsString());
    } catch (_) {
      return null;
    }
  }

  Future<void> refreshQuietly() async {
    try {
      await refresh();
    } catch (_) {}
  }

  Future<Json> refresh() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(feed);
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != 200)
        throw const FormatException('Content service unavailable.');
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        bytes.addAll(chunk);
        if (bytes.length > 65536)
          throw const FormatException('Content too large.');
      }
      final text = utf8.decode(bytes),
          catalog = decodeCatalog(text),
          saved = await read();
      if (catalog['revision'] < (saved?['revision'] ?? 0))
        throw const FormatException('Ignoring older content.');
      final temp = File('${file.path}.pending');
      await temp.writeAsString(text, flush: true);
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
      return catalog;
    } finally {
      client.close(force: true);
    }
  }
}

class ContentPage extends StatefulWidget {
  final Planner planner;
  const ContentPage({super.key, required this.planner});
  @override
  State<ContentPage> createState() => _ContentPageState();
}

class _ContentPageState extends State<ContentPage> {
  Json? catalog;
  bool busy = false;
  String message = '';
  ContentCache get cache => ContentCache(widget.planner.directory);
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final saved = await cache.read();
    if (!mounted) return;
    setState(() => catalog = saved);
    if (widget.planner.state['contentAutoUpdate'] != false) await refresh();
  }

  Future<void> refresh() async {
    setState(() => busy = true);
    try {
      final value = await cache.refresh();
      if (mounted)
        setState(() {
          catalog = value;
          message =
              'Content revision ${value['revision']} is ready. No app reinstall needed.';
        });
    } catch (_) {
      if (mounted)
        setState(
          () => message =
              'Offline or unavailable. Keeping saved content; your planner still works.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Content updates')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Routine packs and colors can update without a new APK, IPA, EXE, or AppImage. New native features still need an app update. Your private tasks and edited routines are never replaced automatically.',
        ),
        SwitchListTile(
          title: const Text('Automatically refresh content'),
          subtitle: const Text(
            'Checks the public content feed on app launch and when this screen opens. Sends no personal planner data.',
          ),
          value: widget.planner.state['contentAutoUpdate'] != false,
          onChanged: (value) async {
            await widget.planner.save(
              clone(widget.planner.state)..['contentAutoUpdate'] = value,
            );
            if (mounted) setState(() {});
          },
        ),
        FilledButton(
          onPressed: busy ? null : refresh,
          child: Text(busy ? 'Checking…' : 'Check content now'),
        ),
        if (message.isNotEmpty)
          Padding(padding: const EdgeInsets.all(12), child: Text(message)),
        if (catalog != null) ...[
          Text('Revision ${catalog!['revision']} · ${catalog!['message']}'),
          for (final pack in rows(catalog!, 'packs'))
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pack['title'] as String,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(pack['description'] as String),
                    for (final step in rows(pack, 'steps'))
                      Text(
                        '${(step['hour'] as int).toString().padLeft(2, '0')}:${(step['minute'] as int).toString().padLeft(2, '0')} · ${step['title']}',
                      ),
                    TextButton(
                      onPressed:
                          (widget.planner.state['contentPacks'] as List? ?? [])
                              .contains(pack['id'])
                          ? null
                          : () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('Add these routine steps?'),
                                  content: const Text(
                                    'Adds new steps. Existing routines and history stay in place. Edit the new times in Routines.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(c, false),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(c, true),
                                      child: const Text('Add steps'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed != true) return;
                              try {
                                await widget.planner.save(
                                  installPack(
                                    widget.planner.state,
                                    catalog!,
                                    pack,
                                  ),
                                );
                                if (mounted) setState(() {});
                              } catch (e) {
                                if (mounted) setState(() => message = '$e');
                              }
                            },
                      child: Text(
                        (widget.planner.state['contentPacks'] as List? ?? [])
                                .contains(pack['id'])
                            ? 'Already added'
                            : 'Add these routine steps',
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 20),
        const Text(
          'Privacy: account sessions use the OS secure vault. Planner files and JSON exports contain readable personal data; protect your device and backups. Public content updates do not upload your planner.',
        ),
      ],
    ),
  );
}
