import 'package:flutter/material.dart';
import '../data/repository.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import '../services/pdf_service.dart';
import '../services/whatsapp_service.dart';

/// Rappels impayés — liste toutes les factures avec un reste à payer,
/// triées de la plus ancienne à la plus récente, avec un rappel WhatsApp
/// prêt à envoyer en un tap par client. Pendant, côté téléphone, de
/// `modules/relances.py` côté ordinateur.
class RappelsScreen extends StatefulWidget {
  const RappelsScreen({super.key});

  @override
  State<RappelsScreen> createState() => _RappelsScreenState();
}

class _RappelsScreenState extends State<RappelsScreen> {
  final _factureRepo = FactureRepository();
  final _clientRepo = ClientRepository();
  List<Facture> _factures = [];
  List<Client> _clients = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final factures = await _factureRepo.all();
    final clients = await _clientRepo.all();
    if (!mounted) return;
    final impayees = factures.where((f) => f.resteAPayer > 0).toList()..sort((a, b) => a.dateFacture.compareTo(b.dateFacture));
    setState(() {
      _factures = impayees;
      _clients = clients;
      _loading = false;
    });
  }

  Client? _clientFor(int? id) {
    if (id == null) return null;
    for (final c in _clients) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> _rappeler(Facture f) async {
    final client = _clientFor(f.clientId);
    setState(() => _busy = true);
    try {
      final lignes = await _factureRepo.lignes(f.numero);
      final bytes = await PdfService.facturePdf(f, client, lignes);
      if (!mounted) return;
      final telephone = client?.telephone.trim() ?? '';
      if (WhatsappService.numeroValide(telephone)) {
        await showAppBottomSheet(
          context,
          title: 'Rappel WhatsApp',
          child: WhatsappMessageSheet(
            telephone: telephone,
            messageInitial:
                'Bonjour ${client?.nom ?? ''}, petit rappel concernant votre facture ${f.numero} — il reste ${fmtFcfa(f.resteAPayer)} à régler. Merci de votre confiance — MK Entreprise.',
            introTexte: "Un rappel peut accompagner l'envoi de la facture sur WhatsApp",
            onOuvert: () => PdfService.share(bytes, '${f.numero}.pdf'),
          ),
        );
      } else {
        if (!mounted) return;
        showFormError(context, "Ce client n'a pas de numéro de téléphone valide enregistré.");
      }
    } catch (_) {
      if (mounted) showFormError(context, 'Impossible de préparer le rappel pour cette facture.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalDu = _factures.fold<double>(0, (s, f) => s + f.resteAPayer);
    return Scaffold(
      appBar: AppBar(title: const Text('Rappels impayés')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : RefreshIndicator(
              color: AppColors.gold,
              onRefresh: _load,
              child: _factures.isEmpty
                  ? ListView(children: const [EmptyState(icon: Icons.check_circle_outline, text: 'Aucune facture impayée pour le moment.')])
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                        AppCard(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${_factures.length} facture${_factures.length > 1 ? 's' : ''} impayée${_factures.length > 1 ? 's' : ''}',
                                style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600, fontSize: 13.5),
                              ),
                              Text(fmtFcfa(totalDu), style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700, fontSize: 15)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        for (final f in _factures) ...[
                          _RappelCard(facture: f, client: _clientFor(f.clientId), busy: _busy, onRappel: () => _rappeler(f)),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
            ),
    );
  }
}

class _RappelCard extends StatelessWidget {
  final Facture facture;
  final Client? client;
  final bool busy;
  final VoidCallback onRappel;
  const _RappelCard({required this.facture, required this.client, required this.busy, required this.onRappel});

  @override
  Widget build(BuildContext context) {
    final dateParsee = DateTime.tryParse(facture.dateFacture);
    final jours = dateParsee == null ? null : DateTime.now().difference(dateParsee).inDays;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${facture.numero} — ${client?.nom ?? "Client non renseigné"}',
            style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Text(
            jours != null && jours > 0 ? 'Reste : ${fmtFcfa(facture.resteAPayer)} · émise il y a $jours jour(s)' : 'Reste : ${fmtFcfa(facture.resteAPayer)}',
            style: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          WhatsappButton(label: busy ? 'Préparation…' : 'Rappel WhatsApp', onPressed: busy ? () {} : onRappel),
        ],
      ),
    );
  }
}
