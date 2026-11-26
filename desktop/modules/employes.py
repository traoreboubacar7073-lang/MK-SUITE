"""
MK Suite - Module Personnel & Paie
"""
import customtkinter as ctk
from datetime import datetime
from ui.theme import COLORS, font, title_font, card, primary_button, secondary_button, danger_button, search_entry
from ui.widgets import section_title, status_badge, confirm_delete, show_context_menu
from ui.reference_lists import MOIS, MODE_PAIEMENT


class EmployesView(ctk.CTkFrame):
    def __init__(self, parent, db, **kwargs):
        super().__init__(parent, fg_color="transparent", **kwargs)
        self.db = db
        self.mode = "employes"
        self.mois_var = ctk.StringVar(value=MOIS[datetime.now().month - 1])
        self.annee_var = ctk.StringVar(value=str(datetime.now().year))
        self.build()
        self.refresh_list()

    def build(self):
        header = ctk.CTkFrame(self, fg_color="transparent")
        header.pack(fill="x", padx=4, pady=(4, 16))
        section_title(header, "Employés & Paie", "Personnel, masse salariale et paiements mensuels").pack(
            side="left")
        self.new_btn = primary_button(header, "+ Nouvel employé", command=self.open_form)
        self.new_btn.pack(side="right")

        tabs = ctk.CTkFrame(self, fg_color=COLORS["bg_card"], corner_radius=10, height=44)
        tabs.pack(fill="x", padx=4, pady=(0, 16))
        self.tab_emp_btn = ctk.CTkButton(
            tabs, text="👔 Employés", command=lambda: self.switch_tab("employes"),
            fg_color=COLORS["gold"], text_color="#0B1220", font=font(13, "bold"),
            corner_radius=8, height=36, width=150)
        self.tab_emp_btn.pack(side="left", padx=6, pady=4)
        self.tab_paie_btn = ctk.CTkButton(
            tabs, text="💰 Paie", command=lambda: self.switch_tab("paie"),
            fg_color="transparent", text_color=COLORS["text_secondary"], font=font(13),
            corner_radius=8, height=36, width=150)
        self.tab_paie_btn.pack(side="left", padx=6, pady=4)

        self.totals_row = ctk.CTkFrame(self, fg_color="transparent")
        self.totals_row.pack(fill="x", padx=4, pady=(0, 16))

        self.list_frame = ctk.CTkScrollableFrame(self, fg_color="transparent")
        self.list_frame.pack(fill="both", expand=True, padx=4)

    def switch_tab(self, mode):
        self.mode = mode
        if mode == "employes":
            self.tab_emp_btn.configure(fg_color=COLORS["gold"], text_color="#0B1220", font=font(13, "bold"))
            self.tab_paie_btn.configure(fg_color="transparent", text_color=COLORS["text_secondary"], font=font(13))
            self.new_btn.configure(text="+ Nouvel employé", command=self.open_form)
            self.refresh_list()
        else:
            self.tab_paie_btn.configure(fg_color=COLORS["gold"], text_color="#0B1220", font=font(13, "bold"))
            self.tab_emp_btn.configure(fg_color="transparent", text_color=COLORS["text_secondary"], font=font(13))
            self.new_btn.configure(text="🔄 Actualiser", command=self.refresh_paie)
            self.refresh_paie()

    def refresh_list(self):
        for w in self.totals_row.winfo_children():
            w.destroy()
        for w in self.list_frame.winfo_children():
            w.destroy()

        masse = self.db.fetchone(
            "SELECT COALESCE(SUM(salaire_mensuel),0) as t, COUNT(*) as c FROM employes WHERE statut='Actif'")
        for label, val, color in [
            ("Masse salariale mensuelle", f"{masse['t']:,.0f} FCFA".replace(",", " "), COLORS["gold"]),
            ("Employés actifs", str(masse["c"]), COLORS["info"]),
        ]:
            c = ctk.CTkFrame(self.totals_row, fg_color=COLORS["bg_card"], corner_radius=10,
                              border_width=1, border_color=COLORS["border"])
            c.pack(side="left", padx=(0, 10), ipady=8, ipadx=16)
            ctk.CTkLabel(c, text=label.upper(), font=font(10, "bold"),
                         text_color=COLORS["text_secondary"]).pack(anchor="w", padx=14, pady=(6, 0))
            ctk.CTkLabel(c, text=val, font=font(16, "bold"), text_color=color).pack(
                anchor="w", padx=14, pady=(0, 6))
        rows = self.db.fetchall("SELECT * FROM employes ORDER BY code")
        if not rows:
            ctk.CTkLabel(self.list_frame, text="Aucun employé enregistré.",
                         font=font(12), text_color=COLORS["text_muted"]).pack(pady=40)
            return

        header_row = ctk.CTkFrame(self.list_frame, fg_color=COLORS["bg_sidebar"], corner_radius=8, height=36)
        header_row.pack(fill="x", pady=(0, 4))
        for txt, w in [("CODE", 70), ("NOM", 220), ("POSTE", 180), ("CONTRAT", 100)]:
            ctk.CTkLabel(header_row, text=txt, font=font(10, "bold"), text_color=COLORS["gold"],
                         width=w, anchor="w").pack(side="left", padx=8)
        ctk.CTkLabel(header_row, text="SALAIRE MENSUEL", font=font(10, "bold"), text_color=COLORS["gold"],
                     anchor="e").pack(side="right", padx=16)

        for i, r in enumerate(rows):
            bg = COLORS["bg_card"] if i % 2 == 0 else COLORS["bg_dark"]
            row = ctk.CTkFrame(self.list_frame, fg_color=bg, corner_radius=8, height=44)
            row.pack(fill="x", pady=2)
            row.pack_propagate(False)
            ctk.CTkLabel(row, text=r["code"], font=font(11, "bold"), text_color=COLORS["gold"],
                         width=70, anchor="w").pack(side="left", padx=8)
            ctk.CTkLabel(row, text=r["nom"], font=font(12, "bold"), text_color=COLORS["text_primary"],
                         width=220, anchor="w").pack(side="left", padx=8)
            ctk.CTkLabel(row, text=r["poste"] or "—", font=font(11), text_color=COLORS["text_secondary"],
                         width=180, anchor="w").pack(side="left", padx=8)
            ctk.CTkLabel(row, text=r["type_contrat"] or "—", font=font(11), text_color=COLORS["text_secondary"],
                         width=100, anchor="w").pack(side="left", padx=8)
            ctk.CTkLabel(row, text=f"{r['salaire_mensuel']:,.0f} FCFA".replace(",", " "), font=font(12, "bold"),
                         text_color=COLORS["text_primary"], anchor="e").pack(side="right", padx=16)

            for w in row.winfo_children():
                w.bind("<Button-1>", lambda e, rid=r["id"]: self.open_form_edit(rid))
            row.bind("<Button-1>", lambda e, rid=r["id"]: self.open_form_edit(rid))
            row.bind("<Enter>", lambda e, w=row: w.configure(fg_color=COLORS["bg_card_hover"]))
            row.bind("<Leave>", lambda e, w=row, b=bg: w.configure(fg_color=b))

            def on_right_click(event, rid=r["id"], nom=r["nom"]):
                def do_delete():
                    def confirmed():
                        self.db.execute("DELETE FROM employes WHERE id=?", (rid,))
                        self.refresh_list()
                    confirm_delete(self, f"Supprimer {nom} ?",
                                    "Cette action est définitive.", confirmed)
                items = [
                    ("✏️ Modifier", lambda: self.open_form_edit(rid)),
                    (None, None),
                    ("🗑 Supprimer", do_delete),
                ]
                show_context_menu(row, event, items)

            for w in [row] + row.winfo_children():
                w.bind("<Button-3>", on_right_click)

    def open_form_edit(self, employe_id):
        r = self.db.fetchone("SELECT * FROM employes WHERE id=?", (employe_id,))
        self.open_form(r)

    def open_form(self, existing=None):
        dialog = ctk.CTkToplevel(self)
        dialog.title("Employé")
        dialog.geometry("420x720")
        dialog.configure(fg_color=COLORS["bg_dark"])
        dialog.transient(self)
        dialog.grab_set()
        dialog.bind("<Escape>", lambda e: dialog.destroy())

        scroll = ctk.CTkScrollableFrame(dialog, fg_color="transparent")
        scroll.pack(fill="both", expand=True)

        ctk.CTkLabel(scroll, text="Nouvel employé" if not existing else "Modifier l'employé",
                     font=font(16, "bold"), text_color=COLORS["text_primary"]).pack(pady=(24, 4))
        code_preview = existing["code"] if existing else self.db.next_code("EMP", "employes", width=2)
        ctk.CTkLabel(scroll, text=f"Code : {code_preview}", font=font(11),
                     text_color=COLORS["gold"]).pack(pady=(0, 12))

        fields = {}

        def add_field(label, key, value=""):
            ctk.CTkLabel(scroll, text=label, font=font(12), text_color=COLORS["text_secondary"],
                         anchor="w").pack(fill="x", padx=32, pady=(8, 2))
            entry = ctk.CTkEntry(scroll, height=40, corner_radius=8, fg_color=COLORS["bg_input"],
                                  border_color=COLORS["border"], font=font(13))
            entry.pack(fill="x", padx=32)
            entry.insert(0, str(value) if value else "")
            fields[key] = entry

        add_field("Nom complet *", "nom", existing["nom"] if existing else "")
        add_field("Poste", "poste", existing["poste"] if existing else "")
        add_field("Téléphone", "telephone", existing["telephone"] if existing else "")
        add_field("Salaire mensuel (FCFA)", "salaire", existing["salaire_mensuel"] if existing else "")

        ctk.CTkLabel(scroll, text="Type de contrat", font=font(12), text_color=COLORS["text_secondary"],
                     anchor="w").pack(fill="x", padx=32, pady=(8, 2))
        contrat_var = ctk.StringVar(value=existing["type_contrat"] if existing else "CDI")
        ctk.CTkOptionMenu(scroll, values=["CDI", "CDD", "Journalier", "Stage"], variable=contrat_var,
                           height=40, corner_radius=8, fg_color=COLORS["bg_input"],
                           button_color=COLORS["gold"], button_hover_color=COLORS["gold_light"],
                           text_color=COLORS["text_primary"]).pack(fill="x", padx=32)

        ctk.CTkLabel(scroll, text="Statut", font=font(12), text_color=COLORS["text_secondary"],
                     anchor="w").pack(fill="x", padx=32, pady=(8, 2))
        statut_var = ctk.StringVar(value=existing["statut"] if existing else "Actif")
        ctk.CTkOptionMenu(scroll, values=["Actif", "Inactif"], variable=statut_var,
                           height=40, corner_radius=8, fg_color=COLORS["bg_input"],
                           button_color=COLORS["gold"], button_hover_color=COLORS["gold_light"],
                           text_color=COLORS["text_primary"]).pack(fill="x", padx=32)

        def save():
            nom = fields["nom"].get().strip()
            if not nom:
                fields["nom"].configure(border_color=COLORS["danger"])
                return
            try:
                salaire = float(fields["salaire"].get().replace(" ", "") or 0)
            except ValueError:
                salaire = 0
            if existing:
                self.db.execute(
                    "UPDATE employes SET nom=?, poste=?, telephone=?, salaire_mensuel=?, type_contrat=?, "
                    "statut=? WHERE id=?",
                    (nom, fields["poste"].get(), fields["telephone"].get(), salaire, contrat_var.get(),
                     statut_var.get(), existing["id"]))
            else:
                code = self.db.next_code("EMP", "employes", width=2)
                self.db.execute(
                    "INSERT INTO employes (code, nom, poste, telephone, salaire_mensuel, type_contrat, statut) "
                    "VALUES (?,?,?,?,?,?,?)",
                    (code, nom, fields["poste"].get(), fields["telephone"].get(), salaire, contrat_var.get(),
                     statut_var.get()))
            dialog.destroy()
            self.refresh_list()

        primary_button(scroll, "Enregistrer", command=save).pack(fill="x", padx=32, pady=(24, 8))
        secondary_button(scroll, "Annuler", command=dialog.destroy).pack(fill="x", padx=32)

        if existing:
            def delete_employe():
                def do_delete():
                    self.db.move_to_corbeille("employes", existing["id"], f"Employé {existing['nom']}",
                                               "Employés & Paie")
                    dialog.destroy()
                    self.refresh_list()

                confirm_delete(dialog, f"Supprimer {existing['nom']} ?",
                                "Il restera 30 jours dans la Corbeille, restaurable si besoin. "
                                "L'historique de paie déjà enregistré n'est pas supprimé.", do_delete)

            danger_button(scroll, "Supprimer cet employé", command=delete_employe).pack(
                fill="x", padx=32, pady=(12, 20))

    # ================= ONGLET PAIE =================
    def refresh_paie(self):
        for w in self.totals_row.winfo_children():
            w.destroy()
        for w in self.list_frame.winfo_children():
            w.destroy()

        selector = ctk.CTkFrame(self.totals_row, fg_color="transparent")
        selector.pack(side="left")
        ctk.CTkLabel(selector, text="Mois :", font=font(12), text_color=COLORS["text_secondary"]).pack(
            side="left", padx=(0, 6))
        ctk.CTkOptionMenu(selector, values=MOIS, variable=self.mois_var,
                           command=lambda v: self.refresh_paie(), height=36, width=140,
                           corner_radius=8, fg_color=COLORS["bg_input"], button_color=COLORS["gold"],
                           button_hover_color=COLORS["gold_light"], text_color=COLORS["text_primary"]).pack(
            side="left", padx=(0, 12))
        ctk.CTkLabel(selector, text="Année :", font=font(12), text_color=COLORS["text_secondary"]).pack(
            side="left", padx=(0, 6))
        annee_entry = ctk.CTkEntry(selector, textvariable=self.annee_var, height=36, width=80,
                                    corner_radius=8, fg_color=COLORS["bg_input"], border_color=COLORS["border"],
                                    font=font(12))
        annee_entry.pack(side="left")
        annee_entry.bind("<Return>", lambda e: self.refresh_paie())

        employes = self.db.fetchall("SELECT * FROM employes WHERE statut='Actif' ORDER BY code")
        if not employes:
            ctk.CTkLabel(self.list_frame, text="Aucun employé actif.", font=font(12),
                         text_color=COLORS["text_muted"]).pack(pady=40)
            return

        mois = self.mois_var.get()
        try:
            annee = int(self.annee_var.get())
        except ValueError:
            annee = datetime.now().year

        header_row = ctk.CTkFrame(self.list_frame, fg_color=COLORS["bg_sidebar"], corner_radius=8, height=36)
        header_row.pack(fill="x", pady=(0, 4))
        for txt, w in [("EMPLOYÉ", 200), ("SALAIRE DÛ", 110), ("AVANCES", 110), ("NET À PAYER", 120)]:
            ctk.CTkLabel(header_row, text=txt, font=font(10, "bold"), text_color=COLORS["gold"],
                         width=w, anchor="w").pack(side="left", padx=8)
        ctk.CTkLabel(header_row, text="STATUT", font=font(10, "bold"), text_color=COLORS["gold"],
                     anchor="e").pack(side="right", padx=16)

        total_net = 0
        total_paye = 0
        for i, emp in enumerate(employes):
            paie = self.db.fetchone("SELECT * FROM paie WHERE employe_id=? AND mois=? AND annee=?",
                                     (emp["id"], mois, annee))
            salaire_du = paie["salaire_du"] if paie else emp["salaire_mensuel"]
            avances = paie["avances_versees"] if paie else 0
            net = salaire_du - avances
            statut = paie["statut"] if paie else "Non généré"
            total_net += net
            if statut == "Payé":
                total_paye += net

            bg = COLORS["bg_card"] if i % 2 == 0 else COLORS["bg_dark"]
            row = ctk.CTkFrame(self.list_frame, fg_color=bg, corner_radius=8, height=48)
            row.pack(fill="x", pady=2)
            row.pack_propagate(False)
            name_col = ctk.CTkFrame(row, fg_color="transparent", width=200)
            name_col.pack(side="left", padx=8)
            name_col.pack_propagate(False)
            ctk.CTkLabel(name_col, text=emp["nom"], font=font(12, "bold"), text_color=COLORS["text_primary"],
                         anchor="w").pack(anchor="w")
            ctk.CTkLabel(name_col, text=emp["poste"] or "—", font=font(10), text_color=COLORS["text_secondary"],
                         anchor="w").pack(anchor="w")
            ctk.CTkLabel(row, text=f"{salaire_du:,.0f}".replace(",", " "), font=font(11),
                         text_color=COLORS["text_primary"], width=110, anchor="w").pack(side="left", padx=8)
            ctk.CTkLabel(row, text=f"{avances:,.0f}".replace(",", " "), font=font(11),
                         text_color=COLORS["text_secondary"], width=110, anchor="w").pack(side="left", padx=8)
            ctk.CTkLabel(row, text=f"{net:,.0f} FCFA".replace(",", " "), font=font(12, "bold"),
                         text_color=COLORS["gold"], width=120, anchor="w").pack(side="left", padx=8)

            status_map = {"Payé": "success", "En attente": "warning", "Non généré": "neutral"}
            action_frame = ctk.CTkFrame(row, fg_color="transparent")
            action_frame.pack(side="right", padx=12)
            if statut == "Payé":
                status_badge(action_frame, "✓ Payé", "success").pack(side="right")
            else:
                secondary_button(action_frame, "💰 Payer", height=30, width=90,
                                  command=lambda e=emp, sd=salaire_du, av=avances:
                                  self._open_paie_form(e, mois, annee, sd, av)).pack(side="right")
                status_badge(action_frame, statut, status_map.get(statut, "neutral")).pack(
                    side="right", padx=(0, 8))

        summary = ctk.CTkFrame(self.list_frame, fg_color=COLORS["gold"], corner_radius=8, height=44)
        summary.pack(fill="x", pady=(6, 0))
        summary.pack_propagate(False)
        ctk.CTkLabel(summary, text=f"TOTAL {mois.upper()} {annee}", font=font(12, "bold"),
                     text_color="#0B1220").pack(side="left", padx=16)
        ctk.CTkLabel(summary, text=f"Net dû : {total_net:,.0f} FCFA — Déjà payé : {total_paye:,.0f} FCFA".replace(",", " "),
                     font=font(11, "bold"), text_color="#0B1220").pack(side="right", padx=16)

    def _open_paie_form(self, employe, mois, annee, salaire_du_defaut, avances_defaut):
        dialog = ctk.CTkToplevel(self)
        dialog.title("Paiement de salaire")
        dialog.geometry("400x460")
        dialog.configure(fg_color=COLORS["bg_dark"])
        dialog.transient(self)
        dialog.grab_set()
        dialog.bind("<Escape>", lambda e: dialog.destroy())

        ctk.CTkLabel(dialog, text=f"Payer {employe['nom']}", font=font(15, "bold"),
                     text_color=COLORS["text_primary"]).pack(pady=(24, 2))
        ctk.CTkLabel(dialog, text=f"{mois} {annee}", font=font(11), text_color=COLORS["gold"]).pack(
            pady=(0, 16))

        fields = {}

        def add_field(label, key, value):
            ctk.CTkLabel(dialog, text=label, font=font(12), text_color=COLORS["text_secondary"],
                         anchor="w").pack(fill="x", padx=32, pady=(8, 2))
            entry = ctk.CTkEntry(dialog, height=38, corner_radius=8, fg_color=COLORS["bg_input"],
                                  border_color=COLORS["border"], font=font(13))
            entry.insert(0, str(value))
            entry.pack(fill="x", padx=32)
            fields[key] = entry

        add_field("Salaire dû (FCFA)", "salaire", salaire_du_defaut)
        add_field("Avances déjà versées (FCFA)", "avances", avances_defaut)

        ctk.CTkLabel(dialog, text="Mode de paiement", font=font(12), text_color=COLORS["text_secondary"],
                     anchor="w").pack(fill="x", padx=32, pady=(8, 2))
        mode_var = ctk.StringVar(value="Espèces")
        ctk.CTkOptionMenu(dialog, values=MODE_PAIEMENT, variable=mode_var, height=38, corner_radius=8,
                           fg_color=COLORS["bg_input"], button_color=COLORS["gold"],
                           button_hover_color=COLORS["gold_light"], text_color=COLORS["text_primary"]).pack(
            fill="x", padx=32)

        def confirm_paiement():
            try:
                salaire = float(fields["salaire"].get() or 0)
                avances = float(fields["avances"].get() or 0)
            except ValueError:
                return
            net = salaire - avances
            existing = self.db.fetchone("SELECT id FROM paie WHERE employe_id=? AND mois=? AND annee=?",
                                         (employe["id"], mois, annee))
            if existing:
                self.db.execute(
                    "UPDATE paie SET salaire_du=?, avances_versees=?, net_a_payer=?, date_paiement=?, "
                    "mode_paiement=?, statut='Payé' WHERE id=?",
                    (salaire, avances, net, datetime.now().strftime("%Y-%m-%d"), mode_var.get(),
                     existing["id"]))
            else:
                self.db.execute(
                    "INSERT INTO paie (mois, annee, employe_id, salaire_du, avances_versees, net_a_payer, "
                    "date_paiement, mode_paiement, statut) VALUES (?,?,?,?,?,?,?,?, 'Payé')",
                    (mois, annee, employe["id"], salaire, avances, net,
                     datetime.now().strftime("%Y-%m-%d"), mode_var.get()))
            dialog.destroy()
            self.refresh_paie()

        primary_button(dialog, "✓ Confirmer le paiement", command=confirm_paiement).pack(
            fill="x", padx=32, pady=(20, 8))
        secondary_button(dialog, "Annuler", command=dialog.destroy).pack(fill="x", padx=32)
