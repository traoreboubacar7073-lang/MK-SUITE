"""
MK Suite - Module Corbeille
Tout élément supprimé (client, devis, facture, dépense, etc.) atterrit ici pendant
30 jours avant d'être définitivement effacé — le temps de se rattraper en cas d'erreur.
"""
import customtkinter as ctk
from datetime import datetime, timedelta
from ui.theme import COLORS, font, title_font, card, primary_button, secondary_button, danger_button
from ui.widgets import section_title, confirm_delete

MODULE_ICONS = {
    "Clients": "👥", "Devis & Factures": "📋", "Sourcing": "🚚", "Dépenses": "💳",
    "Calcul Vitres": "📐", "Fournisseurs": "🏭", "Employés & Paie": "👔",
}


class CorbeilleView(ctk.CTkScrollableFrame):
    def __init__(self, parent, db, **kwargs):
        super().__init__(parent, fg_color="transparent", **kwargs)
        self.db = db
        self.build()

    def build(self):
        header = ctk.CTkFrame(self, fg_color="transparent")
        header.pack(fill="x", padx=4, pady=(4, 8))
        section_title(header, "Corbeille",
                      "Éléments supprimés — restaurables pendant 30 jours").pack(side="left")

        info_card = ctk.CTkFrame(self, fg_color=COLORS["bg_input"], corner_radius=10)
        info_card.pack(fill="x", padx=4, pady=(0, 16))
        ctk.CTkLabel(info_card, text="ℹ️ Tout élément supprimé reste ici 30 jours avant d'être "
                                       "effacé pour de bon. Tu peux le restaurer à tout moment.",
                     font=font(11), text_color=COLORS["text_secondary"], wraplength=900,
                     justify="left").pack(anchor="w", padx=16, pady=10)

        self.list_frame = ctk.CTkFrame(self, fg_color="transparent")
        self.list_frame.pack(fill="both", expand=True, padx=4)
        self.refresh()

    def refresh(self):
        for w in self.list_frame.winfo_children():
            w.destroy()

        items = self.db.get_corbeille()
        if not items:
            empty = ctk.CTkFrame(self.list_frame, fg_color="transparent")
            empty.pack(fill="both", expand=True, pady=80)
            ctk.CTkLabel(empty, text="🗑️", font=font(40)).pack()
            ctk.CTkLabel(empty, text="La corbeille est vide", font=font(14, "bold"),
                         text_color=COLORS["text_secondary"]).pack(pady=(8, 0))
            return

        for item in items:
            self._build_row(item)

    def _build_row(self, item):
        deleted_at = datetime.fromisoformat(item["date_suppression"])
        jours_restants = 30 - (datetime.now() - deleted_at).days
        jours_restants = max(jours_restants, 0)
        urgent = jours_restants <= 5

        row = card(self.list_frame, fg_color=COLORS["bg_card"])
        row.pack(fill="x", pady=4)
        inner = ctk.CTkFrame(row, fg_color="transparent")
        inner.pack(fill="x", padx=18, pady=12)

        icon = MODULE_ICONS.get(item["module"], "🗑")
        ctk.CTkLabel(inner, text=icon, font=font(20)).pack(side="left", padx=(0, 14))

        txt = ctk.CTkFrame(inner, fg_color="transparent")
        txt.pack(side="left", fill="x", expand=True)
        ctk.CTkLabel(txt, text=item["libelle"] or "Élément sans nom", font=font(13, "bold"),
                     text_color=COLORS["text_primary"], anchor="w").pack(anchor="w")
        ctk.CTkLabel(txt, text=f"{item['module']} · supprimé le {deleted_at.strftime('%d/%m/%Y à %H:%M')}",
                     font=font(10), text_color=COLORS["text_secondary"], anchor="w").pack(anchor="w")

        delai_color = COLORS["danger"] if urgent else COLORS["text_muted"]
        delai_txt = "sera effacé aujourd'hui" if jours_restants == 0 else \
            f"effacement définitif dans {jours_restants} jour(s)"
        ctk.CTkLabel(txt, text=delai_txt, font=font(10, "bold"), text_color=delai_color,
                     anchor="w").pack(anchor="w", pady=(2, 0))

        btns = ctk.CTkFrame(inner, fg_color="transparent")
        btns.pack(side="right")
        secondary_button(btns, "↩️ Restaurer", height=34, width=120,
                          command=lambda i=item: self._restore(i)).pack(side="left", padx=4)
        danger_button(btns, "Supprimer définitivement", height=34,
                      command=lambda i=item: self._delete_forever(i)).pack(side="left", padx=4)

    def _restore(self, item):
        self.db.restore_from_corbeille(item["id"])
        self.refresh()

    def _delete_forever(self, item):
        confirm_delete(
            self, "Supprimer définitivement ?",
            f"« {item['libelle']} » sera effacé pour toujours, sans possibilité de récupération.",
            lambda: self._confirm_delete_forever(item["id"]))

    def _confirm_delete_forever(self, corbeille_id):
        self.db.delete_from_corbeille(corbeille_id)
        self.refresh()
