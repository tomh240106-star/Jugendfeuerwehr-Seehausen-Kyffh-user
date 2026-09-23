import 'package:flutter/material.dart';

import '../services/home_navigation.dart';

enum LegalSection { datenschutz, kontakt }

class LegalScreen extends StatelessWidget {
  final LegalSection initialSection;

  const LegalScreen({
    super.key,
    this.initialSection = LegalSection.datenschutz,
  });

  static const _name = 'Jugendfeuerwehr Seehausen/Kyffhäuser';

  @override
  Widget build(BuildContext context) {
    final privacy = initialSection == LegalSection.datenschutz;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Zur Startseite',
            onPressed: () => HomeNavigation.goHome(context),
            icon: const Icon(Icons.home_outlined),
          ),
        ],
        title: Text(
          privacy ? 'Datenschutz' : 'Kontakt & Verantwortliche Stelle',
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (privacy) ..._privacyWidgets() else ..._contactWidgets(),
          ],
        ),
      ),
    );
  }

  List<Widget> _privacyWidgets() {
    return [
      _heading('Datenschutzhinweise'),
      _paragraph(
        'Diese App wird ausschließlich für die interne Organisation der '
        '$_name genutzt. Sie ist nicht für die allgemeine Öffentlichkeit bestimmt.',
      ),
      _heading('Verantwortliche Stelle'),
      _paragraph(_name),
      _heading('Verarbeitete Daten'),
      _paragraph(
        'Je nach Nutzung können insbesondere Name, E-Mail-Adresse, '
        'Telefonnummer, Benutzerrolle, Termin-Rückmeldungen, Nachrichten, '
        'Dokumentzugriffe, Geräte-Token für Push-Benachrichtigungen sowie '
        'Alarm-Rückmeldungen verarbeitet werden.',
      ),
      _heading('Zwecke der Verarbeitung'),
      _paragraph(
        'Die Daten werden ausschließlich für interne Zwecke der Jugendfeuerwehr '
        'verarbeitet, insbesondere für Benutzerverwaltung, Terminplanung, '
        'Ausbildungsplanung, interne Kommunikation, Dokumentbereitstellung '
        'und Alarmierung.',
      ),
      _heading('Technische Dienste'),
      _paragraph(
        'Für Anmeldung, Datenbank und Dateispeicherung wird Supabase genutzt. '
        'Für Push-Benachrichtigungen wird Firebase Cloud Messaging verwendet.',
      ),
      _heading('Zugriff'),
      _paragraph(
        'Auf die App und ihre Inhalte erhalten nur berechtigte Mitglieder, '
        'Eltern und Ausbilder der Jugendfeuerwehr Zugriff. Die Rechte werden '
        'rollenbezogen vergeben.',
      ),
      _heading('Speicherdauer'),
      _paragraph(
        'Daten werden nur so lange gespeichert, wie sie für die interne '
        'Organisation erforderlich sind oder ein berechtigter Grund für die '
        'weitere Speicherung besteht.',
      ),
      _heading('Rechte der betroffenen Personen'),
      _paragraph(
        'Betroffene Personen können im Rahmen der gesetzlichen Voraussetzungen '
        'Auskunft, Berichtigung, Löschung oder Einschränkung der Verarbeitung '
        'verlangen. Bei Minderjährigen sind zusätzlich die jeweils geltenden '
        'Vorgaben zu berücksichtigen.',
      ),
      _heading('Kontakt'),
      _paragraph(
        'Kontakt zur verantwortlichen Stelle erfolgt intern über die bekannten '
        'Ansprechpartner der $_name.',
      ),
      _heading('Stand'),
      _paragraph('September 2026'),
    ];
  }

  List<Widget> _contactWidgets() {
    return [
      _heading('Verantwortliche Stelle'),
      _paragraph(_name),
      _heading('Nutzung der App'),
      _paragraph(
        'Die App wird ausschließlich intern innerhalb der Jugendfeuerwehr '
        'verwendet und dient der Organisation von Terminen, Ausbildung, '
        'Nachrichten, Dokumenten und Alarmierungen.',
      ),
      _heading('Kontakt'),
      _paragraph(
        'Die Kontaktaufnahme erfolgt intern über die bekannten Ansprechpartner '
        'der $_name.',
      ),
      _heading('Hinweis'),
      _paragraph(
        'Sollte die App später öffentlich angeboten oder außerhalb der '
        'Jugendfeuerwehr eingesetzt werden, müssen die rechtlichen Angaben '
        'erneut geprüft und gegebenenfalls erweitert werden.',
      ),
    ];
  }

  Widget _heading(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: Color(0xFF0A1F44),
        ),
      ),
    );
  }

  Widget _paragraph(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 15,
          height: 1.45,
          color: Color(0xFF344054),
        ),
      ),
    );
  }
}
