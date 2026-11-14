"""
MK Suite - Rappels WhatsApp (factures impayées)
Liste toutes les factures avec un reste à payer, triées de la plus ancienne
à la plus récente, avec un rappel WhatsApp prêt à envoyer en un clic par
client — pendant, côté ordinateur, du module de rappels côté téléphone
(lib/screens/rappels_screen.dart).
"""
import os
import tempfile
from datetime import datetime
import customtkinter as ctk
from ui.theme import COLORS, font, title_font, card, primary_button, secondary_button
from ui.widgets import section_title
from modules.pdf_generator import generate_facture_pdf
from modules.whatsapp_service import ouvrir_dialogue_message, reveler_dans_explorateur


class RelancesView(ctk.CTkScrollableFrame):
    def __init__(self, parent, db, app=None, **kwargs):
        super().__init__(parent, fg_color="transparent", **kwargs)
        self.db = db
        self.app = app
        self.build()

    def build(self):
        header = ctk.CTkFrame(self, fg_color="transparent")
        header.pack(fill="x", padx=4, pady=(4, 8))
        section_title(header, "Rappels impayés",
                      "Factures avec un solde restant — relance WhatsApp en un clic").pack(side="left")
        self.total_lbl = ctk.CTkLabel(header, text="", font=font(12, "bold"), text_color=COLORS["gold"])
        self.total_lbl.pack(side="right")

        info_card = ctk.CTkFrame(self, fg_color=COLORS["bg_input"], corner_radius=10)
        info_card.pack(fill="x", padx=4, pady=(0, 16))
        ctk.CTkLabel(
            info_card,
            text="ℹ️ Toutes les factures avec un reste à payer, des plus anciennes aux plus récentes. "
                 "Le bouton WhatsApp prépare un message de rappel personnalisé et révèle la facture en "
                 "PDF dans l'explorateur, prête à joindre à la conversation.",
            font=font(11), text_color=COLORS["text_secondary"], wraplength=900, justify="left",
        ).pack(anchor="w", padx=16, pady=10)

        self.list_frame = ctk.CTkFrame(self, fg_color="transparent")
        self.list_frame.pack(fill="both", expand=True, padx=4)
        self.refresh()

    def refresh(self):
        for w in self.list_frame.winfo_children():
            w.destroy()

        rows = self.db.fetchall(
            "SELECT f.*, c.nom AS client_nom, c.telephone AS client_tel FROM factures f "
            "LEFT JOIN clients c ON c.id = f.client_id "
            "WHERE f.reste_a_payer > 0 ORDER BY f.date_facture ASC"
        )

        total_du = sum((r["reste_a_payer"] or 0) for r in rows)
        total_txt = f"{total_du:,.0f}".replace(",", " ")
        self.total_lbl.configure(text=f"{len(rows)} facture(s) · {total_txt} FCFA dus")

        if not rows:
            empty = ctk.CTkFrame(self.list_frame, fg_color="transparent")
            empty.pack(fill="both", expand=True, pady=80)
            ctk.CTkLabel(empty, text="✅", font=font(40)).pack()
            ctk.CTkLabel(empty, text="Aucune facture impayée pour le moment", font=font(14, "bold"),
                         text_color=COLORS["text_secondary"]).pack(pady=(8, 0))
            return

        for r in rows:
            self._build_row(r)

    def _build_row(self, r):
        row = card(self.list_frame, fg_color=COLORS["bg_card"])
        row.pack(fill="x", pady=4)
        inner = ctk.CTkFrame(row, fg_color="transparent")
        inner.pack(fill="x", padx=18, pady=12)

        txt = ctk.CTkFrame(inner, fg_color="transparent")
        txt.pack(side="left", fill="x", expand=True)
        nom = r["client_nom"] or "Client non renseigné"
        ctk.CTkLabel(txt, text=f"{r['numero']} — {nom}", font=font(13, "bold"),
                     text_color=COLORS["text_primary"], anchor="w").pack(anchor="w")

        retard_txt = ""
        try:
            date_f = datetime.fromisoformat(r["date_facture"])
            jours = (datetime.now() - date_f).days
            if jours > 0:
                retard_txt = f" · émise il y a {jours} jour(s)"
        except Exception:
            pass
        reste_txt = f"{(r['reste_a_payer'] or 0):,.0f}".replace(",", " ")
        ttc_txt = f"{(r['montant_ttc'] or 0):,.0f}".replace(",", " ")
        ctk.CTkLabel(txt, text=f"Reste à payer : {reste_txt} FCFA / {ttc_txt} FCFA{retard_txt}",
                     font=font(11), text_color=COLORS["danger"], anchor="w").pack(anchor="w")

        btns = ctk.CTkFrame(inner, fg_color="transparent")
        btns.pack(side="right")
        secondary_button(btns, "👁️ Voir", height=34, width=90,
                          command=lambda rr=r: self._voir_facture(rr)).pack(side="left", padx=4)
        primary_button(
            btns, "💬 Rappel WhatsApp", height=34, width=170,
            fg_color="#25D366", hover_color="#1FAE56", text_color="white",
            command=lambda rr=r: self._rappel(rr),
        ).pack(side="left", padx=4)

    def _voir_facture(self, r):
        if self.app:
            self.app.show_page("devis", initial_mode="factures", focus_numero=r["numero"])

    def _rappel(self, facture_row):
        client_row = None
        if facture_row["client_id"]:
            client_row = self.db.fetchone("SELECT * FROM clients WHERE id=?", (facture_row["client_id"],))
        lignes = self.db.fetchall(
            "SELECT * FROM lignes_facture WHERE facture_numero=?", (facture_row["numero"],))
        path = os.path.join(tempfile.gettempdir(), f"{facture_row['numero']}.pdf")
        generate_facture_pdf(path, facture_row, client_row, lignes)

        nom = client_row["nom"] if client_row else ""
        reste_txt = f"{(facture_row['reste_a_payer'] or 0):,.0f}".replace(",", " ")
        message = (f"Bonjour {nom}, petit rappel concernant votre facture {facture_row['numero']} — "
                   f"il reste {reste_txt} FCFA à régler. Merci de votre confiance — MK Entreprise.")
        telephone = client_row["telephone"] if client_row else ""
        ouvrir_dialogue_message(self, telephone, message, lambda: reveler_dans_explorateur(path))
