import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  bool _isTrainer = false;
  String? _error;
  List<Map<String, dynamic>> _profiles = [];
  List<Map<String, dynamic>> _links = [];
  String _searchQuery = '';
  String _roleFilter = 'alle';
  bool _onlyUnlinked = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Kein Benutzer angemeldet.');

      final own = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      final profiles = await _supabase
          .from('profiles')
          .select(
              'id,first_name,last_name,role,phone,notifications_enabled,approval_status,approved_at')
          .order('last_name')
          .order('first_name');

      final links = await _supabase
          .from('parent_child')
          .select('parent_id,child_id,created_at');

      if (!mounted) return;

      setState(() {
        _isTrainer =
            own?['role']?.toString().trim().toLowerCase() == 'ausbilder';
        _profiles = List<Map<String, dynamic>>.from(profiles);
        _links = List<Map<String, dynamic>>.from(links);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String _name(Map<String, dynamic> p) {
    final first = p['first_name']?.toString().trim() ?? '';
    final last = p['last_name']?.toString().trim() ?? '';
    final name = '$first $last'.trim();
    return name.isEmpty ? 'Ohne Namen' : name;
  }

  String _roleLabel(dynamic role) {
    switch (role?.toString()) {
      case 'ausbilder':
        return 'Ausbilder';
      case 'eltern':
        return 'Eltern';
      case 'jugendmitglied':
        return 'Jugendmitglied';
      default:
        return role?.toString() ?? '';
    }
  }

  Map<String, dynamic>? _profileById(String? id) {
    for (final p in _profiles) {
      if (p['id']?.toString() == id) return p;
    }
    return null;
  }

  bool _isLinked(Map<String, dynamic> p) {
    final id = p['id']?.toString();
    final role = p['role']?.toString();

    if (id == null) return false;

    if (role == 'eltern') {
      return _links.any((l) => l['parent_id']?.toString() == id);
    }

    if (role == 'jugendmitglied') {
      return _links.any((l) => l['child_id']?.toString() == id);
    }

    return true;
  }

  int _roleCount(String role) {
    if (role == 'alle') return _profiles.length;
    return _profiles.where((p) => p['role']?.toString() == role).length;
  }

  int get _unlinkedCount {
    return _profiles.where((p) {
      final role = p['role']?.toString();
      if (role != 'eltern' && role != 'jugendmitglied') return false;
      return !_isLinked(p);
    }).length;
  }

  String _relationsText(Map<String, dynamic> p) {
    final id = p['id']?.toString();
    final role = p['role']?.toString();

    if (role == 'eltern') {
      final names = _links
          .where((l) => l['parent_id']?.toString() == id)
          .map((l) => _profileById(l['child_id']?.toString()))
          .whereType<Map<String, dynamic>>()
          .map(_name)
          .toList();
      return names.isEmpty
          ? 'Keine Kinder verknüpft'
          : 'Kinder: ${names.join(', ')}';
    }

    if (role == 'jugendmitglied') {
      final names = _links
          .where((l) => l['child_id']?.toString() == id)
          .map((l) => _profileById(l['parent_id']?.toString()))
          .whereType<Map<String, dynamic>>()
          .map(_name)
          .toList();
      return names.isEmpty
          ? 'Keine Eltern verknüpft'
          : 'Eltern: ${names.join(', ')}';
    }

    return '';
  }

  Future<void> _editProfile(Map<String, dynamic> profile) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ProfileEditor(
        profile: profile,
        canChangeRole: _isTrainer,
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _manageLinks() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ParentChildManager(
        profiles: _profiles,
        links: _links,
      ),
    );
    if (changed == true) await _load();
  }

  List<Map<String, dynamic>> get _filteredProfiles {
    final query = _searchQuery.trim().toLowerCase();

    return _profiles.where((profile) {
      final role = profile['role']?.toString() ?? '';
      final name = _name(profile).toLowerCase();
      final phone = profile['phone']?.toString().toLowerCase() ?? '';

      final matchesSearch =
          query.isEmpty || name.contains(query) || phone.contains(query);

      final matchesRole = _roleFilter == 'alle' || role == _roleFilter;
      final matchesLink = !_onlyUnlinked || !_isLinked(profile);

      return matchesSearch && matchesRole && matchesLink;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0A1F44);
    const blue = Color(0xFF0B4EA2);
    const red = Color(0xFFE30613);
    const green = Color(0xFF13A05B);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF3F5F7),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Mitglieder konnten nicht geladen werden.\n\n$_error',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [navy, blue],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Image.asset(
                          'assets/branding/logo.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Mitglieder',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Profile und Verknüpfungen verwalten',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_isTrainer)
                        IconButton(
                          tooltip: 'Eltern und Kinder verknüpfen',
                          onPressed: _manageLinks,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: red,
                          ),
                          icon: const Icon(Icons.family_restroom),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
              child: Column(
                children: [
                  TextField(
                    onChanged: (value) {
                      setState(() => _searchQuery = value);
                    },
                    decoration: InputDecoration(
                      hintText: 'Mitglied suchen',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(0xFFE3E8EE),
                            ),
                          ),
                          child: Text(
                            '${_profiles.length} Mitglieder · '
                            '${_links.length} Verknüpfungen',
                            style: const TextStyle(
                              color: navy,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      if (_unlinkedCount > 0) ...[
                        const SizedBox(width: 8),
                        FilterChip(
                          avatar: const Icon(
                            Icons.link_off,
                            size: 18,
                          ),
                          label: Text('Ohne Link ($_unlinkedCount)'),
                          selected: _onlyUnlinked,
                          onSelected: (value) {
                            setState(() => _onlyUnlinked = value);
                          },
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 42,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        ChoiceChip(
                          label: Text('Alle (${_roleCount('alle')})'),
                          selected: _roleFilter == 'alle',
                          onSelected: (_) =>
                              setState(() => _roleFilter = 'alle'),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: Text(
                            'Ausbilder (${_roleCount('ausbilder')})',
                          ),
                          selected: _roleFilter == 'ausbilder',
                          onSelected: (_) =>
                              setState(() => _roleFilter = 'ausbilder'),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: Text(
                            'Jugend (${_roleCount('jugendmitglied')})',
                          ),
                          selected: _roleFilter == 'jugendmitglied',
                          onSelected: (_) =>
                              setState(() => _roleFilter = 'jugendmitglied'),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: Text('Eltern (${_roleCount('eltern')})'),
                          selected: _roleFilter == 'eltern',
                          onSelected: (_) =>
                              setState(() => _roleFilter = 'eltern'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
              child: _filteredProfiles.isEmpty
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 40,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE3E8EE)),
                      ),
                      child: const Column(
                        children: [
                          Icon(
                            Icons.person_search,
                            size: 58,
                            color: Color(0xFF0B4EA2),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Keine passenden Mitglieder gefunden.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0A1F44),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: _filteredProfiles.map((p) {
                        final relation = _relationsText(p);
                        final role = p['role']?.toString();

                        Color accent;
                        IconData icon;

                        if (role == 'ausbilder') {
                          accent = red;
                          icon = Icons.local_fire_department;
                        } else if (role == 'eltern') {
                          accent = blue;
                          icon = Icons.family_restroom;
                        } else {
                          accent = green;
                          icon = Icons.person;
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFE3E8EE),
                            ),
                            boxShadow: const [
                              BoxShadow(
                                blurRadius: 12,
                                offset: Offset(0, 4),
                                color: Color(0x0D000000),
                              ),
                            ],
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => _editProfile(p),
                            child: Padding(
                              padding: const EdgeInsets.all(15),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 54,
                                    height: 54,
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Icon(
                                      icon,
                                      color: accent,
                                      size: 29,
                                    ),
                                  ),
                                  const SizedBox(width: 13),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _name(p),
                                          style: const TextStyle(
                                            color: navy,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            Text(
                                              _roleLabel(role),
                                              style: TextStyle(
                                                color: accent,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            if (role == 'eltern' ||
                                                role == 'jugendmitglied')
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 7,
                                                  vertical: 3,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: (_isLinked(p)
                                                          ? const Color(
                                                              0xFF13A05B,
                                                            )
                                                          : const Color(
                                                              0xFFFF8A00,
                                                            ))
                                                      .withValues(
                                                    alpha: 0.12,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                    999,
                                                  ),
                                                ),
                                                child: Text(
                                                  _isLinked(p)
                                                      ? 'Verknüpft'
                                                      : 'Nicht verknüpft',
                                                  style: TextStyle(
                                                    color: _isLinked(p)
                                                        ? const Color(
                                                            0xFF13A05B,
                                                          )
                                                        : const Color(
                                                            0xFFFF8A00,
                                                          ),
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        if ((p['phone'] ?? '')
                                            .toString()
                                            .trim()
                                            .isNotEmpty) ...[
                                          const SizedBox(height: 7),
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.phone_outlined,
                                                size: 17,
                                                color: Color(0xFF98A2B3),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                p['phone'].toString(),
                                                style: const TextStyle(
                                                  color: Color(0xFF667085),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                        const SizedBox(height: 7),
                                        Row(
                                          children: [
                                            Icon(
                                              p['notifications_enabled'] == true
                                                  ? Icons
                                                      .notifications_active_outlined
                                                  : Icons
                                                      .notifications_off_outlined,
                                              size: 17,
                                              color:
                                                  p['notifications_enabled'] ==
                                                          true
                                                      ? green
                                                      : const Color(0xFF98A2B3),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              p['notifications_enabled'] == true
                                                  ? 'Push aktiviert'
                                                  : 'Push deaktiviert',
                                              style: const TextStyle(
                                                color: Color(0xFF667085),
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (relation.isNotEmpty) ...[
                                          const SizedBox(height: 7),
                                          Text(
                                            relation,
                                            style: const TextStyle(
                                              color: Color(0xFF667085),
                                              height: 1.3,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right,
                                    color: Color(0xFF98A2B3),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: _isTrainer
          ? FloatingActionButton(
              onPressed: _manageLinks,
              backgroundColor: red,
              foregroundColor: Colors.white,
              child: const Icon(Icons.family_restroom),
            )
          : null,
    );
  }
}

class _ProfileEditor extends StatefulWidget {
  final Map<String, dynamic> profile;
  final bool canChangeRole;

  const _ProfileEditor({
    required this.profile,
    required this.canChangeRole,
  });

  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  final _supabase = Supabase.instance.client;
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _phone;
  late String _role;
  late bool _notificationsEnabled;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _firstName = TextEditingController(
        text: widget.profile['first_name']?.toString() ?? '');
    _lastName = TextEditingController(
        text: widget.profile['last_name']?.toString() ?? '');
    _phone =
        TextEditingController(text: widget.profile['phone']?.toString() ?? '');
    _role = widget.profile['role']?.toString() ?? 'jugendmitglied';
    _notificationsEnabled = widget.profile['notifications_enabled'] == true;
  }

  Future<void> _approveAccount() async {
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null) return;

    try {
      await _supabase.from('profiles').update({
        'approval_status': 'approved',
        'approved_by': currentUser.id,
        'approved_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.profile['id']);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konto wurde freigegeben.')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Freigabe fehlgeschlagen: $e')),
      );
    }
  }

  Future<void> _deleteAccount() async {
    final role = widget.profile['role']?.toString();
    if (role != 'jugendmitglied' && role != 'eltern') return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mitglied entfernen?'),
        content: const Text(
          'Das Mitglied wird vollständig aus der App entfernt. '
          'Das Konto kann sich danach nicht mehr anmelden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Color(0xFFE30613),
            ),
            child: const Text('Entfernen'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await _supabase.functions.invoke(
        'delete-member',
        body: {'target_user_id': widget.profile['id']},
      );

      if (response.status >= 400) {
        throw Exception('Serverfehler ${response.status}');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mitglied wurde entfernt.')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Entfernen fehlgeschlagen: $e')),
      );
    }
  }

  Future<void> _save() async {
    if (_firstName.text.trim().isEmpty || _lastName.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Vorname und Nachname sind erforderlich.')),
      );
      return;
    }

    setState(() => _saving = true);

    final data = <String, dynamic>{
      'first_name': _firstName.text.trim(),
      'last_name': _lastName.text.trim(),
      'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      'notifications_enabled': _notificationsEnabled,
    };

    if (widget.canChangeRole) {
      data['role'] = _role;
    }

    try {
      await _supabase
          .from('profiles')
          .update(data)
          .eq('id', widget.profile['id']);

      if (widget.canChangeRole) {
        try {
          await _supabase.functions.invoke(
            'send-push',
            body: {
              'user_id': widget.profile['id'],
              'title': 'Profil aktualisiert',
              'body': 'Deine Profildaten wurden aktualisiert.',
            },
          );
        } catch (pushError) {
          debugPrint('Profil gespeichert, Push fehlgeschlagen: $pushError');
        }
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speichern fehlgeschlagen: $e')),
      );
    }
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Profil bearbeiten',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _firstName,
              decoration: const InputDecoration(
                labelText: 'Vorname *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _lastName,
              decoration: const InputDecoration(
                labelText: 'Nachname *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Telefon',
                border: OutlineInputBorder(),
              ),
            ),
            if (widget.canChangeRole) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(
                  labelText: 'Rolle',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'ausbilder', child: Text('Ausbilder')),
                  DropdownMenuItem(value: 'eltern', child: Text('Eltern')),
                  DropdownMenuItem(
                    value: 'jugendmitglied',
                    child: Text('Jugendmitglied'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _role = value);
                },
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Push-Benachrichtigungen'),
              value: _notificationsEnabled,
              onChanged: (value) {
                setState(() => _notificationsEnabled = value);
              },
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save),
                label: const Text('Speichern'),
              ),
            ),
            if (widget.canChangeRole &&
                (widget.profile['role']?.toString() == 'jugendmitglied' ||
                    widget.profile['role']?.toString() == 'eltern')) ...[
              if (widget.profile['approval_status']?.toString() !=
                  'approved') ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _approveAccount,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF13A05B),
                    ),
                    icon: const Icon(Icons.verified_user_outlined),
                    label: const Text('Konto freigeben'),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _deleteAccount,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE30613),
                    side: const BorderSide(color: Color(0xFFE30613)),
                  ),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Mitglied entfernen'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ParentChildManager extends StatefulWidget {
  final List<Map<String, dynamic>> profiles;
  final List<Map<String, dynamic>> links;

  const _ParentChildManager({
    required this.profiles,
    required this.links,
  });

  @override
  State<_ParentChildManager> createState() => _ParentChildManagerState();
}

class _ParentChildManagerState extends State<_ParentChildManager> {
  final _supabase = Supabase.instance.client;
  late List<Map<String, dynamic>> _links;
  String? _parentId;
  String? _childId;
  bool _saving = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _links = widget.links.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  String _nameById(String? id) {
    for (final p in widget.profiles) {
      if (p['id']?.toString() == id) {
        final first = p['first_name']?.toString().trim() ?? '';
        final last = p['last_name']?.toString().trim() ?? '';
        final name = '$first $last'.trim();
        return name.isEmpty ? 'Ohne Namen' : name;
      }
    }
    return 'Unbekannt';
  }

  List<Map<String, dynamic>> get _sortedLinks {
    final result = _links.map((e) => Map<String, dynamic>.from(e)).toList();
    result.sort((a, b) {
      final parentCompare =
          _nameById(a['parent_id']?.toString()).toLowerCase().compareTo(
                _nameById(b['parent_id']?.toString()).toLowerCase(),
              );
      if (parentCompare != 0) return parentCompare;

      return _nameById(a['child_id']?.toString()).toLowerCase().compareTo(
            _nameById(b['child_id']?.toString()).toLowerCase(),
          );
    });
    return result;
  }

  Future<void> _add() async {
    if (_parentId == null || _childId == null || _saving) return;

    final exists = _links.any(
      (l) =>
          l['parent_id']?.toString() == _parentId &&
          l['child_id']?.toString() == _childId,
    );

    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Diese Verknüpfung besteht bereits.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      await _supabase.from('parent_child').insert({
        'parent_id': _parentId,
        'child_id': _childId,
      });

      if (!mounted) return;

      setState(() {
        _links.add({'parent_id': _parentId, 'child_id': _childId});
        _childId = null;
        _saving = false;
        _changed = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Eltern-Kind-Verknüpfung wurde gespeichert.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Verknüpfen fehlgeschlagen: $e')),
      );
    }
  }

  Future<void> _remove(Map<String, dynamic> link) async {
    if (_saving) return;

    final parentName = _nameById(link['parent_id']?.toString());
    final childName = _nameById(link['child_id']?.toString());

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Verknüpfung lösen?'),
        content: Text(
          'Soll die Verknüpfung zwischen $parentName und $childName '
          'wirklich entfernt werden?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Entfernen'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);

    try {
      await _supabase
          .from('parent_child')
          .delete()
          .eq('parent_id', link['parent_id'])
          .eq('child_id', link['child_id']);

      if (!mounted) return;

      setState(() {
        _links.removeWhere(
          (l) =>
              l['parent_id']?.toString() == link['parent_id']?.toString() &&
              l['child_id']?.toString() == link['child_id']?.toString(),
        );
        _saving = false;
        _changed = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verknüpfung wurde entfernt.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Entfernen fehlgeschlagen: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final parents = widget.profiles
        .where((p) => p['role']?.toString() == 'eltern')
        .toList();

    final children = widget.profiles
        .where((p) => p['role']?.toString() == 'jugendmitglied')
        .toList();

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Eltern & Kinder verknüpfen',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FB),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '${parents.length} Elternteile · '
                '${children.length} Jugendmitglieder · '
                '${_links.length} Verknüpfungen',
                style: const TextStyle(
                  color: Color(0xFF0A1F44),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (parents.isEmpty || children.isEmpty) ...[
              const SizedBox(height: 12),
              const Card(
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Verknüpfung aktuell nicht möglich'),
                  subtitle: Text(
                    'Es muss mindestens ein Elternkonto und ein '
                    'Jugendmitglied vorhanden sein.',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              initialValue: _parentId,
              decoration: const InputDecoration(
                labelText: 'Elternteil',
                border: OutlineInputBorder(),
              ),
              items: parents
                  .map(
                    (p) => DropdownMenuItem(
                      value: p['id'].toString(),
                      child: Text(_nameById(p['id'].toString())),
                    ),
                  )
                  .toList(),
              onChanged: parents.isEmpty
                  ? null
                  : (value) => setState(() => _parentId = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _childId,
              decoration: const InputDecoration(
                labelText: 'Jugendmitglied',
                border: OutlineInputBorder(),
              ),
              items: children
                  .map(
                    (p) => DropdownMenuItem(
                      value: p['id'].toString(),
                      child: Text(_nameById(p['id'].toString())),
                    ),
                  )
                  .toList(),
              onChanged: children.isEmpty
                  ? null
                  : (value) => setState(() => _childId = value),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving || _parentId == null || _childId == null
                    ? null
                    : _add,
                icon: const Icon(Icons.link),
                label: const Text('Verknüpfen'),
              ),
            ),
            const SizedBox(height: 20),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Bestehende Verknüpfungen',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            if (_links.isEmpty)
              const Card(
                child: ListTile(title: Text('Noch keine Verknüpfungen.')),
              )
            else
              ..._sortedLinks.map(
                (link) => Card(
                  child: ListTile(
                    title: Text(
                      '${_nameById(link['parent_id']?.toString())} → '
                      '${_nameById(link['child_id']?.toString())}',
                    ),
                    trailing: IconButton(
                      onPressed: _saving ? null : () => _remove(link),
                      icon: const Icon(Icons.link_off),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, _changed),
                child: const Text('Fertig'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
