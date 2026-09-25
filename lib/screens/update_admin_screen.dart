import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UpdateAdminScreen extends StatefulWidget {
  const UpdateAdminScreen({super.key});

  @override
  State<UpdateAdminScreen> createState() =>
      _UpdateAdminScreenState();
}

class _UpdateAdminScreenState extends State<UpdateAdminScreen>
    with SingleTickerProviderStateMixin {
  static const _navy = Color(0xFF0A1F44);
  static const _blue = Color(0xFF0B4EA2);
  static const _red = Color(0xFFE30613);
  static const _green = Color(0xFF13A05B);
  static const _orange = Color(0xFFFF7A00);

  final _supabase = Supabase.instance.client;

  late final TabController _tabController;

  bool _loading = true;
  bool _isDeveloper = false;
  String? _error;

  List<Map<String, dynamic>> _releases = [];
  List<Map<String, dynamic>> _profiles = [];
  Map<String, bool> _beta = {};

  String _userSearch = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
    );
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<bool> _checkDeveloper() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    final row = await _supabase
        .from('developer_access')
        .select('user_id')
        .eq('user_id', user.id)
        .maybeSingle();

    return row != null;
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final developer = await _checkDeveloper();

      if (!developer) {
        if (!mounted) return;
        setState(() {
          _isDeveloper = false;
          _loading = false;
        });
        return;
      }

      final result = await Future.wait([
        _supabase
            .from('app_releases')
            .select()
            .order('build_number', ascending: false),
        _supabase
            .from('profiles')
            .select(
              'id,first_name,last_name,role,approval_status',
            )
            .eq('approval_status', 'approved')
            .order('last_name')
            .order('first_name'),
        _supabase
            .from('app_beta_users')
            .select('user_id,enabled'),
      ]);

      final releases =
          List<Map<String, dynamic>>.from(result[0]);
      final profiles =
          List<Map<String, dynamic>>.from(result[1]);
      final betaRows =
          List<Map<String, dynamic>>.from(result[2]);

      final beta = <String, bool>{};
      for (final row in betaRows) {
        final id = row['user_id']?.toString();
        if (id != null) {
          beta[id] = row['enabled'] == true;
        }
      }

      if (!mounted) return;

      setState(() {
        _isDeveloper = true;
        _releases = releases;
        _profiles = profiles;
        _beta = beta;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _name(Map<String, dynamic> profile) {
    final first =
        profile['first_name']?.toString().trim() ?? '';
    final last =
        profile['last_name']?.toString().trim() ?? '';
    final value = '$first $last'.trim();

    return value.isEmpty ? 'Unbenannter Benutzer' : value;
  }

  String _roleLabel(String? role) {
    switch (role) {
      case 'ausbilder':
        return 'Ausbilder';
      case 'jugendmitglied':
        return 'Jugendmitglied';
      case 'eltern':
        return 'Eltern';
      default:
        return role ?? 'Mitglied';
    }
  }

  String _channelLabel(String? value) {
    switch (value) {
      case 'beta':
        return 'BETA';
      case 'forall':
        return 'FOR ALL';
      default:
        return 'NON';
    }
  }

  Color _channelColor(String? value) {
    switch (value) {
      case 'beta':
        return _orange;
      case 'forall':
        return _green;
      default:
        return const Color(0xFF667085);
    }
  }

  Future<void> _setBeta(
    String userId,
    bool enabled,
  ) async {
    final developer = _supabase.auth.currentUser;
    if (developer == null) return;

    final old = _beta[userId] ?? false;

    setState(() {
      _beta[userId] = enabled;
    });

    try {
      await _supabase.from('app_beta_users').upsert(
        {
          'user_id': userId,
          'enabled': enabled,
          'granted_by': developer.id,
          'granted_at':
              DateTime.now().toUtc().toIso8601String(),
          'updated_at':
              DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id',
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _beta[userId] = old;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Beta-Status konnte nicht geändert werden: $e',
          ),
        ),
      );
    }
  }

  Future<void> _setReleaseChannel(
    Map<String, dynamic> release,
    String channel,
  ) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      await _supabase
          .from('app_releases')
          .update({
            'channel': channel,
            'updated_by': user.id,
            'updated_at':
                DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', release['id']);

      await _load();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Update-Kanal konnte nicht geändert werden: $e',
          ),
        ),
      );
    }
  }

  Future<void> _setForceUpdate(
    Map<String, dynamic> release,
    bool value,
  ) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      await _supabase
          .from('app_releases')
          .update({
            'force_update': value,
            'updated_by': user.id,
            'updated_at':
                DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', release['id']);

      await _load();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pflichtupdate konnte nicht geändert werden: $e',
          ),
        ),
      );
    }
  }

  Future<void> _setActive(
    Map<String, dynamic> release,
    bool value,
  ) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      await _supabase
          .from('app_releases')
          .update({
            'is_active': value,
            'updated_by': user.id,
            'updated_at':
                DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', release['id']);

      await _load();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Aktivstatus konnte nicht geändert werden: $e',
          ),
        ),
      );
    }
  }

  Future<void> _deleteRelease(
    Map<String, dynamic> release,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Version löschen?'),
        content: Text(
          'Version ${release['version_name']} '
          '(Build ${release['build_number']}) '
          'und die zugehörige APK werden gelöscht.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _red,
            ),
            onPressed: () =>
                Navigator.pop(dialogContext, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final path = release['storage_path']?.toString();

      if (path != null && path.isNotEmpty) {
        await _supabase.storage
            .from('app-updates')
            .remove([path]);
      }

      await _supabase
          .from('app_releases')
          .delete()
          .eq('id', release['id']);

      await _load();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Version konnte nicht gelöscht werden: $e',
          ),
        ),
      );
    }
  }

  Future<void> _showCreateRelease() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const _CreateReleaseScreen(),
      ),
    );

    if (created == true) {
      await _load();
    }
  }

  List<Map<String, dynamic>> get _filteredProfiles {
    final q = _userSearch.trim().toLowerCase();

    if (q.isEmpty) return _profiles;

    return _profiles.where((profile) {
      final text = [
        _name(profile),
        profile['role'],
      ].join(' ').toLowerCase();

      return text.contains(q);
    }).toList();
  }

  Widget _releasesTab() {
    if (_releases.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _InfoCard(
            icon: Icons.system_update_alt,
            title: 'Noch keine Update-Version',
            text:
                'Lege zuerst eine APK an. Neue Versionen starten '
                'am besten als NON, werden danach auf BETA und '
                'anschließend auf FOR ALL gesetzt.',
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
        itemCount: _releases.length,
        itemBuilder: (_, index) {
          final release = _releases[index];
          final channel =
              release['channel']?.toString() ?? 'non';
          final active = release['is_active'] == true;
          final force = release['force_update'] == true;

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Version '
                              '${release['version_name']}',
                              style: const TextStyle(
                                color: _navy,
                                fontSize: 18,
                                fontWeight:
                                    FontWeight.w900,
                              ),
                            ),
                            Text(
                              'Build ${release['build_number']}',
                              style: const TextStyle(
                                color: Color(0xFF667085),
                                fontWeight:
                                    FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _channelColor(channel)
                              .withValues(alpha: 0.10),
                          borderRadius:
                              BorderRadius.circular(99),
                        ),
                        child: Text(
                          _channelLabel(channel),
                          style: TextStyle(
                            color: _channelColor(channel),
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if ((release['notes']
                              ?.toString()
                              .trim()
                              .isNotEmpty ??
                          false)) ...[
                    const SizedBox(height: 10),
                    Text(
                      release['notes'].toString(),
                      style: const TextStyle(
                        color: Color(0xFF475467),
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  const Text(
                    'Freigabe',
                    style: TextStyle(
                      color: _navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      _ChannelButton(
                        label: 'NON',
                        selected: channel == 'non',
                        onTap: () =>
                            _setReleaseChannel(
                          release,
                          'non',
                        ),
                      ),
                      _ChannelButton(
                        label: 'BETA',
                        selected: channel == 'beta',
                        onTap: () =>
                            _setReleaseChannel(
                          release,
                          'beta',
                        ),
                      ),
                      _ChannelButton(
                        label: 'FOR ALL',
                        selected: channel == 'forall',
                        onTap: () =>
                            _setReleaseChannel(
                          release,
                          'forall',
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 26),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: active,
                    title: const Text(
                      'Version aktiv',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: const Text(
                      'Inaktive Versionen werden nie ausgeliefert.',
                    ),
                    onChanged: (value) =>
                        _setActive(release, value),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: force,
                    title: const Text(
                      'Pflichtupdate',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: const Text(
                      'Die alte App bleibt bis zur Installation gesperrt.',
                    ),
                    onChanged: (value) =>
                        _setForceUpdate(
                      release,
                      value,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.verified_user_outlined,
                        size: 18,
                        color: _green,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'SHA-256: '
                          '${release['sha256'] ?? '-'}',
                          maxLines: 1,
                          overflow:
                              TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF667085),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Löschen',
                        onPressed: () =>
                            _deleteRelease(release),
                        icon: const Icon(
                          Icons.delete_outline,
                          color: _red,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _betaUsersTab() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
        children: [
          _InfoCard(
            icon: Icons.science_outlined,
            title: 'Beta-Nutzer',
            text:
                'Nur von dir aktivierte Nutzer sehen BETA-Versionen. '
                'NON bleibt unsichtbar. FOR ALL gilt für alle.',
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (value) {
              setState(() {
                _userSearch = value;
              });
            },
            decoration: InputDecoration(
              hintText: 'Benutzer suchen',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ..._filteredProfiles.map((profile) {
            final id = profile['id']?.toString() ?? '';
            final enabled = _beta[id] ?? false;

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: SwitchListTile.adaptive(
                value: enabled,
                onChanged: id.isEmpty
                    ? null
                    : (value) =>
                        _setBeta(id, value),
                title: Text(
                  _name(profile),
                  style: const TextStyle(
                    color: _navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  _roleLabel(
                    profile['role']?.toString(),
                  ),
                ),
                secondary: CircleAvatar(
                  backgroundColor: enabled
                      ? _orange.withValues(alpha: 0.12)
                      : const Color(0xFFF2F4F7),
                  child: Icon(
                    enabled
                        ? Icons.science
                        : Icons.person_outline,
                    color: enabled
                        ? _orange
                        : const Color(0xFF667085),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF3F5F7),
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!_isDeveloper) {
      return Scaffold(
        backgroundColor: const Color(0xFFF3F5F7),
        appBar: AppBar(
          title: const Text('Update-Server'),
          backgroundColor: _navy,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 58,
                  color: _red,
                ),
                SizedBox(height: 12),
                Text(
                  'Kein Entwicklerzugriff',
                  style: TextStyle(
                    color: _navy,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Update-Server'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(
              icon: Icon(Icons.system_update_alt),
              text: 'Updates',
            ),
            Tab(
              icon: Icon(Icons.science_outlined),
              text: 'Beta-Nutzer',
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Neu laden',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: const Color(0xFFFFE4E8),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: _red,
                ),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _releasesTab(),
                _betaUsersTab(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton:
          _tabController.index == 0
              ? FloatingActionButton.extended(
                  onPressed: _showCreateRelease,
                  backgroundColor: _blue,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.add),
                  label: const Text(
                    'Neue Version',
                  ),
                )
              : null,
    );
  }
}

class _CreateReleaseScreen extends StatefulWidget {
  const _CreateReleaseScreen();

  @override
  State<_CreateReleaseScreen> createState() =>
      _CreateReleaseScreenState();
}

class _CreateReleaseScreenState
    extends State<_CreateReleaseScreen> {
  static const _navy = Color(0xFF0A1F44);
  static const _blue = Color(0xFF0B4EA2);

  final _supabase = Supabase.instance.client;

  final _version = TextEditingController();
  final _build = TextEditingController();
  final _notes = TextEditingController();

  Uint8List? _apkBytes;
  String? _apkName;
  String? _sha;
  int? _fileSize;

  String _channel = 'non';
  bool _forceUpdate = false;
  bool _saving = false;

  @override
  void dispose() {
    _version.dispose();
    _build.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickApk() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['apk'],
      allowMultiple: false,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final bytes = file.bytes;

    if (bytes == null) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Die APK konnte nicht eingelesen werden.',
          ),
        ),
      );
      return;
    }

    final digest = sha256.convert(bytes).toString();

    if (!mounted) return;

    setState(() {
      _apkBytes = bytes;
      _apkName = file.name;
      _sha = digest;
      _fileSize = bytes.length;
    });
  }

  String _sizeLabel(int bytes) {
    final mb = bytes / 1024 / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  Future<void> _save() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final version = _version.text.trim();
    final build = int.tryParse(_build.text.trim());

    if (version.isEmpty || build == null || build <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bitte Version und gültige Buildnummer eintragen.',
          ),
        ),
      );
      return;
    }

    if (_apkBytes == null || _sha == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bitte zuerst eine APK auswählen.',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    String? uploadedPath;

    try {
      final safeVersion = version.replaceAll(
        RegExp(r'[^0-9A-Za-z._-]'),
        '_',
      );

      uploadedPath =
          'android/${build}_${safeVersion}_'
          '${DateTime.now().millisecondsSinceEpoch}.apk';

      await _supabase.storage
          .from('app-updates')
          .uploadBinary(
            uploadedPath,
            _apkBytes!,
            fileOptions: const FileOptions(
              contentType:
                  'application/vnd.android.package-archive',
              upsert: false,
              cacheControl: '3600',
            ),
          );

      await _supabase.from('app_releases').insert({
        'platform': 'android',
        'version_name': version,
        'build_number': build,
        'channel': _channel,
        'storage_path': uploadedPath,
        'sha256': _sha,
        'file_size_bytes': _fileSize,
        'notes': _notes.text.trim(),
        'force_update': _forceUpdate,
        'is_active': true,
        'created_by': user.id,
        'updated_by': user.id,
      });

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      // Falls die Datenbankanlage fehlschlägt, bleibt keine
      // verwaiste APK im Update-Bucket.
      if (uploadedPath != null) {
        try {
          await _supabase.storage
              .from('app-updates')
              .remove([uploadedPath]);
        } catch (_) {
          // Der ursprüngliche Fehler ist wichtiger.
        }
      }

      if (!mounted) return;

      setState(() => _saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Version konnte nicht angelegt werden: $e',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Neue Update-Version'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _InfoCard(
            icon: Icons.route_outlined,
            title: 'Empfohlener Ablauf',
            text:
                '1. NON – nur gespeichert. '
                '2. BETA – ausgewählte Tester. '
                '3. FOR ALL – alle Benutzer.',
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _version,
            decoration: const InputDecoration(
              labelText: 'Version *',
              hintText: 'z. B. 1.0.12',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _build,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Buildnummer *',
              hintText: 'z. B. 14',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            minLines: 3,
            maxLines: 7,
            decoration: const InputDecoration(
              labelText: 'Änderungen / Changelog',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Freigabe',
            style: TextStyle(
              color: _navy,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'non',
                label: Text('NON'),
              ),
              ButtonSegment(
                value: 'beta',
                label: Text('BETA'),
              ),
              ButtonSegment(
                value: 'forall',
                label: Text('FOR ALL'),
              ),
            ],
            selected: {_channel},
            onSelectionChanged: (value) {
              setState(() {
                _channel = value.first;
              });
            },
          ),
          const SizedBox(height: 10),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _forceUpdate,
            title: const Text(
              'Pflichtupdate',
              style: TextStyle(
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: const Text(
              'Bei Aktivierung kann die alte Version '
              'nicht weiter benutzt werden.',
            ),
            onChanged: (value) {
              setState(() {
                _forceUpdate = value;
              });
            },
          ),
          const Divider(height: 28),
          OutlinedButton.icon(
            onPressed: _saving ? null : _pickApk,
            icon: const Icon(
              Icons.android_outlined,
            ),
            label: Text(
              _apkName == null
                  ? 'APK auswählen'
                  : 'Andere APK auswählen',
            ),
          ),
          if (_apkName != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFFE3E8EE),
                ),
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    _apkName!,
                    style: const TextStyle(
                      color: _navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (_fileSize != null)
                    Text(
                      _sizeLabel(_fileSize!),
                      style: const TextStyle(
                        color: Color(0xFF667085),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    'SHA-256: $_sha',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: _blue,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
            ),
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.cloud_upload_outlined),
            label: Text(
              _saving
                  ? 'APK wird hochgeladen …'
                  : 'Version speichern',
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Hinweis: APK-Dateien sind oft groß. '
            'Bei instabiler Verbindung kann ein Upload aus der App '
            'fehlschlagen. Dann die APK direkt in den privaten '
            'Supabase-Storage-Bucket „app-updates“ hochladen und '
            'die Version anschließend erneut anlegen.',
            style: TextStyle(
              color: Color(0xFF667085),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChannelButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFE3E8EE),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 0),
          Icon(
            icon,
            color: const Color(0xFF0B4EA2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF0A1F44),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
