"""
MK Suite - Module Gestion Clients
Reproduit la structure exacte de l'onglet "Clients" du classeur Excel MK Entreprise :
ID Client (CL-001), Nom, Type, Téléphone, Adresse, Date 1er contact, Statut
+ Total Facturé / Encaissé / Solde Dû calculés depuis les Factures.
"""
import customtkinter as ctk
from ui.theme import COLORS, font, title_font, card, primary_button, secondary_button, danger_button, search_entry
from ui.widgets import section_title, status_badge, show_context_menu
from ui.reference_lists import TYPE_CLIENT, STATUT_ACTIF_INACTIF


class ClientsView(ctk.CTkFrame):
    def __init__(self, parent, db, focus_id=None, **kwargs):
        super().__init__(parent, fg_color="transparent", **kwargs)
        self.db = db
        self.selected_client = None
        self.build()
        self.refresh_list()
        if focus_id:
            self.show_detail(focus_id)

    def build(self):
        header = ctk.CTkFrame(self, fg_color="transparent")
        header.pack(fill="x", padx=4, pady=(4, 16))
        section_title(header, "Clients", "Gère ta base clientèle").pack(side="left")
        primary_button(header, "+ Nouveau client", command=self.open_form).pack(side="right")

        search_row = ctk.CTkFrame(self, fg_color="transparent")
        search_row.pack(fill="x", padx=4, pady=(0, 12))
        self.search_var = ctk.StringVar()
        self.search_var.trace_add("write", lambda *a: self.refresh_list())
        search_field = search_entry(search_row, self.search_var,
                                     "🔍 Rechercher un client (nom, téléphone, code...)")
        search_field.pack(fill="x")

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
        ctk.CTkLabel(self.detail_panel, text="👤", font=font(40)).pack(pady=(60, 10))
        ctk.CTkLabel(self.detail_panel, text="Sélectionne un client\npour voir les détails",
                     font=font(13), text_color=COLORS["text_secondary"], justify="center").pack()

    def refresh_list(self):
        for w in self.list_frame.winfo_children():
            w.destroy()

        query = self.search_var.get().strip()
        if query:
            rows = self.db.fetchall(
                "SELECT * FROM clients WHERE nom LIKE ? OR telephone LIKE ? OR code LIKE ? ORDER BY code",
                (f"%{query}%", f"%{query}%", f"%{query}%"))
        else:
            rows = self.db.fetchall("SELECT * FROM clients ORDER BY code")

        if not rows:
            ctk.CTkLabel(self.list_frame, text="Aucun client trouvé. Clique sur '+ Nouveau client' pour commencer.",
                         font=font(12), text_color=COLORS["text_muted"]).pack(pady=40)
            return

        for i, r in enumerate(rows):
            self._build_client_row(r, i)

    def _build_client_row(self, r, idx):
        bg = COLORS["bg_card"] if idx % 2 == 0 else COLORS["bg_dark"]
        row = ctk.CTkFrame(self.list_frame, fg_color=bg, corner_radius=10, height=64)
        row.pack(fill="x", pady=3)
        row.pack_propagate(False)

        code_badge = ctk.CTkFrame(row, fg_color=COLORS["bg_input"], corner_radius=6, width=64, height=26)
        code_badge.pack(side="left", padx=(16, 12), pady=19)
        code_badge.pack_propagate(False)
        ctk.CTkLabel(code_badge, text=r["code"] or "—", font=font(11, "bold"),
                     text_color=COLORS["gold"]).pack(expand=True)

        info = ctk.CTkFrame(row, fg_color="transparent")
        info.pack(side="left", fill="both", expand=True, pady=10)
        ctk.CTkLabel(info, text=r["nom"], font=font(13, "bold"), text_color=COLORS["text_primary"],
                     anchor="w").pack(anchor="w")
        ctk.CTkLabel(info, text=r["telephone"] or "—", font=font(11),
                     text_color=COLORS["text_secondary"], anchor="w").pack(anchor="w")

        type_lbl = ctk.CTkLabel(row, text=r["type_client"], font=font(11, "bold"),
                                 text_color=COLORS["gold"])
        type_lbl.pack(side="right", padx=16)

        for widget in (row, info, code_badge):
            widget.bind("<Button-1>", lambda e, cid=r["id"]: self.show_detail(cid))
        row.bind("<Enter>", lambda e, w=row: w.configure(fg_color=COLORS["bg_card_hover"]))
        row.bind("<Leave>", lambda e, w=row, b=bg: w.configure(fg_color=b))

        def on_right_click(event, cid=r["id"], row_data=r):
            items = [
                ("👁 Voir le détail", lambda: self.show_detail(cid)),
                ("✏️ Modifier", lambda: self.open_form(row_data)),
                (None, None),
                ("🗑 Supprimer", lambda: self.delete_client(cid)),
            ]
            show_context_menu(row, event, items)

        for widget in (row, info, code_badge):
            widget.bind("<Button-3>", on_right_click)

    def show_detail(self, client_id):
        r = self.db.fetchone("SELECT * FROM clients WHERE id=?", (client_id,))
        if not r:
            return
        for w in self.detail_panel.winfo_children():
            w.destroy()

        code_badge = ctk.CTkFrame(self.detail_panel, fg_color=COLORS["gold"], corner_radius=10,
                                   width=80, height=32)
        code_badge.pack(pady=(28, 10))
        code_badge.pack_propagate(False)
        ctk.CTkLabel(code_badge, text=r["code"] or "—", font=font(13, "bold"),
                     text_color="#0B1220").pack(expand=True)

        ctk.CTkLabel(self.detail_panel, text=r["nom"], font=font(16, "bold"),
                     text_color=COLORS["text_primary"]).pack()
        badge_row = ctk.CTkFrame(self.detail_panel, fg_color="transparent")
        badge_row.pack(pady=(6, 20))
        status_badge(badge_row, r["type_client"], "info").pack(side="left", padx=3)
        status_badge(badge_row, r["statut"], "success" if r["statut"] == "Actif" else "neutral").pack(
            side="left", padx=3)

        fields = [
            ("📞 Téléphone", r["telephone"] or "—"),
            ("📍 Adresse", r["adresse"] or "—"),
            ("🧾 NIF", r["nif"] or "—"),
            ("📅 1er contact", (r["date_premier_contact"] or "—")[:10]),
        ]
        for label, value in fields:
            f = ctk.CTkFrame(self.detail_panel, fg_color="transparent")
            f.pack(fill="x", padx=24, pady=6)
            ctk.CTkLabel(f, text=label, font=font(11), text_color=COLORS["text_muted"],
                         anchor="w").pack(anchor="w")
            ctk.CTkLabel(f, text=value, font=font(12, "bold"), text_color=COLORS["text_primary"],
                         anchor="w").pack(anchor="w")

        # Statistiques : Nb Devis, Nb Factures, Total Facturé, Total Encaissé, Solde Dû
        nb_devis = self.db.fetchone("SELECT COUNT(*) as c FROM devis WHERE client_id=?", (client_id,))
        fact_stats = self.db.fetchone(
            "SELECT COUNT(*) as c, COALESCE(SUM(montant_ttc),0) as ttc, "
            "COALESCE(SUM(avance_recue),0) as encaisse, COALESCE(SUM(reste_a_payer),0) as solde "
            "FROM factures WHERE client_id=?", (client_id,))

        stats_card = ctk.CTkFrame(self.detail_panel, fg_color=COLORS["bg_input"], corner_radius=10)
        stats_card.pack(fill="x", padx=24, pady=(12, 8))
        stat_lines = [
            ("Devis", str(nb_devis["c"])),
            ("Factures", str(fact_stats["c"])),
            ("Total facturé TTC", f"{fact_stats['ttc']:,.0f} FCFA".replace(",", " ")),
            ("Total encaissé", f"{fact_stats['encaisse']:,.0f} FCFA".replace(",", " ")),
            ("Solde dû", f"{fact_stats['solde']:,.0f} FCFA".replace(",", " ")),
        ]
        for label, value in stat_lines:
            row = ctk.CTkFrame(stats_card, fg_color="transparent")
            row.pack(fill="x", padx=12, pady=4)
            ctk.CTkLabel(row, text=label, font=font(11), text_color=COLORS["text_secondary"],
                         anchor="w").pack(side="left")
            color = COLORS["danger"] if label == "Solde dû" and fact_stats["solde"] > 0 else COLORS["text_primary"]
            ctk.CTkLabel(row, text=value, font=font(11, "bold"), text_color=color,
                         anchor="e").pack(side="right")
        ctk.CTkFrame(stats_card, fg_color="transparent", height=8).pack()

        btn_row = ctk.CTkFrame(self.detail_panel, fg_color="transparent")
        btn_row.pack(fill="x", padx=24, pady=(16, 20))
        secondary_button(btn_row, "Modifier", command=lambda: self.open_form(r)).pack(
            fill="x", pady=4)
        danger_button(btn_row, "Supprimer", command=lambda: self.delete_client(client_id)).pack(
            fill="x", pady=4)

    def delete_client(self, client_id):
        dialog = ctk.CTkToplevel(self)
        dialog.title("Confirmation")
        dialog.geometry("360x160")
        dialog.configure(fg_color=COLORS["bg_dark"])
        dialog.transient(self)
        dialog.grab_set()
        dialog.bind("<Escape>", lambda e: dialog.destroy())
        ctk.CTkLabel(dialog, text="Supprimer ce client ?", font=font(14, "bold"),
                     text_color=COLORS["text_primary"]).pack(pady=(24, 6))
        ctk.CTkLabel(dialog, text="Il restera 30 jours dans la Corbeille, restaurable si besoin.",
                     font=font(12), text_color=COLORS["text_secondary"], wraplength=300,
                     justify="center").pack(pady=(0, 16))
        row = ctk.CTkFrame(dialog, fg_color="transparent")
        row.pack()

        def confirm():
            c = self.db.fetchone("SELECT nom FROM clients WHERE id=?", (client_id,))
            libelle = f"Client {c['nom']}" if c else "Client"
            self.db.move_to_corbeille("clients", client_id, libelle, "Clients")
            dialog.destroy()
            self.refresh_list()
            self._show_empty_detail()

        secondary_button(row, "Annuler", command=dialog.destroy, width=120).pack(
            side="left", padx=6)
        danger_button(row, "Supprimer", command=confirm, width=120,
                      fg_color=COLORS["danger"], text_color="white").pack(side="left", padx=6)

    def open_form(self, existing=None):
        dialog = ctk.CTkToplevel(self)
        dialog.title("Client")
        dialog.geometry("420x560")
        dialog.configure(fg_color=COLORS["bg_dark"])
        dialog.transient(self)
        dialog.grab_set()
        dialog.bind("<Escape>", lambda e: dialog.destroy())

        scroll = ctk.CTkScrollableFrame(dialog, fg_color="transparent")
        scroll.pack(fill="both", expand=True)

        ctk.CTkLabel(scroll, text="Nouveau client" if not existing else "Modifier le client",
                     font=font(16, "bold"), text_color=COLORS["text_primary"]).pack(pady=(24, 4))

        code_preview = existing["code"] if existing else self.db.next_code("CL", "clients")
        ctk.CTkLabel(scroll, text=f"Code : {code_preview}", font=font(11),
                     text_color=COLORS["gold"]).pack(pady=(0, 12))

        fields = {}

        def add_field(label, key, value=""):
            ctk.CTkLabel(scroll, text=label, font=font(12), text_color=COLORS["text_secondary"],
                         anchor="w").pack(fill="x", padx=32, pady=(8, 2))
            entry = ctk.CTkEntry(scroll, height=40, corner_radius=8, fg_color=COLORS["bg_input"],
                                  border_color=COLORS["border"], font=font(13))
            entry.pack(fill="x", padx=32)
            entry.insert(0, value)
            fields[key] = entry

        add_field("Nom complet / Raison sociale *", "nom", existing["nom"] if existing else "")
        add_field("Téléphone", "telephone", existing["telephone"] if existing else "")
        add_field("Adresse", "adresse", existing["adresse"] if existing else "")
        add_field("NIF (Numéro d'Identification Fiscale)", "nif", existing["nif"] if existing else "")

        ctk.CTkLabel(scroll, text="Type de client", font=font(12), text_color=COLORS["text_secondary"],
                     anchor="w").pack(fill="x", padx=32, pady=(8, 2))
        type_var = ctk.StringVar(value=existing["type_client"] if existing else "Particulier")
        type_menu = ctk.CTkOptionMenu(scroll, values=TYPE_CLIENT,
                                       variable=type_var, height=40, corner_radius=8,
                                       fg_color=COLORS["bg_input"], button_color=COLORS["gold"],
                                       button_hover_color=COLORS["gold_light"],
                                       text_color=COLORS["text_primary"])
        type_menu.pack(fill="x", padx=32)

        ctk.CTkLabel(scroll, text="Statut", font=font(12), text_color=COLORS["text_secondary"],
                     anchor="w").pack(fill="x", padx=32, pady=(8, 2))
        statut_var = ctk.StringVar(value=existing["statut"] if existing else "Actif")
        statut_menu = ctk.CTkOptionMenu(scroll, values=["Actif", "Inactif"],
                                         variable=statut_var, height=40, corner_radius=8,
                                         fg_color=COLORS["bg_input"], button_color=COLORS["gold"],
                                         button_hover_color=COLORS["gold_light"],
                                         text_color=COLORS["text_primary"])
        statut_menu.pack(fill="x", padx=32)

        def save():
            nom = fields["nom"].get().strip()
            if not nom:
                fields["nom"].configure(border_color=COLORS["danger"])
                return
            if existing:
                self.db.execute(
                    "UPDATE clients SET nom=?, telephone=?, adresse=?, nif=?, type_client=?, statut=? WHERE id=?",
                    (nom, fields["telephone"].get(), fields["adresse"].get(), fields["nif"].get(),
                     type_var.get(), statut_var.get(), existing["id"]))
            else:
                code = self.db.next_code("CL", "clients")
                self.db.execute(
                    "INSERT INTO clients (code, nom, telephone, adresse, nif, type_client, statut) "
                    "VALUES (?,?,?,?,?,?,?)",
                    (code, nom, fields["telephone"].get(), fields["adresse"].get(), fields["nif"].get(),
                     type_var.get(), statut_var.get()))
            dialog.destroy()
            self.refresh_list()

        primary_button(scroll, "Enregistrer", command=save).pack(fill="x", padx=32, pady=(24, 8))
        secondary_button(scroll, "Annuler", command=dialog.destroy).pack(fill="x", padx=32, pady=(0, 20))
