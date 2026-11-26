"""
MK Suite - Envoi par WhatsApp (ordinateur)
Pendant, côté ordinateur, de lib/services/whatsapp_service.dart côté
téléphone : ouvre une conversation WhatsApp avec un message déjà rédigé, via
le lien https://wa.me/... (WhatsApp Desktop, s'il est installé, s'enregistre
généralement comme gestionnaire de ces liens ; sinon ça ouvre WhatsApp Web
dans le navigateur par défaut).

LIMITE IMPORTANTE, la même que côté téléphone : WhatsApp n'offre aucun moyen,
pour une application tierce, de joindre automatiquement un fichier à une
conversation — ce serait une porte ouverte au spam. Sur téléphone, on
contourne ça avec le sélecteur de partage natif (qui, lui, sait déposer un
fichier dans WhatsApp). Sur ordinateur, il n'existe pas d'équivalent
générique : la meilleure approche possible est donc d'ouvrir la conversation
ET de révéler le PDF déjà généré dans l'explorateur de fichiers, prêt à être
glissé-déposé dans la fenêtre WhatsApp qui vient de s'ouvrir — ce qui reste
nettement plus rapide que de partir de zéro (retrouver le contact, régénérer
le PDF, chercher où l'enregistrer).
"""
import os
import re
import sys
import subprocess
import webbrowser
import urllib.parse


def numero_valide(numero):
    """Au moins 8 chiffres une fois les espaces/tirets/+ retirés — même règle
    que numeroValide() côté téléphone."""
    chiffres = re.sub(r"[^0-9]", "", numero or "")
    return len(chiffres) >= 8


def ouvrir_conversation(numero, message):
    """Ouvre la conversation WhatsApp du numéro donné, message déjà rédigé
    (modifiable par l'utilisateur avant l'envoi — WhatsApp ne permet jamais
    l'envoi automatique). Retourne False si le numéro est invalide."""
    chiffres = re.sub(r"[^0-9]", "", numero or "")
    if not chiffres:
        return False
    url = f"https://wa.me/{chiffres}?text={urllib.parse.quote(message)}"
    webbrowser.open(url)
    return True


def reveler_dans_explorateur(path):
    """Ouvre l'explorateur de fichiers avec le PDF déjà sélectionné (Windows/
    macOS) — ou, à défaut (Linux), ouvre simplement son dossier — pour que le
    glisser-déposer vers WhatsApp soit aussi direct que possible."""
    try:
        if sys.platform.startswith("win"):
            subprocess.run(["explorer", "/select,", os.path.normpath(path)])
        elif sys.platform == "darwin":
            subprocess.run(["open", "-R", path])
        else:
            subprocess.run(["xdg-open", os.path.dirname(path)])
    except Exception:
        pass


def ouvrir_dialogue_message(parent, telephone, message_defaut, on_reveal_pdf):
    """Fenêtre d'envoi WhatsApp réutilisable — message pré-rédigé (modifiable),
    puis ouverture de la conversation ET du PDF déjà généré dans l'explorateur
    de fichiers (l'ordinateur n'a pas de sélecteur de partage natif capable de
    joindre le fichier tout seul, contrairement au téléphone — voir la note en
    tête de ce fichier).

    Extrait de `modules/devis_factures.py` (méthode `_whatsapp_message_dialog`
    d'origine) pour être partagé avec `modules/relances.py` (rappels de
    factures impayées) sans dupliquer cette fenêtre — les deux appellent
    maintenant cette même fonction, `parent` étant simplement le widget
    CTkFrame/CTkScrollableFrame qui ouvre la fenêtre (utilisé comme maître du
    CTkToplevel)."""
    import customtkinter as ctk
    from ui.theme import COLORS, font, primary_button, secondary_button

    telephone = (telephone or "").strip()
    valide = numero_valide(telephone)

    dialog = ctk.CTkToplevel(parent)
    dialog.title("Message WhatsApp")
    dialog.geometry("440x380")
    dialog.configure(fg_color=COLORS["bg_dark"])
    dialog.transient(parent)
    dialog.grab_set()
    dialog.bind("<Escape>", lambda e: dialog.destroy())

    ctk.CTkLabel(dialog, text="💬 Envoyer par WhatsApp", font=font(15, "bold"),
                 text_color=COLORS["text_primary"]).pack(pady=(20, 4))
    if valide:
        intro = f"Un message peut accompagner l'envoi du PDF sur WhatsApp ({telephone})."
    else:
        intro = ("Ce client n'a pas de numéro de téléphone valide enregistré — le PDF sera "
                  "quand même révélé dans l'explorateur pour un envoi manuel.")
    ctk.CTkLabel(dialog, text=intro, font=font(11), text_color=COLORS["text_secondary"],
                 wraplength=380, justify="left").pack(padx=28, pady=(0, 12))

    msg_box = ctk.CTkTextbox(dialog, height=120, fg_color=COLORS["bg_input"],
                              text_color=COLORS["text_primary"], font=font(12))
    if valide:
        msg_box.insert("1.0", message_defaut)
    msg_box.configure(state="normal" if valide else "disabled")
    msg_box.pack(fill="x", padx=28, pady=(0, 16))

    def confirmer():
        if valide:
            ouvrir_conversation(telephone, msg_box.get("1.0", "end").strip())
        dialog.destroy()
        on_reveal_pdf()

    label_btn = "Ouvrir WhatsApp, puis joindre le PDF" if valide else "Voir le PDF dans l'explorateur"
    primary_button(dialog, label_btn, command=confirmer).pack(fill="x", padx=28, pady=(0, 8))
    secondary_button(dialog, "Ne pas envoyer maintenant", command=dialog.destroy).pack(
        fill="x", padx=28, pady=(0, 20))
