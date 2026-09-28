HOME-DESIGN ÄNDERUNGEN

DATEI:
lib/screens/home_shell.dart

1) Ersetze in _ModernDashboardState die komplette build()-Methode durch:

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/branding/app_background.jpg',
          fit: BoxFit.cover,
        ),
        Container(
          color: const Color(0xFF06162E).withValues(alpha: 0.48),
        ),
        RefreshIndicator(
          onRefresh: _refreshAll,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _HeroHeader(
                title: _firstName,
                subtitle: _isTrainer
                    ? 'Ausbilder · Jugendfeuerwehr Seehausen/Kyffhäuser'
                    : 'Jugendfeuerwehr Seehausen/Kyffhäuser',
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: Colors.red,
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                child: Column(
                  children: [
                    if (_canUseAlarm) ...[
                      _FeatureCard(
                        background: _activeAlarm != null
                            ? _red
                            : const Color(0xFFB3000C),
                        icon: _activeAlarm != null
                            ? Icons.notification_important
                            : Icons.notifications_active,
                        eyebrow: _activeAlarm != null
                            ? 'AKTIVER JUGENDFEUERWEHR-ALARM'
                            : 'JUGENDFEUERWEHR-ALARM',
                        title:
                            _activeAlarm?['title']?.toString() ??
                                'Alarm & Rückmeldung',
                        subtitle: _activeAlarm != null
                            ? '${(_activeAlarm!['location'] ?? 'Treffpunkt siehe Alarm').toString()}\n'
                                'Jetzt Rückmeldung öffnen'
                            : (_isTrainer
                                ? 'Alarm auslösen und Rückmeldungen '
                                    'der Jugendmitglieder sehen.'
                                : 'Hier erscheinen aktive Alarme '
                                    'und deine Rückmeldung.'),
                        onTap: widget.onOpenAlarm,
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (_isTrainer) ...[
                      _FeatureCard(
                        background: _navy,
                        icon: Icons.account_tree_outlined,
                        eyebrow: 'NUR FÜR AUSBILDER',
                        title: 'Projekte',
                        subtitle:
                            '$_openProjectCount offene Projekte · '
                            '$_openProjectTaskCount offene Aufgaben\n'
                            'Planen, Aufgaben verteilen und Fortschritt verfolgen.',
                        onTap: widget.onOpenProjekte,
                      ),
                      const SizedBox(height: 14),
                    ],
                    _FeatureCard(
                      background: _red,
                      icon: Icons.calendar_month,
                      eyebrow: 'NÄCHSTER TERMIN',
                      title: _nextEvent?['title']?.toString() ??
                          'Kein Termin',
                      subtitle: _nextEvent == null
                          ? 'Aktuell ist kein zukünftiger Termin eingetragen.'
                          : (_profile?['role']?.toString() == 'eltern'
                              ? '${_eventDate(_nextEvent!['starts_at'])}\n'
                                  '${_nextEvent!['location'] ?? ''}'
                              : '${_eventDate(_nextEvent!['starts_at'])}\n'
                                  '${_nextEvent!['location'] ?? ''}\n'
                                  '• ${_attendanceText()}'),
                      onTap: widget.onOpenTermine,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _DashboardStat(
                            icon: Icons.event_available_outlined,
                            value: '$_upcomingEventCount',
                            label: 'kommende Termine',
                            onTap: widget.onOpenTermine,
                          ),
                        ),
                        if (_profile?['role']?.toString() != 'eltern') ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: _DashboardStat(
                              icon: Icons.how_to_reg_outlined,
                              value: '$_openAttendanceCount',
                              label: 'Rückmeldungen offen',
                              onTap: widget.onOpenTermine,
                              highlight: _openAttendanceCount > 0,
                            ),
                          ),
                        ],
                        const SizedBox(width: 10),
                        Expanded(
                          child: _DashboardStat(
                            icon: Icons.notifications_none,
                            value:
                                '${widget.unreadMessages + widget.newDocuments}',
                            label: 'neue Hinweise',
                            onTap: widget.unreadMessages > 0
                                ? widget.onOpenNachrichten
                                : widget.onOpenDokumente,
                            highlight: widget.unreadMessages > 0 ||
                                widget.newDocuments > 0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _MiniFeature(
                            background: _blue,
                            icon: Icons.chat_bubble_outline,
                            value: widget.unreadMessages.toString(),
                            label: 'neue Nachrichten',
                            onTap: widget.onOpenNachrichten,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _MiniFeature(
                            background: _green,
                            icon: Icons.folder_open,
                            value: widget.newDocuments.toString(),
                            label: 'neue Dokumente',
                            onTap: widget.onOpenDokumente,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _MiniFeature(
                            background: _orange,
                            icon: Icons.menu_book_outlined,
                            value: 'Plan',
                            label:
                                _trainingPlan?['title']?.toString() ??
                                    'Ausbildung',
                            onTap: widget.onOpenAusbildung,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _MiniFeature(
                            background: Colors.white,
                            foreground: _navy,
                            icon: Icons.groups_outlined,
                            value: _isTrainer
                                ? '$_memberCount'
                                : 'Profil',
                            label: _isTrainer
                                ? 'Mitglieder'
                                : 'Mein Bereich',
                            onTap: _isTrainer
                                ? widget.onOpenMitglieder
                                : () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const _MyProfileScreen(),
                                      ),
                                    );
                                  },
                            bordered: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.16),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const _SectionCard(
                        icon: Icons.sailing_outlined,
                        title: 'Gemeinsam. Stark. Für morgen.',
                        subtitle:
                            'Jugendfeuerwehr Seehausen/Kyffhäuser',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }


2) Ersetze die komplette Klasse _HeroHeader durch:

class _HeroHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _HeroHeader({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 280,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(34),
          bottomRight: Radius.circular(34),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/branding/app_background.jpg',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF06162E).withValues(alpha: 0.24),
                  const Color(0xFF06162E).withValues(alpha: 0.78),
                ],
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 62,
                        height: 62,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A1F44)
                              .withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.70),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.24),
                              blurRadius: 14,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.asset(
                            'assets/branding/logo.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Jugendfeuerwehr\nSeehausen/Kyffhäuser',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            height: 1.05,
                            fontSize: 17,
                            shadows: [
                              Shadow(
                                blurRadius: 8,
                                color: Colors.black54,
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Abmelden',
                        style: IconButton.styleFrom(
                          backgroundColor:
                              Colors.black.withValues(alpha: 0.20),
                        ),
                        onPressed: () async {
                          final confirmed =
                              await showDialog<bool>(
                            context: context,
                            builder: (dialogContext) =>
                                AlertDialog(
                              title: const Text('Abmelden?'),
                              content: const Text(
                                'Möchtest du dich wirklich '
                                'aus der App abmelden?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(
                                    dialogContext,
                                    false,
                                  ),
                                  child: const Text('Abbrechen'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.pop(
                                    dialogContext,
                                    true,
                                  ),
                                  child: const Text('Abmelden'),
                                ),
                              ],
                            ),
                          );

                          if (confirmed == true) {
                            await PushService
                                .unregisterCurrentDevice();

                            await Supabase.instance.client.auth
                                .signOut();
                          }
                        },
                        icon: const Icon(
                          Icons.logout,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      shadows: [
                        Shadow(
                          blurRadius: 12,
                          color: Colors.black87,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      shadows: [
                        Shadow(
                          blurRadius: 8,
                          color: Colors.black87,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
