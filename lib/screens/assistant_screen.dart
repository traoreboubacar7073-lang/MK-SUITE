import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repository.dart';
import '../models/models.dart';
import '../services/assistant_service.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});
  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  String _bilan = '';
  String? _error;
  bool _loading = true;
  List<Facture> _dues = [];
  Map<int, String> _clients = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final factures = await FactureRepository().all();
      final depenses = await DepenseRepository().all();
      final clients = await ClientRepository().all();
      if (!mounted) return;
      setState(() {
        _bilan = AssistantService.bilan(factures, depenses, DateTime.now());
        _dues = factures.where((f) => f.resteAPayer > 0).toList()
          ..sort((a, b) => b.resteAPayer.compareTo(a.resteAPayer));
        _clients = {for (final c in clients) c.id: c.nom};
      });
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Impossible de lire les données. Réessayez.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showRelance(Facture f) async {
    final texte = AssistantService.relance(
      f,
      _clients[f.clientId] ?? 'cher client',
    );
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Relance ${f.numero}'),
        content: SingleChildScrollView(child: SelectableText(texte)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'),
          ),
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: texte));
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (mounted)
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Relance copiée. Vérifiez-la avant envoi.'),
                  ),
                );
            },
            child: const Text('Copier'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Assistant MK'),
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          tooltip: 'Actualiser',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Assistance hors ligne',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Bilan automatique et modèles de relance. Aucune donnée envoyée sur internet. Cet assistant utilise des règles, pas une IA conversationnelle.',
              ),
              const SizedBox(height: 20),
              if (_error != null) ...[
                Text(_error!),
                TextButton(onPressed: _load, child: const Text('Réessayer')),
              ] else ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(_bilan),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Préparer une relance',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Text(
                  'Les factures sont classées par solde, sans présumer de leur échéance.',
                ),
                for (final f in _dues)
                  ListTile(
                    title: Text(f.numero),
                    subtitle: Text(
                      '${_clients[f.clientId] ?? "Client non renseigné"} · ${f.resteAPayer.toStringAsFixed(0)} FCFA',
                    ),
                    trailing: const Icon(Icons.edit_note),
                    onTap: () => _showRelance(f),
                  ),
              ],
            ],
          ),
  );
}
