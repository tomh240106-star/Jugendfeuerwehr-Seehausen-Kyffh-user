import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';

import '../services/app_update_service.dart';
import '../services/developer_error_logger.dart';

class AndroidUpdateGate extends StatefulWidget {
  final Widget child;

  const AndroidUpdateGate({
    super.key,
    required this.child,
  });

  @override
  State<AndroidUpdateGate> createState() =>
      _AndroidUpdateGateState();
}

class _AndroidUpdateGateState extends State<AndroidUpdateGate>
    with WidgetsBindingObserver {
  static const _navy = Color(0xFF0A1F44);
  static const _blue = Color(0xFF0B4EA2);
  static const _red = Color(0xFFE30613);
  static const _green = Color(0xFF13A05B);

  StreamSubscription<OtaEvent>? _subscription;

  bool _checking = true;
  bool _downloading = false;
  bool _installTriggered = false;
  bool _failed = false;
  bool _allowAppAfterFailure = false;

  double _progress = 0;
  String _status = 'Suche nach Updates …';
  String? _details;
  AppRelease? _release;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndStart();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Wenn der Android-Installer verlassen wurde und die alte App
    // weiterläuft, bleibt ein Pflichtupdate gesperrt. Bei einem
    // freiwilligen Update darf der Nutzer anschließend weiterarbeiten.
    if (state == AppLifecycleState.resumed &&
        _installTriggered &&
        _release?.forceUpdate != true) {
      if (mounted) {
        setState(() {
          _allowAppAfterFailure = true;
        });
      }
    }
  }

  Future<void> _checkAndStart() async {
    if (!AppUpdateService.supportsAutomaticUpdate) {
      if (mounted) {
        setState(() => _checking = false);
      }
      return;
    }

    if (mounted) {
      setState(() {
        _checking = true;
        _failed = false;
        _details = null;
        _status = 'Suche nach Updates …';
      });
    }

    try {
      final release =
          await AppUpdateService.findLatestAllowedUpdate();

      if (!mounted) return;

      if (release == null) {
        setState(() {
          _release = null;
          _checking = false;
        });
        return;
      }

      setState(() {
        _release = release;
        _checking = false;
        _status =
            'Version ${release.versionName} wird vorbereitet …';
      });

      await _downloadAndInstall(release);
    } catch (error, stack) {
      await DeveloperErrorLogger.logError(
        error,
        stack,
        source: 'AndroidUpdateGate.check',
        severity: 'error',
      );

      if (!mounted) return;

      setState(() {
        _checking = false;
        _failed = true;
        _status = 'Updateprüfung fehlgeschlagen';
        _details = error.toString();
      });
    }
  }

  Future<void> _downloadAndInstall(
    AppRelease release,
  ) async {
    await _subscription?.cancel();

    setState(() {
      _downloading = true;
      _failed = false;
      _installTriggered = false;
      _allowAppAfterFailure = false;
      _progress = 0;
      _details = null;
      _status =
          'Update ${release.versionName} wird heruntergeladen …';
    });

    try {
      final url =
          await AppUpdateService.createDownloadUrl(release);

      final stream = OtaUpdate().execute(
        url,
        destinationFilename:
            'jf_update_${release.buildNumber}.apk',
        sha256checksum: release.sha256.toLowerCase(),
      );

      _subscription = stream.listen(
        _handleOtaEvent,
        onError: (Object error, StackTrace stack) async {
          await DeveloperErrorLogger.logError(
            error,
            stack,
            source: 'AndroidUpdateGate.otaStream',
            severity: 'error',
            context: {
              'build_number': release.buildNumber,
            },
          );

          if (!mounted) return;

          setState(() {
            _downloading = false;
            _failed = true;
            _status = 'Update konnte nicht geladen werden';
            _details = error.toString();
          });
        },
      );
    } catch (error, stack) {
      await DeveloperErrorLogger.logError(
        error,
        stack,
        source: 'AndroidUpdateGate.download',
        severity: 'error',
        context: {
          'build_number': release.buildNumber,
        },
      );

      if (!mounted) return;

      setState(() {
        _downloading = false;
        _failed = true;
        _status = 'Update konnte nicht gestartet werden';
        _details = error.toString();
      });
    }
  }

  Future<void> _handleOtaEvent(OtaEvent event) async {
    if (!mounted) return;

    switch (event.status) {
      case OtaStatus.DOWNLOADING:
        final parsed =
            double.tryParse(event.value ?? '0') ?? 0;

        setState(() {
          _downloading = true;
          _progress = parsed.clamp(0, 100) / 100;
          _status = 'Update wird heruntergeladen …';
          _details = '${parsed.toStringAsFixed(0)} %';
        });
        break;

      case OtaStatus.INSTALLING:
        setState(() {
          _downloading = false;
          _installTriggered = true;
          _progress = 1;
          _status = 'Android-Installation wurde geöffnet';
          _details =
              'Bitte bestätige die Installation des Updates.';
        });
        break;

      case OtaStatus.INSTALLATION_DONE:
        setState(() {
          _downloading = false;
          _installTriggered = true;
          _progress = 1;
          _status = 'Update wurde installiert';
        });
        break;

      case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
        await _setOtaFailure(
          'Installationsberechtigung fehlt',
          'Erlaube Android, Apps aus dieser Quelle zu installieren, '
              'und tippe anschließend auf „Erneut versuchen“.',
          event,
        );
        break;

      case OtaStatus.CHECKSUM_ERROR:
        await _setOtaFailure(
          'Sicherheitsprüfung fehlgeschlagen',
          'Die SHA-256-Prüfsumme der APK stimmt nicht. '
              'Das Update wird nicht installiert.',
          event,
        );
        break;

      case OtaStatus.DOWNLOAD_ERROR:
        await _setOtaFailure(
          'Download fehlgeschlagen',
          event.value ?? 'Die APK konnte nicht geladen werden.',
          event,
        );
        break;

      case OtaStatus.INSTALLATION_ERROR:
        await _setOtaFailure(
          'Installation fehlgeschlagen',
          event.value ??
              'Android konnte das Update nicht installieren.',
          event,
        );
        break;

      case OtaStatus.INTERNAL_ERROR:
        await _setOtaFailure(
          'Interner Updatefehler',
          event.value ?? 'Unbekannter Fehler',
          event,
        );
        break;

      case OtaStatus.ALREADY_RUNNING_ERROR:
        setState(() {
          _status = 'Update läuft bereits';
          _details =
              'Der Download wurde bereits gestartet.';
        });
        break;

      case OtaStatus.CANCELED:
        await _setOtaFailure(
          'Update abgebrochen',
          'Der Download wurde abgebrochen.',
          event,
        );
        break;
    }
  }

  Future<void> _setOtaFailure(
    String title,
    String details,
    OtaEvent event,
  ) async {
    await DeveloperErrorLogger.logError(
      StateError('$title: $details'),
      StackTrace.current,
      source: 'AndroidUpdateGate.${event.status.name}',
      severity: 'warning',
      context: {
        'ota_value': event.value,
        'build_number': _release?.buildNumber,
      },
    );

    if (!mounted) return;

    setState(() {
      _downloading = false;
      _failed = true;
      _status = title;
      _details = details;
    });
  }

  bool get _mustBlock {
    return _release?.forceUpdate == true;
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const _UpdateLoadingPage(
        title: 'Suche nach Updates …',
      );
    }

    if (_release == null || _allowAppAfterFailure) {
      return widget.child;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 540,
              ),
              child: Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          color: (_failed ? _red : _blue)
                              .withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _failed
                              ? Icons.error_outline
                              : _installTriggered
                                  ? Icons.system_update_alt
                                  : Icons.downloading_outlined,
                          color: _failed ? _red : _blue,
                          size: 38,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        _mustBlock
                            ? 'Pflichtupdate'
                            : 'App-Update',
                        style: const TextStyle(
                          color: _navy,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Version ${_release!.versionName} '
                        '(Build ${_release!.buildNumber}) · '
                        '${_release!.channelLabel}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF667085),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        _status,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _navy,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (_details != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _details!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF667085),
                            height: 1.35,
                          ),
                        ),
                      ],
                      if (_release!.notes.trim().isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F7FA),
                            borderRadius:
                                BorderRadius.circular(14),
                          ),
                          child: Text(
                            _release!.notes,
                            style: const TextStyle(
                              color: _navy,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      if (_downloading) ...[
                        LinearProgressIndicator(
                          value: _progress > 0
                              ? _progress
                              : null,
                          minHeight: 8,
                          borderRadius:
                              BorderRadius.circular(99),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${(_progress * 100).toStringAsFixed(0)} %',
                          style: const TextStyle(
                            color: _blue,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                      if (_failed) ...[
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () =>
                                _downloadAndInstall(
                              _release!,
                            ),
                            icon: const Icon(Icons.refresh),
                            label: const Text(
                              'Erneut versuchen',
                            ),
                          ),
                        ),
                      ],
                      if (_installTriggered &&
                          !_downloading) ...[
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () =>
                                _downloadAndInstall(
                              _release!,
                            ),
                            icon: const Icon(
                              Icons.system_update_alt,
                            ),
                            label: const Text(
                              'Installation erneut öffnen',
                            ),
                          ),
                        ),
                      ],
                      if (!_mustBlock &&
                          (_failed ||
                              _installTriggered)) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _allowAppAfterFailure = true;
                            });
                          },
                          child: const Text(
                            'App trotzdem öffnen',
                          ),
                        ),
                      ],
                      if (_mustBlock) ...[
                        const SizedBox(height: 12),
                        const Row(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.lock_outline,
                              color: _red,
                              size: 18,
                            ),
                            SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Diese App-Version bleibt bis '
                                'zum Update gesperrt.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _red,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UpdateLoadingPage extends StatelessWidget {
  final String title;

  const _UpdateLoadingPage({
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF0A1F44),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
