import 'package:flutter/material.dart';
import '../data/database.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

/// Écran de synchronisation locale Wi-Fi — voir sync_service.dart pour le
/// détail du protocole. Les deux appareils (téléphone ↔ ordinateur)
/// doivent être sur le même réseau Wi-Fi ; PEU IMPORTE lequel "démarre le
/// serveur" et lequel "se connecte" — le résultat final est le même des
/// deux côtés (toutes les données fusionnées).
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _server = SyncServer();
  final _ipController = TextEditingController();
  String? _localAddress;
  bool _loadingAddress = true;
  bool _syncing = false;
  bool _checkingReach = false;
  bool? _reachable;
  SyncLog? _lastLog;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _refreshAddress();
  }

  Future<void> _refreshAddress() async {
    setState(() => _loadingAddress = true);
    final addr = await SyncServer.localAddress();
    if (!mounted) return;
    setState(() {
      _localAddress = addr;
      _loadingAddress = false;
    });
  }

  Future<void> _toggleServer() async {
    if (_server.isRunning) {
      await _server.stop();
      if (!mounted) return;
      setState(() {});
      return;
    }
    final db = await AppDatabase.instance.database;
    final addr = await _server.start(db);
    if (!mounted) return;
    setState(() => _localAddress = addr ?? _localAddress);
    if (addr == null) {
      showFormError(context, "Impossible de démarrer le serveur — le port $syncPort est peut-être déjà utilisé par une autre application.");
    }
  }

  Future<void> _checkReachable() async {
    final host = _ipController.text.trim();
    if (host.isEmpty) return;
    setState(() {
      _checkingReach = true;
      _reachable = null;
    });
    final ok = await SyncClient.canReach(host);
    if (!mounted) return;
    setState(() {
      _checkingReach = false;
      _reachable = ok;
    });
  }

  Future<void> _synchroniser() async {
    final host = _ipController.text.trim();
    if (host.isEmpty) {
      showFormError(context, "Indique l'adresse IP de l'autre appareil.");
      return;
    }
    setState(() {
      _syncing = true;
      _lastLog = null;
      _lastError = null;
    });
    try {
      final db = await AppDatabase.instance.database;
      final log = await SyncClient.syncWith(db, host);
      if (!mounted) return;
      setState(() => _lastLog = log);
      showFormSuccess(context, 'Synchronisation terminée : ${log.inserted} ajout(s), ${log.updated} mise(s) à jour.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _lastError = "Échec de la synchronisation : vérifie que les deux appareils sont sur le même Wi-Fi et que l'autre appareil a démarré son serveur.\n\n($e)");
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  void dispose() {
    _server.stop();
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Synchronisation')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: [
          Text(
            'Aucun serveur internet : les deux appareils échangent directement leurs données quand ils sont sur le MÊME réseau Wi-Fi. '
            'Rien n\'est jamais perdu — chaque appareil garde toutes ses lignes, et la plus récente modification l\'emporte en cas de conflit.',
            style: TextStyle(color: context.textMuted, fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 20),

          // --- Bloc "recevoir" -------------------------------------------------
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconBadge(icon: Icons.wifi_tethering, color: AppColors.info, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Recevoir une synchronisation', style: TextStyle(color: context.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text('L\'autre appareil se connecte à toi', style: TextStyle(color: context.textFaint, fontSize: 11.5)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                  decoration: BoxDecoration(color: AppColors.surfaceHover, borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    children: [
                      Icon(Icons.language, size: 16, color: context.textFaint),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _loadingAddress
                            ? Text('Recherche de l\'adresse Wi-Fi…', style: TextStyle(color: context.textFaint, fontSize: 13))
                            : Text(
                                _localAddress == null ? 'Adresse introuvable — vérifie que le Wi-Fi est activé.' : '${_localAddress!} : $syncPort',
                                style: TextStyle(color: context.textPrimary, fontSize: 14, fontWeight: FontWeight.w700, fontFamily: 'monospace'),
                              ),
                      ),
                      IconButton(icon: Icon(Icons.refresh, size: 18, color: context.textFaint), onPressed: _refreshAddress, tooltip: 'Actualiser'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                GoldButton(
                  label: _server.isRunning ? 'Arrêter le serveur' : 'Démarrer le serveur',
                  icon: _server.isRunning ? Icons.stop_circle_outlined : Icons.play_circle_outline,
                  onPressed: _toggleServer,
                ),
                if (_server.isRunning) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text('En attente d\'une connexion…', style: TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // --- Bloc "se connecter" ---------------------------------------------
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconBadge(icon: Icons.sync, color: AppColors.gold, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Se connecter à un autre appareil', style: TextStyle(color: context.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text('Saisis l\'adresse affichée sur l\'autre appareil', style: TextStyle(color: context.textFaint, fontSize: 11.5)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _ipController,
                  keyboardType: TextInputType.numbersPunctuation,
                  style: TextStyle(color: context.textPrimary, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    hintText: 'ex : 192.168.1.24',
                    suffixIcon: _checkingReach
                        ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                        : (_reachable == null
                            ? null
                            : Icon(_reachable! ? Icons.check_circle : Icons.error_outline, color: _reachable! ? AppColors.success : AppColors.danger)),
                  ),
                  onChanged: (_) => setState(() => _reachable = null),
                  onSubmitted: (_) => _checkReachable(),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: GhostButton(label: _checkingReach ? 'Vérification…' : 'Vérifier', onPressed: _checkingReach ? () {} : _checkReachable),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GoldButton(
                        label: _syncing ? 'Synchronisation…' : 'Synchroniser',
                        icon: Icons.sync,
                        onPressed: _syncing ? () {} : _synchroniser,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (_syncing) ...[
            const SizedBox(height: 20),
            const Center(child: CircularProgressIndicator(color: AppColors.gold)),
          ],

          if (_lastError != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.danger.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.danger.withOpacity(0.3))),
              child: Text(_lastError!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5, height: 1.4)),
            ),
          ],

          if (_lastLog != null) ...[
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: AppColors.success, size: 18),
                      const SizedBox(width: 8),
                      Text('Résultat de la synchronisation', style: TextStyle(color: context.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text('${_lastLog!.inserted} ligne(s) ajoutée(s) · ${_lastLog!.updated} ligne(s) mise(s) à jour ici.',
                      style: TextStyle(color: context.textMuted, fontSize: 12.5)),
                  if (_lastLog!.lines.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Divider(color: AppColors.border, height: 1),
                    const SizedBox(height: 10),
                    for (final line in _lastLog!.lines)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('• $line', style: TextStyle(color: context.textFaint, fontSize: 11.5, height: 1.3)),
                      ),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),
          Text(
            'À savoir : si un fournisseur ou un tarif de vitre a été créé indépendamment sur les deux appareils avant la toute première synchronisation, '
            'ils fusionneront automatiquement en une seule fiche dès ce premier échange. Une suppression faite sur un appareil se répercute sur l\'autre '
            'au prochain échange (l\'élément reste 30 jours dans la Corbeille des deux côtés).',
            style: TextStyle(color: context.textFaint, fontSize: 11, height: 1.4),
          ),
        ],
      ),
    );
  }
}
