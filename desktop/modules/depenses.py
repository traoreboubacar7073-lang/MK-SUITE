"""
MK Suite - Module Dépenses
Registre des dépenses journalières (import Excel : 1300+ lignes), avec recherche,
filtre par catégorie/mois, et totaux automatiques.
"""
import customtkinter as ctk
from tkinter import ttk
from ui.theme import COLORS, font, title_font, card, primary_button, secondary_button, danger_button, search_entry
from ui.widgets import section_title, confirm_delete, show_context_menu
from ui.reference_lists import CATEGORIE_DEPENSE, MODE_PAIEMENT, FOURNISSEURS_REFERENCE


MOIS_FR = ["Janvier", "Février", "Mars", "Avril", "Mai", "Juin", "Juillet",
           "Août", "Septembre", "Octobre", "Novembre", "Décembre"]


class DepensesView(ctk.CTkFrame):
    def __init__(self, parent, db, **kwargs):
        super().__init__(parent, fg_color="transparent", **kwargs)
        self.db = db
        self.categorie_filter = "Toutes"
        self.build()
        self.refresh_list()

    def build(self):
        header = ctk.CTkFrame(self, fg_color="transparent")
        header.pack(fill="x", padx=4, pady=(4, 16))
        section_title(header, "Dépenses", "Registre journalier des sorties d'argent").pack(side="left")
        self.new_btn = primary_button(header, "+ Nouvelle dépense", command=self.open_form)
        self.new_btn.pack(side="right")

        tabs = ctk.CTkFrame(self, fg_color=COLORS["bg_card"], corner_radius=10, height=44)
        tabs.pack(fill="x", padx=4, pady=(0, 12))
        self.tab_registre_btn = ctk.CTkButton(
            tabs, text="📋 Registre", command=lambda: self.switch_tab("registre"),
            fg_color=COLORS["gold"], text_color="#0B1220", font=font(13, "bold"),
            corner_radius=8, height=36, width=160)
        self.tab_registre_btn.pack(side="left", padx=6, pady=4)
        self.tab_annuelle_btn = ctk.CTkButton(
            tabs, text="📅 Vue annuelle", command=lambda: self.switch_tab("annuelle"),
            fg_color="transparent", text_color=COLORS["text_secondary"], font=font(13),
            corner_radius=8, height=36, width=160)
        self.tab_annuelle_btn.pack(side="left", padx=6, pady=4)
        self.mode = "registre"

        # Bandeau de totaux
        self.totals_row = ctk.CTkFrame(self, fg_color="transparent")
        self.totals_row.pack(fill="x", padx=4, pady=(0, 12))

        self.filters = ctk.CTkFrame(self, fg_color="transparent")
        self.filters.pack(fill="x", padx=4, pady=(0, 12))
        self.search_var = ctk.StringVar()
        self.search_var.trace_add("write", lambda *a: self.refresh_list())
        search_field = search_entry(self.filters, self.search_var,
                                     "🔍 Rechercher (bénéficiaire, description...)")
        search_field.pack(side="left", fill="x", expand=True, padx=(0, 8))

        categories = self.db.fetchall("SELECT DISTINCT categorie FROM depenses ORDER BY categorie")
        cat_values = ["Toutes"] + [c["categorie"] for c in categories if c["categorie"]]
        self.cat_var = ctk.StringVar(value="Toutes")
        cat_menu = ctk.CTkOptionMenu(self.filters, values=cat_values, variable=self.cat_var,
                                      command=lambda v: self.refresh_list(), height=42, width=220,
                                      corner_radius=10, fg_color=COLORS["bg_input"],
                                      button_color=COLORS["gold"], button_hover_color=COLORS["gold_light"],
                                      text_color=COLORS["text_primary"])
        cat_menu.pack(side="left")

        self.body = ctk.CTkFrame(self, fg_color="transparent")
        self.body.pack(fill="both", expand=True, padx=4)
        self.body.grid_columnconfigure(0, weight=1)
        self.body.grid_columnconfigure(1, weight=0)
        self.body.grid_rowconfigure(0, weight=1)

        self.list_frame = ctk.CTkFrame(self.body, fg_color="transparent")
        self.list_frame.grid(row=0, column=0, sticky="nsew", padx=(0, 8))
        self.tree = None

        self.detail_panel = ctk.CTkScrollableFrame(self.body, width=320, fg_color=COLORS["bg_card"],
                                                     corner_radius=14, border_width=1,
                                                     border_color=COLORS["border"])
        self.detail_panel.grid(row=0, column=1, sticky="nsew")
        self._show_empty_detail()

    def _show_empty_detail(self):
        for w in self.detail_panel.winfo_children():
            w.destroy()
        ctk.CTkLabel(self.detail_panel, text="💳", font=font(40)).pack(pady=(60, 10))
        ctk.CTkLabel(self.detail_panel, text="Sélectionne une dépense\npour voir le détail",
                     font=font(13), text_color=COLORS["text_secondary"], justify="center").pack()

    def switch_tab(self, mode):
        self.mode = mode
        if mode == "registre":
            self.tab_registre_btn.configure(fg_color=COLORS["gold"], text_color="#0B1220", font=font(13, "bold"))
            self.tab_annuelle_btn.configure(fg_color="transparent", text_color=COLORS["text_secondary"], font=font(13))
            self.filters.pack(fill="x", padx=4, pady=(0, 12))
            self.new_btn.configure(state="normal")
            self.list_frame.grid(row=0, column=0, sticky="nsew", padx=(0, 8))
            self.detail_panel.grid(row=0, column=1, sticky="nsew")
            self.refresh_list()
        else:
            self.tab_annuelle_btn.configure(fg_color=COLORS["gold"], text_color="#0B1220", font=font(13, "bold"))
            self.tab_registre_btn.configure(fg_color="transparent", text_color=COLORS["text_secondary"], font=font(13))
            self.filters.pack_forget()
            self.detail_panel.grid_remove()
            self.list_frame.grid(row=0, column=0, columnspan=2, sticky="nsew", padx=0)
            self._build_annual_view()

        self._build_totals()

    def _build_totals(self):
        for w in self.totals_row.winfo_children():
            w.destroy()
        total = self.db.fetchone("SELECT COALESCE(SUM(montant),0) as t, COUNT(*) as c FROM depenses")
        cards_data = [
            ("Total dépenses", f"{total['t']:,.0f} FCFA".replace(",", " "), COLORS["danger"]),
            ("Nombre d'entrées", str(total["c"]), COLORS["info"]),
        ]
        for label, val, color in cards_data:
            c = ctk.CTkFrame(self.totals_row, fg_color=COLORS["bg_card"], corner_radius=10,
                              border_width=1, border_color=COLORS["border"])
            c.pack(side="left", padx=(0, 10), ipady=8, ipadx=16)
            ctk.CTkLabel(c, text=label.upper(), font=font(10, "bold"),
                         text_color=COLORS["text_secondary"]).pack(anchor="w", padx=14, pady=(6, 0))
            ctk.CTkLabel(c, text=val, font=font(16, "bold"), text_color=color).pack(
                anchor="w", padx=14, pady=(0, 6))

    def _build_annual_view(self):
        from datetime import datetime
        for w in self.totals_row.winfo_children():
            w.destroy()
        for w in self.list_frame.winfo_children():
            w.destroy()

        annee = datetime.now().year
        annee_row = ctk.CTkFrame(self.totals_row, fg_color="transparent")
        annee_row.pack(side="left")
        ctk.CTkLabel(annee_row, text=f"Année analysée : {annee}", font=font(13, "bold"),
                     text_color=COLORS["gold"]).pack(anchor="w", pady=6)

        mois_abbrev = ["Jan", "Fév", "Mar", "Avr", "Mai", "Jun", "Jul", "Aoû", "Sep", "Oct", "Nov", "Déc"]

        table_scroll = ctk.CTkScrollableFrame(self.list_frame, fg_color="transparent",
                                               orientation="horizontal", height=520)
        table_scroll.pack(fill="both", expand=True)

        grid = ctk.CTkFrame(table_scroll, fg_color="transparent")
        grid.pack(fill="both", expand=True)

        col_w = 78
        header_row = ctk.CTkFrame(grid, fg_color=COLORS["bg_sidebar"], corner_radius=8)
        header_row.pack(fill="x", pady=(0, 4))
        ctk.CTkLabel(header_row, text="CATÉGORIE", font=font(10, "bold"), text_color=COLORS["gold"],
                     width=210, anchor="w").pack(side="left", padx=8, pady=8)
        for m in mois_abbrev:
            ctk.CTkLabel(header_row, text=m.upper(), font=font(10, "bold"), text_color=COLORS["gold"],
                         width=col_w, anchor="e").pack(side="left", padx=4, pady=8)
        ctk.CTkLabel(header_row, text="TOTAL", font=font(10, "bold"), text_color=COLORS["gold"],
                     width=100, anchor="e").pack(side="left", padx=8, pady=8)

        totaux_mensuels = [0] * 12
        grand_total = 0

        for i, categorie in enumerate(CATEGORIE_DEPENSE):
            bg = COLORS["bg_card"] if i % 2 == 0 else COLORS["bg_dark"]
            row = ctk.CTkFrame(grid, fg_color=bg, corner_radius=8)
            row.pack(fill="x", pady=1)
            ctk.CTkLabel(row, text=categorie, font=font(11), text_color=COLORS["text_primary"],
                         width=210, anchor="w").pack(side="left", padx=8, pady=8)

            total_categorie = 0
            for m in range(1, 13):
                mois_key = f"{annee}-{m:02d}"
                r = self.db.fetchone(
                    "SELECT COALESCE(SUM(montant),0) as t FROM depenses WHERE categorie=? AND date_depense LIKE ?",
                    (categorie, f"{mois_key}%"))
                val = r["t"]
                total_categorie += val
                totaux_mensuels[m - 1] += val
                txt = f"{val:,.0f}".replace(",", " ") if val else "—"
                color = COLORS["text_primary"] if val else COLORS["text_muted"]
                ctk.CTkLabel(row, text=txt, font=font(10), text_color=color,
                             width=col_w, anchor="e").pack(side="left", padx=4, pady=8)

            grand_total += total_categorie
            ctk.CTkLabel(row, text=f"{total_categorie:,.0f}".replace(",", " "), font=font(11, "bold"),
                         text_color=COLORS["gold"], width=100, anchor="e").pack(side="left", padx=8, pady=8)

        total_row = ctk.CTkFrame(grid, fg_color=COLORS["gold"], corner_radius=8)
        total_row.pack(fill="x", pady=(6, 0))
        ctk.CTkLabel(total_row, text="TOTAL MENSUEL", font=font(11, "bold"), text_color="#0B1220",
                     width=210, anchor="w").pack(side="left", padx=8, pady=8)
        for val in totaux_mensuels:
            txt = f"{val:,.0f}".replace(",", " ") if val else "—"
            ctk.CTkLabel(total_row, text=txt, font=font(10, "bold"), text_color="#0B1220",
                         width=col_w, anchor="e").pack(side="left", padx=4, pady=8)
        ctk.CTkLabel(total_row, text=f"{grand_total:,.0f}".replace(",", " "), font=font(11, "bold"),
                     text_color="#0B1220", width=100, anchor="e").pack(side="left", padx=8, pady=8)

    def _style_treeview(self):
        """Configure le style sombre du Treeview pour qu'il s'intègre au thème MK Suite"""
        style = ttk.Style()
        try:
            style.theme_use("clam")
        except Exception:
            pass
        style.configure("MK.Treeview",
                         background=COLORS["bg_card"], fieldbackground=COLORS["bg_card"],
                         foreground=COLORS["text_primary"], rowheight=32, borderwidth=0,
                         font=("Segoe UI", 10))
        style.configure("MK.Treeview.Heading",
                         background=COLORS["bg_sidebar"], foreground=COLORS["gold"],
                         font=("Segoe UI", 10, "bold"), borderwidth=0, relief="flat")
        style.map("MK.Treeview",
                  background=[("selected", COLORS["bg_card_hover"])],
                  foreground=[("selected", COLORS["gold"])])
        style.map("MK.Treeview.Heading", background=[("active", COLORS["bg_sidebar"])])
        style.layout("MK.Treeview", [('MK.Treeview.treearea', {'sticky': 'nswe'})])

    def refresh_list(self):
        for w in self.list_frame.winfo_children():
            w.destroy()

        query = self.search_var.get().strip()
        categorie = self.cat_var.get()
        sql = "SELECT * FROM depenses WHERE 1=1"
        params = []
        if query:
            sql += " AND (beneficiaire LIKE ? OR description LIKE ?)"
            params += [f"%{query}%", f"%{query}%"]
        if categorie != "Toutes":
            sql += " AND categorie = ?"
            params.append(categorie)
        sql += " ORDER BY date_depense DESC"
        rows = self.db.fetchall(sql, tuple(params))

        if not rows:
            ctk.CTkLabel(self.list_frame, text="Aucune dépense trouvée.",
                         font=font(12), text_color=COLORS["text_muted"]).pack(pady=40)
            return

        self._style_treeview()

        tree_frame = ctk.CTkFrame(self.list_frame, fg_color=COLORS["bg_card"], corner_radius=10)
        tree_frame.pack(fill="both", expand=True)

        columns = ("date", "categorie", "beneficiaire", "mode", "montant")
        tree = ttk.Treeview(tree_frame, columns=columns, show="headings", style="MK.Treeview",
                             selectmode="browse")
        tree.heading("date", text="DATE")
        tree.heading("categorie", text="CATÉGORIE")
        tree.heading("beneficiaire", text="BÉNÉFICIAIRE")
        tree.heading("mode", text="MODE")
        tree.heading("montant", text="MONTANT (FCFA)")
        tree.column("date", width=90, anchor="w")
        tree.column("categorie", width=260, anchor="w")
        tree.column("beneficiaire", width=220, anchor="w")
        tree.column("mode", width=160, anchor="w")
        tree.column("montant", width=140, anchor="e")

        # Insertion en masse — bien plus rapide que créer un widget par cellule
        for r in rows:
            tree.insert("", "end", iid=str(r["id"]), values=(
                (r["date_depense"] or "")[:10],
                r["categorie"] or "—",
                r["beneficiaire"] or "—",
                r["mode_paiement"] or "—",
                f"{r['montant']:,.0f}".replace(",", " "),
            ))

        def on_select(event):
            sel = tree.selection()
            if sel:
                self.show_detail(int(sel[0]))

        tree.bind("<<TreeviewSelect>>", on_select)

        def on_right_click(event):
            row_iid = tree.identify_row(event.y)
            if not row_iid:
                return
            tree.selection_set(row_iid)
            dep_id = int(row_iid)
            show_context_menu(tree, event, [
                ("👁 Voir le détail", lambda: self.show_detail(dep_id)),
                ("✏️ Modifier", lambda: self.open_form(existing_id=dep_id)),
                (None, None),
                ("🗑 Supprimer", lambda: self._delete_depense(dep_id)),
            ])

        tree.bind("<Button-3>", on_right_click)

        vsb = ttk.Scrollbar(tree_frame, orient="vertical", command=tree.yview)
        tree.configure(yscrollcommand=vsb.set)
        tree.pack(side="left", fill="both", expand=True, padx=(1, 0), pady=1)
        vsb.pack(side="right", fill="y")
        self.tree = tree

        count_lbl = ctk.CTkLabel(self.list_frame, text=f"{len(rows)} dépense(s) affichée(s)",
                                  font=font(10), text_color=COLORS["text_muted"])
        count_lbl.pack(anchor="w", pady=(6, 0))

    def show_detail(self, dep_id):
        r = self.db.fetchone("SELECT * FROM depenses WHERE id=?", (dep_id,))
        if not r:
            return
        for w in self.detail_panel.winfo_children():
            w.destroy()

        head = ctk.CTkFrame(self.detail_panel, fg_color="transparent")
        head.pack(fill="x", padx=24, pady=(28, 12))
        ctk.CTkLabel(head, text=r["categorie"] or "Sans catégorie", font=font(15, "bold"),
                     text_color=COLORS["gold"], wraplength=270, justify="left").pack(anchor="w")
        ctk.CTkLabel(head, text=(r["date_depense"] or "")[:10], font=font(12),
                     text_color=COLORS["text_secondary"]).pack(anchor="w", pady=(2, 0))

        info_card = ctk.CTkFrame(self.detail_panel, fg_color=COLORS["bg_input"], corner_radius=10)
        info_card.pack(fill="x", padx=24, pady=8)
        for label, val in [
            ("Description", r["description"] or "—"),
            ("Fournisseur / Bénéficiaire", r["beneficiaire"] or "—"),
            ("Mode de paiement", r["mode_paiement"] or "—"),
        ]:
            row = ctk.CTkFrame(info_card, fg_color="transparent")
            row.pack(fill="x", padx=12, pady=6)
            ctk.CTkLabel(row, text=label, font=font(11), text_color=COLORS["text_secondary"],
                         anchor="w").pack(anchor="w")
            ctk.CTkLabel(row, text=val, font=font(12, "bold"), text_color=COLORS["text_primary"],
                         anchor="w", wraplength=270, justify="left").pack(anchor="w")
        ctk.CTkFrame(info_card, fg_color="transparent", height=6).pack()

        total_card = ctk.CTkFrame(self.detail_panel, fg_color=COLORS["danger"], corner_radius=10)
        total_card.pack(fill="x", padx=24, pady=8)
        ctk.CTkLabel(total_card, text="MONTANT", font=font(10, "bold"), text_color="white").pack(
            pady=(10, 0))
        ctk.CTkLabel(total_card, text=f"{r['montant']:,.0f} FCFA".replace(",", " "),
                     font=font(18, "bold"), text_color="white").pack(pady=(0, 10))

        btn_row = ctk.CTkFrame(self.detail_panel, fg_color="transparent")
        btn_row.pack(fill="x", padx=24, pady=(16, 20))
        secondary_button(btn_row, "✏️ Modifier",
                          command=lambda: self.open_form(existing_id=dep_id)).pack(fill="x", pady=2)
        danger_button(btn_row, "Supprimer",
                      command=lambda: self._delete_depense(dep_id)).pack(fill="x", pady=2)

    def open_form(self, existing_id=None):
        existing = self.db.fetchone("SELECT * FROM depenses WHERE id=?", (existing_id,)) if existing_id else None

        dialog = ctk.CTkToplevel(self)
        dialog.title("Dépense")
        dialog.geometry("420x560")
        dialog.configure(fg_color=COLORS["bg_dark"])
        dialog.transient(self)
        dialog.grab_set()
        dialog.bind("<Escape>", lambda e: dialog.destroy())

        scroll = ctk.CTkScrollableFrame(dialog, fg_color="transparent")
        scroll.pack(fill="both", expand=True)

        ctk.CTkLabel(scroll, text="Modifier la dépense" if existing else "Nouvelle dépense",
                     font=font(16, "bold"), text_color=COLORS["text_primary"]).pack(pady=(24, 16))

        fields = {}

        def add_field(label, key, value=""):
            ctk.CTkLabel(scroll, text=label, font=font(12), text_color=COLORS["text_secondary"],
                         anchor="w").pack(fill="x", padx=32, pady=(8, 2))
            entry = ctk.CTkEntry(scroll, height=40, corner_radius=8, fg_color=COLORS["bg_input"],
                                  border_color=COLORS["border"], font=font(13))
            entry.pack(fill="x", padx=32)
            entry.insert(0, str(value))
            fields[key] = entry

        from datetime import datetime
        add_field("Date (AAAA-MM-JJ)", "date",
                   existing["date_depense"][:10] if existing else datetime.now().strftime("%Y-%m-%d"))

        ctk.CTkLabel(scroll, text="Catégorie", font=font(12), text_color=COLORS["text_secondary"],
                     anchor="w").pack(fill="x", padx=32, pady=(8, 2))
        cat_var = ctk.StringVar(value=existing["categorie"] if existing and existing["categorie"] in CATEGORIE_DEPENSE
                                 else CATEGORIE_DEPENSE[0])
        ctk.CTkOptionMenu(scroll, values=CATEGORIE_DEPENSE, variable=cat_var, height=40, corner_radius=8,
                           fg_color=COLORS["bg_input"], button_color=COLORS["gold"],
                           button_hover_color=COLORS["gold_light"], text_color=COLORS["text_primary"]).pack(
            fill="x", padx=32)

        add_field("Description", "description", existing["description"] if existing else "")

        ctk.CTkLabel(scroll, text="Fournisseur / Bénéficiaire", font=font(12), text_color=COLORS["text_secondary"],
                     anchor="w").pack(fill="x", padx=32, pady=(8, 2))
        default_benef = existing["beneficiaire"] if existing and existing["beneficiaire"] in FOURNISSEURS_REFERENCE \
            else FOURNISSEURS_REFERENCE[0]
        benef_var = ctk.StringVar(value=default_benef)
        ctk.CTkOptionMenu(scroll, values=FOURNISSEURS_REFERENCE, variable=benef_var, height=40, corner_radius=8,
                           fg_color=COLORS["bg_input"], button_color=COLORS["gold"],
                           button_hover_color=COLORS["gold_light"], text_color=COLORS["text_primary"]).pack(
            fill="x", padx=32)

        add_field("Montant (FCFA)", "montant", existing["montant"] if existing else "")

        ctk.CTkLabel(scroll, text="Mode de paiement", font=font(12), text_color=COLORS["text_secondary"],
                     anchor="w").pack(fill="x", padx=32, pady=(8, 2))
        mode_var = ctk.StringVar(value=existing["mode_paiement"] if existing and existing["mode_paiement"] else "Espèces")
        mode_menu = ctk.CTkOptionMenu(scroll, values=MODE_PAIEMENT,
                                       variable=mode_var, height=40, corner_radius=8,
                                       fg_color=COLORS["bg_input"], button_color=COLORS["gold"],
                                       button_hover_color=COLORS["gold_light"], text_color=COLORS["text_primary"])
        mode_menu.pack(fill="x", padx=32)

        def save():
            try:
                montant = float(fields["montant"].get().replace(" ", "").replace(",", ""))
            except ValueError:
                fields["montant"].configure(border_color=COLORS["danger"])
                return
            if existing:
                self.db.execute(
                    "UPDATE depenses SET date_depense=?, categorie=?, description=?, beneficiaire=?, "
                    "montant=?, mode_paiement=? WHERE id=?",
                    (fields["date"].get(), cat_var.get(), fields["description"].get(),
                     benef_var.get(), montant, mode_var.get(), existing["id"]))
            else:
                self.db.execute(
                    "INSERT INTO depenses (date_depense, categorie, description, beneficiaire, montant, "
                    "mode_paiement, justificatif) VALUES (?,?,?,?,?,?,?)",
                    (fields["date"].get(), cat_var.get(), fields["description"].get(),
                     benef_var.get(), montant, mode_var.get(), "Non"))
            dialog.destroy()
            self._build_totals()
            self.refresh_list()

        primary_button(scroll, "Enregistrer", command=save).pack(fill="x", padx=32, pady=(24, 8))
        secondary_button(scroll, "Annuler", command=dialog.destroy).pack(fill="x", padx=32, pady=(0, 20))

    def _delete_depense(self, dep_id):
        r = self.db.fetchone("SELECT description, montant, date_depense FROM depenses WHERE id=?", (dep_id,))
        libelle = f"Dépense {r['description'] or ''} ({r['montant']:,.0f} FCFA)".replace(",", " ") if r else "Dépense"

        def do_delete():
            self.db.move_to_corbeille("depenses", dep_id, libelle, "Dépenses")
            self._build_totals()
            self.refresh_list()
            self._show_empty_detail()

        confirm_delete(self, "Supprimer cette dépense ?",
                        "Elle restera 30 jours dans la Corbeille, restaurable si besoin.", do_delete)
