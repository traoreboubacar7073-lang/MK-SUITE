import 'package:url_launcher/url_launcher.dart';

/// Ouvre WhatsApp directement sur la conversation d'un numéro donné, avec
/// un message déjà rédigé — l'utilisateur n'a plus qu'à appuyer sur
/// "Envoyer". WhatsApp n'autorise aucune application tierce à envoyer un
/// message — et encore moins une pièce jointe — sans confirmation de la
/// personne (protection anti-spam) : ce dernier geste reste donc toujours
/// manuel, volontairement.
///
/// Pour l'envoi d'un document (devis/facture/reçu) en PDF, voir la méthode
/// `_sendWhatsapp` de chaque écran de détail (devis_detail_screen.dart,
/// facture_detail_screen.dart, recu_form_sheet.dart) : le principe est
/// d'ouvrir d'abord cette conversation avec un message d'accompagnement
/// (voir `WhatsappMessageSheet` dans widgets/shared_widgets.dart), puis
/// d'enchaîner sur le sélecteur de partage natif du téléphone pour le PDF
/// lui-même — c'est le geste le plus proche d'un "envoi direct" que
/// WhatsApp autorise pour une app tierce, qui ne peut jamais joindre un
/// fichier toute seule.
class WhatsappService {
  WhatsappService._();

  /// Ne garde que les chiffres du numéro (retire le "+", les espaces,
  /// tirets...), format attendu par le lien wa.me.
  static String _nettoyerNumero(String numero) {
    return numero.replaceAll(RegExp(r'[^0-9]'), '');
  }

  static bool numeroValide(String numero) => _nettoyerNumero(numero).length >= 8;

  static Future<bool> ouvrirConversation({required String numero, required String message}) async {
    final numeroPropre = _nettoyerNumero(numero);
    if (numeroPropre.isEmpty) return false;
    final uri = Uri.parse('https://wa.me/$numeroPropre?text=${Uri.encodeComponent(message)}');
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
