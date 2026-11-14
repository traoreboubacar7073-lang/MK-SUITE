"""
MK Suite - Module Sourcing
Centralise l'achat de matériaux chez un fournisseur pour la revente à un client,
avec calcul automatique de la marge (prix vente - prix achat) x quantité.
"""
import customtkinter as ctk
from ui.theme import COLORS, font, title_font, card, primary_button, secondary_button, danger_button
from ui.widgets import section_title, status_badge, confirm_delete, show_context_menu

STATUT_COLORS = {"En cours": "warning", "Livré": "success", "Annulé": "danger"}


class SourcingView(ctk.CTkFrame):
    def __init__(self, parent, db, **kwargs):
        super().__init__(parent, fg_color="transparent", **kwargs)
        self.db = db
        self.build()
        self.refresh_list()

    def build(self):
        header = ctk.CTkFrame(self, fg_color="transparent")
        header.pack(fill="x", padx=4, pady=(4, 16))
        section_title(header, "Sourcing", "Achat fournisseur → revente client, marge calculée automatiquement").pack(
            side="left")
        primary_button(header, "+ Nouvelle commande", command=self.open_form).pack(side="right")

        self.totals_row = ctk.CTkFrame(self, fg_color="transparent")
        self.totals_row.pack(fill="x", padx=4, pady=(0, 16))

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
        ctk.CTkLabel(self.detail_panel, text="🚚", font=font(40)).pack(pady=(60, 10))
        ctk.CTkLabel(self.detail_panel, text="Sélectionne une commande\npour voir le détail",
                     font=font(13), text_color=COLORS["text_secondary"], justify="center").pack()

    def _build_totals(self):
        for w in self.totals_row.winfo_children():
            w.destroy()
        rows = self.db.fetchall("SELECT * FROM sourcing_commandes")
        total_achat = sum(r["quantite"] * r["prix_achat_unitaire"] for r in rows)
        total_vente = sum(r["quantite"] * r["prix_vente_unitaire"] for r in rows)
        marge = total_vente - total_achat
        cards_data = [
            ("Total achats", f"{total_achat:,.0f} FCFA".replace(",", " "), COLORS["text_secondary"]),
            ("Total ventes", f"{total_vente:,.0f} FCFA".replace(",", " "), COLORS["info"]),
            ("Marge totale", f"{marge:,.0f} FCFA".replace(",", " "),
             COLORS["success"] if marge >= 0 else COLORS["danger"]),
        ]
        for label, val, color in cards_data:
            c = ctk.CTkFrame(self.totals_row, fg_color=COLORS["bg_card"], corner_radius=10,
                              border_width=1, border_color=COLORS["border"])
            c.pack(side="left", padx=(0, 10), ipady=8, ipadx=16)
            ctk.CTkLabel(c, text=label.upper(), font=font(10, "bold"),
                         text_color=COLORS["text_secondary"]).pack(anchor="w", padx=14, pady=(6, 0))
            ctk.CTkLabel(c, text=val, font=font(16, "bold"), text_color=color).pack(
                anchor="w", padx=14, pady=(0, 6))

    def refresh_list(self):
        self._build_totals()
        for w in self.list_frame.winfo_children():
            w.destroy()
        rows = self.db.fetchall(
            "SELECT s.*, f.nom as fournisseur_nom, c.nom as client_nom FROM sourcing_commandes s "
            "LEFT JOIN fournisseurs f ON f.id = s.fournisseur_id "
            "LEFT JOIN clients c ON c.id = s.client_id ORDER BY s.id DESC")
        if not rows:
            ctk.CTkLabel(self.list_frame, text="Aucune commande de sourcing pour le moment. "
                                                 "Clique sur '+ Nouvelle commande' pour commencer.",
                         font=font(12), text_color=COLORS["text_muted"]).pack(pady=40)
            return
        for i, r in enumerate(rows):
            self._build_row(r, i)

    def _build_row(self, r, idx):
        bg = COLORS["bg_card"] if idx % 2 == 0 else COLORS["bg_dark"]
        row = ctk.CTkFrame(self.list_frame, fg_color=bg, corner_radius=10, height=64)
        row.pack(fill="x", pady=3)
        row.pack_propagate(False)

        num_badge = ctk.CTkFrame(row, fg_color=COLORS["bg_input"], corner_radius=6, width=110, height=26)
        num_badge.pack(side="left", padx=(16, 12), pady=19)
        num_badge.pack_propagate(False)
        ctk.CTkLabel(num_badge, text=r["numero"] or "—", font=font(10, "bold"),
                     text_color=COLORS["gold"]).pack(expand=True)

        info = ctk.CTkFrame(row, fg_color="transparent")
        info.pack(side="left", fill="both", expand=True, pady=10)
        ctk.CTkLabel(info, text=r["designation"] or "—", font=font(13, "bold"),
                     text_color=COLORS["text_primary"], anchor="w").pack(anchor="w")
        fourn = r["fournisseur_nom"] or "?"
        client = r["client_nom"] or "?"
        marge = (r["prix_vente_unitaire"] - r["prix_achat_unitaire"]) * r["quantite"]
        ctk.CTkLabel(info, text=f"{fourn} → {client} · marge {marge:,.0f} FCFA".replace(",", " "),
                     font=font(11), text_color=COLORS["text_secondary"], anchor="w").pack(anchor="w")

        status_badge(row, r["statut"], STATUT_COLORS.get(r["statut"], "neutral")).pack(side="right", padx=16)

        for widget in (row, info, num_badge):
            widget.bind("<Button-1>", lambda e, rid=r["id"]: self.show_detail(rid))
        row.bind("<Enter>", lambda e, w=row: w.configure(fg_color=COLORS["bg_card_hover"]))
        row.bind("<Leave>", lambda e, w=row, b=bg: w.configure(fg_color=b))

        def on_right_click(event, row_data=r):
            rid = row_data["id"]
            items = [
                ("👁 Voir le détail", lambda: self.show_detail(rid)),
                ("✏️ Modifier", lambda: self.open_form(existing=row_data)),
                (None, None),
            ]
            for statut in ["En cours", "Livré", "Annulé"]:
                if statut != row_data["statut"]:
                    items.append((f"Marquer « {statut} »", lambda s=statut: self._update_statut(rid, s)))
            items.append((None, None))
            items.append(("🗑 Supprimer", lambda: self._delete(rid)))
            show_context_menu(row, event, items)

        for widget in (row, info, num_badge):
            widget.bind("<Button-3>", on_right_click)

    def show_detail(self, row_id):
        r = self.db.fetchone("SELECT * FROM sourcing_commandes WHERE id=?", (row_id,))
        if not r:
            return
        fournisseur = self.db.fetchone("SELECT * FROM fournisseurs WHERE id=?", (r["fournisseur_id"],)) \
            if r["fournisseur_id"] else None
        client = self.db.fetchone("SELECT * FROM clients WHERE id=?", (r["client_id"],)) \
            if r["client_id"] else None

        for w in self.detail_panel.winfo_children():
            w.destroy()

        head = ctk.CTkFrame(self.detail_panel, fg_color="transparent")
        head.pack(fill="x", padx=24, pady=(24, 12))
        ctk.CTkLabel(head, text=r["numero"] or "—", font=font(16, "bold"),
                     text_color=COLORS["gold"]).pack(anchor="w")
        ctk.CTkLabel(head, text=r["designation"] or "", font=font(13),
                     text_color=COLORS["text_primary"], wraplength=280, justify="left").pack(
            anchor="w", pady=(2, 6))
        status_badge(head, r["statut"], STATUT_COLORS.get(r["statut"], "neutral")).pack(anchor="w")

        info_card = ctk.CTkFrame(self.detail_panel, fg_color=COLORS["bg_input"], corner_radius=10)
        info_card.pack(fill="x", padx=24, pady=8)
        for label, val in [
            ("Fournisseur", fournisseur["nom"] if fournisseur else "—"),
            ("Client", client["nom"] if client else "—"),
            ("Quantité", str(r["quantite"])),
            ("Prix achat unit.", f"{r['prix_achat_unitaire']:,.0f} FCFA".replace(",", " ")),
            ("Prix vente unit.", f"{r['prix_vente_unitaire']:,.0f} FCFA".replace(",", " ")),
            ("Livraison prévue", (r["date_livraison_prevue"] or "—")[:10] if r["date_livraison_prevue"] else "—"),
        ]:
            row = ctk.CTkFrame(info_card, fg_color="transparent")
            row.pack(fill="x", padx=12, pady=4)
            ctk.CTkLabel(row, text=label, font=font(11), text_color=COLORS["text_secondary"]).pack(side="left")
            ctk.CTkLabel(row, text=val, font=font(11, "bold"), text_color=COLORS["text_primary"]).pack(side="right")
        ctk.CTkFrame(info_card, fg_color="transparent", height=8).pack()

        marge = (r["prix_vente_unitaire"] - r["prix_achat_unitaire"]) * r["quantite"]
        marge_card = ctk.CTkFrame(self.detail_panel,
                                   fg_color=COLORS["success"] if marge >= 0 else COLORS["danger"],
                                   corner_radius=10)
        marge_card.pack(fill="x", padx=24, pady=8)
        ctk.CTkLabel(marge_card, text="MARGE TOTALE", font=font(11, "bold"), text_color="#0B1220").pack(
            pady=(10, 0))
        ctk.CTkLabel(marge_card, text=f"{marge:,.0f} FCFA".replace(",", " "),
                     font=font(18, "bold"), text_color="#0B1220").pack(pady=(0, 10))

        btn_row = ctk.CTkFrame(self.detail_panel, fg_color="transparent")
        btn_row.pack(fill="x", padx=24, pady=(16, 20))
        secondary_button(btn_row, "✏️ Modifier",
                          command=lambda: self.open_form(existing=r)).pack(fill="x", pady=(0, 4))
        for statut in ["En cours", "Livré", "Annulé"]:
            if statut != r["statut"]:
                secondary_button(btn_row, f"Marquer « {statut} »",
                                  command=lambda s=statut: self._update_statut(r["id"], s)).pack(
                    fill="x", pady=3)
        danger_button(btn_row, "Supprimer", command=lambda: self._delete(r["id"])).pack(fill="x", pady=(8, 0))

    def _update_statut(self, cmd_id, statut):
        self.db.execute("UPDATE sourcing_commandes SET statut=? WHERE id=?", (statut, cmd_id))
        self.refresh_list()
        self.show_detail(cmd_id)

    def _delete(self, cmd_id):
        r = self.db.fetchone("SELECT numero, designation FROM sourcing_commandes WHERE id=?", (cmd_id,))
        libelle = f"Sourcing {r['numero']} — {r['designation'] or ''}" if r else "Commande sourcing"

        def do_delete():
            self.db.move_to_corbeille("sourcing_commandes", cmd_id, libelle, "Sourcing")
            self.refresh_list()
            self._show_empty_detail()

        confirm_delete(self, "Supprimer cette commande de sourcing ?",
                        "Elle restera 30 jours dans la Corbeille, restaurable si besoin.", do_delete)

    def open_form(self, existing=None):
        dialog = ctk.CTkToplevel(self)
        dialog.title("Commande de sourcing")
        dialog.geometry("440x680")
        dialog.configure(fg_color=COLORS["bg_dark"])
        dialog.transient(self)
        dialog.grab_set()
        dialog.bind("<Escape>", lambda e: dialog.destroy())

        scroll = ctk.CTkScrollableFrame(dialog, fg_color="transparent")
        scroll.pack(fill="both", expand=True)

        ctk.CTkLabel(scroll, text="Modifier la commande" if existing else "Nouvelle commande de sourcing",
                     font=font(16, "bold"), text_color=COLORS["text_primary"]).pack(pady=(24, 16))

        fields = {}

        def add_field(label, key, value=""):
            ctk.CTkLabel(scroll, text=label, font=font(12), text_color=COLORS["text_secondary"],
                         anchor="w").pack(fill="x", padx=32, pady=(6, 2))
            entry = ctk.CTkEntry(scroll, height=38, corner_radius=8, fg_color=COLORS["bg_input"],
                                  border_color=COLORS["border"], font=font(13))
            entry.pack(fill="x", padx=32)
            entry.insert(0, str(value))
            fields[key] = entry

        add_field("Désignation *", "designation", existing["designation"] if existing else "")

        fournisseurs = self.db.fetchall("SELECT id, nom FROM fournisseurs ORDER BY nom")
        clients = self.db.fetchall("SELECT id, nom FROM clients ORDER BY nom")
        fourn_map = {f["nom"]: f["id"] for f in fournisseurs}
        client_map = {c["nom"]: c["id"] for c in clients}

        default_fourn = None
        default_client = None
        if existing:
            if existing["fournisseur_id"]:
                fr = self.db.fetchone("SELECT nom FROM fournisseurs WHERE id=?", (existing["fournisseur_id"],))
                default_fourn = fr["nom"] if fr else None
            if existing["client_id"]:
                cl = self.db.fetchone("SELECT nom FROM clients WHERE id=?", (existing["client_id"],))
                default_client = cl["nom"] if cl else None

        ctk.CTkLabel(scroll, text="Fournisseur", font=font(12), text_color=COLORS["text_secondary"],
                     anchor="w").pack(fill="x", padx=32, pady=(6, 2))
        fourn_var = ctk.StringVar(value=default_fourn or (fournisseurs[0]["nom"] if fournisseurs else ""))
        ctk.CTkOptionMenu(scroll, values=list(fourn_map.keys()) or ["—"], variable=fourn_var,
                           height=38, corner_radius=8, fg_color=COLORS["bg_input"],
                           button_color=COLORS["gold"], button_hover_color=COLORS["gold_light"],
                           text_color=COLORS["text_primary"]).pack(fill="x", padx=32)

        ctk.CTkLabel(scroll, text="Client", font=font(12), text_color=COLORS["text_secondary"],
                     anchor="w").pack(fill="x", padx=32, pady=(6, 2))
        client_var = ctk.StringVar(value=default_client or (clients[0]["nom"] if clients else ""))
        ctk.CTkOptionMenu(scroll, values=list(client_map.keys()) or ["—"], variable=client_var,
                           height=38, corner_radius=8, fg_color=COLORS["bg_input"],
                           button_color=COLORS["gold"], button_hover_color=COLORS["gold_light"],
                           text_color=COLORS["text_primary"]).pack(fill="x", padx=32)

        add_field("Quantité", "quantite", existing["quantite"] if existing else "1")
        add_field("Prix d'achat unitaire (FCFA)", "prix_achat",
                   existing["prix_achat_unitaire"] if existing else "0")
        add_field("Prix de vente unitaire (FCFA)", "prix_vente",
                   existing["prix_vente_unitaire"] if existing else "0")

        ctk.CTkLabel(scroll, text="Statut", font=font(12), text_color=COLORS["text_secondary"],
                     anchor="w").pack(fill="x", padx=32, pady=(6, 2))
        statut_var = ctk.StringVar(value=existing["statut"] if existing else "En cours")
        ctk.CTkOptionMenu(scroll, values=["En cours", "Livré", "Annulé"], variable=statut_var,
                           height=38, corner_radius=8, fg_color=COLORS["bg_input"],
                           button_color=COLORS["gold"], button_hover_color=COLORS["gold_light"],
                           text_color=COLORS["text_primary"]).pack(fill="x", padx=32)

        def save():
            designation = fields["designation"].get().strip()
            if not designation:
                fields["designation"].configure(border_color=COLORS["danger"])
                return
            try:
                qte = float(fields["quantite"].get() or 1)
                p_achat = float(fields["prix_achat"].get() or 0)
                p_vente = float(fields["prix_vente"].get() or 0)
            except ValueError:
                return
            if existing:
                self.db.execute(
                    "UPDATE sourcing_commandes SET fournisseur_id=?, client_id=?, designation=?, "
                    "quantite=?, prix_achat_unitaire=?, prix_vente_unitaire=?, statut=? WHERE id=?",
                    (fourn_map.get(fourn_var.get()), client_map.get(client_var.get()), designation,
                     qte, p_achat, p_vente, statut_var.get(), existing["id"]))
            else:
                numero = self.db.next_numero("SRC", "sourcing_commandes")
                self.db.execute(
                    "INSERT INTO sourcing_commandes (numero, fournisseur_id, client_id, designation, "
                    "quantite, prix_achat_unitaire, prix_vente_unitaire, statut) VALUES (?,?,?,?,?,?,?,?)",
                    (numero, fourn_map.get(fourn_var.get()), client_map.get(client_var.get()),
                     designation, qte, p_achat, p_vente, statut_var.get()))
            dialog.destroy()
            self.refresh_list()
            if existing:
                self.show_detail(existing["id"])

        primary_button(scroll, "Enregistrer", command=save).pack(fill="x", padx=32, pady=(20, 8))
        secondary_button(scroll, "Annuler", command=dialog.destroy).pack(fill="x", padx=32, pady=(0, 20))
