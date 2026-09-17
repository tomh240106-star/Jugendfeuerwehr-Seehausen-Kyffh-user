import 'package:flutter/material.dart';

enum LegalSection { datenschutz, impressum }

class LegalScreen extends StatelessWidget {
  final LegalSection initialSection;

  const LegalScreen({
    super.key,
    this.initialSection = LegalSection.datenschutz,
  });

  static const _placeholder =
      'BITTE VOR VERÖFFENTLICHUNG ERGÄNZEN';

  @override
  Widget build(BuildContext context) {
    final privacy = initialSection == LegalSection.datenschutz;

    return Scaffold(
      appBar: AppBar(
        title: Text(privacy ? 'Datenschutz' : 'Impressum'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (privacy) ..._privacyWidgets() else ..._imprintWidgets(),
          ],
        ),
      ),
    );
  }

  List<Widget> _privacyWidgets() {
    return [
      _warning(),
      _heading('Datenschutzhinweise'),
      _paragraph(
        'Diese App dient der Organisation der Jugendfeuerwehr '
        'Seehausen/Kyffhäuser. Sie verarbeitet personenbezogene Daten '
        'ausschließlich für die in der App bereitgestellten Funktionen.',
      ),
      _heading('Verantwortliche Stelle'),
      _paragraph(
        '$_placeholder\n'
        'Name der verantwortlichen Organisation\n'
        'Anschrift\n'
        'E-Mail-Adresse\n'
        'Telefon',
      ),
      _heading('Verarbeitete Daten'),
      _paragraph(
        'Je nach Nutzung können insbesondere Name, E-Mail-Adresse, '
        'Telefonnummer, Benutzerrolle, Termin-Rückmeldungen, Nachrichten, '
        'Dokumentzugriffe, Geräte-Token für Push-Benachrichtigungen sowie '
        'Alarm-Rückmeldungen verarbeitet werden.',
      ),
      _heading('Zwecke der Verarbeitung'),
      _paragraph(
        'Die Verarbeitung erfolgt zur Benutzerverwaltung, Termin- und '
        'Ausbildungsplanung, internen Kommunikation, Bereitstellung von '
        'Dokumenten sowie zur Alarmierung innerhalb der Jugendfeuerwehr.',
      ),
      _heading('Technische Dienstleister'),
      _paragraph(
        'Für Anmeldung, Datenbank und Dateispeicherung wird Supabase '
        'eingesetzt. Für Push-Benachrichtigungen wird Firebase Cloud '
        'Messaging verwendet. Vor der Veröffentlichung sind die konkreten '
        'Anbieterinformationen, Auftragsverarbeitungsverträge, '
        'Datenstandorte und gegebenenfalls Drittlandübermittlungen '
        'abschließend zu prüfen und hier zu ergänzen.',
      ),
      _heading('Speicherdauer'),
      _paragraph(
        'Personenbezogene Daten werden nur so lange gespeichert, wie sie '
        'für den jeweiligen Zweck erforderlich sind oder gesetzliche '
        'Aufbewahrungspflichten bestehen. Konkrete Löschfristen sind durch '
        'die verantwortliche Stelle festzulegen.',
      ),
      _heading('Betroffenenrechte'),
      _paragraph(
        'Betroffene Personen haben im Rahmen der gesetzlichen Voraussetzungen '
        'insbesondere Rechte auf Auskunft, Berichtigung, Löschung, '
        'Einschränkung der Verarbeitung, Datenübertragbarkeit und Widerspruch. '
        'Für Minderjährige sind die jeweils anwendbaren gesetzlichen '
        'Vorgaben besonders zu berücksichtigen.',
      ),
      _heading('Kontakt Datenschutz'),
      _paragraph(
        '$_placeholder\n'
        'Datenschutz-Kontakt / Datenschutzbeauftragte Person, soweit erforderlich.',
      ),
      _heading('Stand'),
      _paragraph('September 2026'),
    ];
  }

  List<Widget> _imprintWidgets() {
    return [
      _warning(),
      _heading('Impressum'),
      _paragraph(
        'Angaben gemäß den für den Anbieter geltenden gesetzlichen '
        'Informationspflichten.',
      ),
      _heading('Anbieter / Verantwortliche Organisation'),
      _paragraph(
        '$_placeholder\n'
        'Vollständiger Name der Organisation\n'
        'Rechtsform / Träger\n'
        'Straße und Hausnummer\n'
        'PLZ Ort',
      ),
      _heading('Vertretungsberechtigte Person'),
      _paragraph('$_placeholder'),
      _heading('Kontakt'),
      _paragraph(
        'Telefon: $_placeholder\n'
        'E-Mail: $_placeholder',
      ),
      _heading('Weitere Pflichtangaben'),
      _paragraph(
        'Je nach Träger, Rechtsform und Internetauftritt können weitere '
        'Pflichtangaben erforderlich sein. Diese Angaben müssen vor einer '
        'öffentlichen Veröffentlichung rechtlich geprüft und ergänzt werden.',
      ),
    ];
  }

  Widget _warning() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF4C76B)),
      ),
      child: const Text(
        'Entwurf für die App. Die mit „BITTE VOR VERÖFFENTLICHUNG ERGÄNZEN“ '
        'markierten Angaben müssen vor dem Store-Release mit den tatsächlichen '
        'Daten der verantwortlichen Organisation ergänzt und rechtlich geprüft werden.',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
    );
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
