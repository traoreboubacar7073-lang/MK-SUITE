"""
MK Suite - Module Fournisseurs
Le total des achats est calculé automatiquement à partir du registre Dépenses,
exactement comme dans le classeur Excel. Liste + panneau de détail (rapide même
avec de nombreux fournisseurs) plutôt que des cartes individuelles.
"""
import customtkinter as ctk
from ui.theme import COLORS, font, title_font, card, primary_button, secondary_button, danger_button
from ui.widgets import section_title, confirm_delete, show_context_menu


class FournisseursView(ctk.CTkFrame):
    def __init__(self, parent, db, **kwargs):
        super().__init__(parent, fg_color="transparent", **kwargs)
        self.db = db
        self.build()
        self.refresh_list()

    def build(self):
        header = ctk.CTkFrame(self, fg_color="transparent")
        header.pack(fill="x", padx=4, pady=(4, 16))
        section_title(header, "Fournisseurs", "Total des achats calculé depuis le registre des dépenses").pack(
            side="left")
        primary_button(header, "+ Nouveau fournisseur", command=self.open_form).pack(side="right")

        body = ctk.CTkFrame(self, fg_color="transparent")
        body.pack(fill="both", expand=True, padx=4)
        body.grid_columnconfigure(0, weight=1)
        body.grid_columnconfigure(1, weight=0)
        body.grid_rowconfigure(0, weight=1)

        self.list_frame = ctk.CTkScrollableFrame(body, fg_color="transparent")
        self.list_frame.grid(row=0, column=0, sticky="nsew", padx=(0, 8))

        self.detail_panel = ctk.CTkScrollableFrame(body, width=340, fg_color=COLORS["bg_card"],
                                                     corner_radius=14, border_width=1,
                                                     border_color=COLORS["border"])
        self.detail_panel.grid(row=0, column=1, sticky="nsew")
        self._show_empty_detail()

    def _show_empty_detail(self):
        for w in self.detail_panel.winfo_children():
            w.destroy()
        ctk.CTkLabel(self.detail_panel, text="🏭", font=font(40)).pack(pady=(60, 10))
        ctk.CTkLabel(self.detail_panel, text="Sélectionne un fournisseur\npour voir le détail",
                     font=font(13), text_color=COLORS["text_secondary"], justify="center").pack()

    def refresh_list(self):
        for w in self.list_frame.winfo_children():
            w.destroy()

        rows = self.db.fetchall("SELECT * FROM fournisseurs ORDER BY nom")
        if not rows:
            ctk.CTkLabel(self.list_frame, text="Aucun fournisseur enregistré.",
                         font=font(12), text_color=COLORS["text_muted"]).pack(pady=40)
            return

        # Une seule requête groupée, quasi instantanée même avec des milliers de dépenses
        totals = {r["beneficiaire"]: r["t"] for r in self.db.fetchall(
            "SELECT beneficiaire, COALESCE(SUM(montant),0) as t FROM depenses "
            "WHERE beneficiaire IS NOT NULL GROUP BY beneficiaire")}

        header_row = ctk.CTkFrame(self.list_frame, fg_color=COLORS["bg_sidebar"], corner_radius=8, height=36)
        header_row.pack(fill="x", pady=(0, 4))
        for txt, w in [("NOM", 220), ("CATÉGORIE", 220), ("TÉLÉPHONE", 140)]:
            ctk.CTkLabel(header_row, text=txt, font=font(10, "bold"), text_color=COLORS["gold"],
                         width=w, anchor="w").pack(side="left", padx=8)
        ctk.CTkLabel(header_row, text="TOTAL ACHATS", font=font(10, "bold"), text_color=COLORS["gold"],
                     anchor="e").pack(side="right", padx=16)

        for i, r in enumerate(rows):
            total_val = totals.get(r["nom"], 0)
            bg = COLORS["bg_card"] if i % 2 == 0 else COLORS["bg_dark"]
            row = ctk.CTkFrame(self.list_frame, fg_color=bg, corner_radius=8, height=44)
            row.pack(fill="x", pady=2)
            row.pack_propagate(False)
            ctk.CTkLabel(row, text=r["nom"], font=font(12, "bold"), text_color=COLORS["text_primary"],
                         width=220, anchor="w").pack(side="left", padx=8)
            ctk.CTkLabel(row, text=r["categorie_produits"] or "—", font=font(11),
                         text_color=COLORS["text_secondary"], width=220, anchor="w").pack(side="left", padx=8)
            ctk.CTkLabel(row, text=r["telephone"] or "—", font=font(11),
                         text_color=COLORS["text_secondary"], width=140, anchor="w").pack(side="left", padx=8)
            ctk.CTkLabel(row, text=f"{total_val:,.0f} FCFA".replace(",", " "), font=font(12, "bold"),
                         text_color=COLORS["gold"], anchor="e").pack(side="right", padx=16)

            for w in row.winfo_children():
                w.bind("<Button-1>", lambda e, rid=r["id"]: self.show_detail(rid))
            row.bind("<Button-1>", lambda e, rid=r["id"]: self.show_detail(rid))
            row.bind("<Enter>", lambda e, w=row: w.configure(fg_color=COLORS["bg_card_hover"]))
            row.bind("<Leave>", lambda e, w=row, b=bg: w.configure(fg_color=b))

            def on_right_click(event, row_data=r):
                items = [
                    ("👁 Voir le détail", lambda: self.show_detail(row_data["id"])),
                    ("✏️ Modifier", lambda: self.open_form(row_data)),
                    (None, None),
                    ("🗑 Supprimer", lambda: self._delete(row_data)),
                ]
                show_context_menu(row, event, items)

            for w in [row] + row.winfo_children():
                w.bind("<Button-3>", on_right_click)

    def show_detail(self, fournisseur_id):
        r = self.db.fetchone("SELECT * FROM fournisseurs WHERE id=?", (fournisseur_id,))
        if not r:
            return
        total = self.db.fetchone(
            "SELECT COALESCE(SUM(montant),0) as t, COUNT(*) as c FROM depenses WHERE beneficiaire=?",
            (r["nom"],))

        for w in self.detail_panel.winfo_children():
            w.destroy()

        head = ctk.CTkFrame(self.detail_panel, fg_color="transparent")
        head.pack(fill="x", padx=24, pady=(28, 12))
        ctk.CTkLabel(head, text=r["nom"], font=font(16, "bold"),
                     text_color=COLORS["text_primary"], wraplength=280).pack(anchor="w")
        ctk.CTkLabel(head, text=r["categorie_produits"] or "Catégorie non renseignée", font=font(12),
                     text_color=COLORS["gold"]).pack(anchor="w", pady=(2, 0))

        info_card = ctk.CTkFrame(self.detail_panel, fg_color=COLORS["bg_input"], corner_radius=10)
        info_card.pack(fill="x", padx=24, pady=8)
        for label, val in [("📞 Téléphone", r["telephone"] or "—"), ("📍 Adresse", r["adresse"] or "—")]:
            row = ctk.CTkFrame(info_card, fg_color="transparent")
            row.pack(fill="x", padx=12, pady=6)
            ctk.CTkLabel(row, text=label, font=font(11), text_color=COLORS["text_secondary"],
                         anchor="w").pack(anchor="w")
            ctk.CTkLabel(row, text=val, font=font(12, "bold"), text_color=COLORS["text_primary"],
                         anchor="w", wraplength=270).pack(anchor="w")
        ctk.CTkFrame(info_card, fg_color="transparent", height=6).pack()

        total_card = ctk.CTkFrame(self.detail_panel, fg_color=COLORS["gold"], corner_radius=10)
        total_card.pack(fill="x", padx=24, pady=8)
        ctk.CTkLabel(total_card, text="TOTAL ACHATS", font=font(10, "bold"), text_color="#0B1220").pack(
            pady=(10, 0))
        ctk.CTkLabel(total_card, text=f"{total['t']:,.0f} FCFA".replace(",", " "),
                     font=font(16, "bold"), text_color="#0B1220").pack()
        ctk.CTkLabel(total_card, text=f"{total['c']} dépense(s) enregistrée(s)", font=font(10),
                     text_color="#0B1220").pack(pady=(0, 10))

        btn_row = ctk.CTkFrame(self.detail_panel, fg_color="transparent")
        btn_row.pack(fill="x", padx=24, pady=(16, 20))
        secondary_button(btn_row, "✏️ Modifier", command=lambda: self.open_form(r)).pack(fill="x", pady=2)
        danger_button(btn_row, "Supprimer", command=lambda: self._delete(r)).pack(fill="x", pady=2)

    def _delete(self, row):
        def do_delete():
            self.db.move_to_corbeille("fournisseurs", row["id"], f"Fournisseur {row['nom']}", "Fournisseurs")
            self.refresh_list()
            self._show_empty_detail()

        confirm_delete(self, f"Supprimer « {row['nom']} » ?",
                        "Il restera 30 jours dans la Corbeille, restaurable si besoin. "
                        "L'historique de ses dépenses passées reste intact.", do_delete)

    def open_form(self, existing=None):
        dialog = ctk.CTkToplevel(self)
        dialog.title("Fournisseur")
        dialog.geometry("400x480")
        dialog.configure(fg_color=COLORS["bg_dark"])
        dialog.transient(self)
        dialog.grab_set()
        dialog.bind("<Escape>", lambda e: dialog.destroy())

        scroll = ctk.CTkScrollableFrame(dialog, fg_color="transparent")
        scroll.pack(fill="both", expand=True)

        ctk.CTkLabel(scroll, text="Modifier le fournisseur" if existing else "Nouveau fournisseur",
                     font=font(16, "bold"), text_color=COLORS["text_primary"]).pack(pady=(24, 16))

        fields = {}

        def add_field(label, key, value=""):
            ctk.CTkLabel(scroll, text=label, font=font(12), text_color=COLORS["text_secondary"],
                         anchor="w").pack(fill="x", padx=32, pady=(8, 2))
            entry = ctk.CTkEntry(scroll, height=40, corner_radius=8, fg_color=COLORS["bg_input"],
                                  border_color=COLORS["border"], font=font(13))
            entry.insert(0, value or "")
            entry.pack(fill="x", padx=32)
            fields[key] = entry

        add_field("Nom du fournisseur *", "nom", existing["nom"] if existing else "")
        add_field("Catégorie de produits", "categorie", existing["categorie_produits"] if existing else "")
        add_field("Téléphone", "telephone", existing["telephone"] if existing else "")
        add_field("Adresse", "adresse", existing["adresse"] if existing else "")

        def save():
            nom = fields["nom"].get().strip()
            if not nom:
                fields["nom"].configure(border_color=COLORS["danger"])
                return
            if existing:
                self.db.execute(
                    "UPDATE fournisseurs SET nom=?, categorie_produits=?, telephone=?, adresse=? WHERE id=?",
                    (nom, fields["categorie"].get(), fields["telephone"].get(), fields["adresse"].get(),
                     existing["id"]))
            else:
                self.db.execute(
                    "INSERT INTO fournisseurs (nom, categorie_produits, telephone, adresse) VALUES (?,?,?,?)",
                    (nom, fields["categorie"].get(), fields["telephone"].get(), fields["adresse"].get()))
            dialog.destroy()
            self.refresh_list()
            if existing:
                self.show_detail(existing["id"])

        primary_button(scroll, "Enregistrer", command=save).pack(fill="x", padx=32, pady=(24, 8))
        secondary_button(scroll, "Annuler", command=dialog.destroy).pack(fill="x", padx=32, pady=(0, 20))
