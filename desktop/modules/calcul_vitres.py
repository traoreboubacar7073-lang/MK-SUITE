"""
MK Suite - Module Calcul Vitres
Calculateur : Surface = Largeur x Hauteur x Quantité, prix repris automatiquement
selon le type de vitre sélectionné (exactement comme l'onglet Excel).
"""
import os
import tempfile
import customtkinter as ctk
from tkinter import filedialog
from ui.theme import COLORS, font, title_font, card, primary_button, secondary_button, danger_button
from ui.widgets import section_title, confirm_delete
from modules.pdf_generator import generate_vitres_pdf, open_file, print_file


class CalculVitresView(ctk.CTkScrollableFrame):
    def __init__(self, parent, db, **kwargs):
        super().__init__(parent, fg_color="transparent", **kwargs)
        self.db = db
        self.build()
        self.refresh_history()

    def build(self):
        header = ctk.CTkFrame(self, fg_color="transparent")
        header.pack(fill="x", padx=4, pady=(4, 16))
        section_title(header, "Calcul Vitres",
                      "Saisis toutes tes vitres à la suite — Entrée passe au champ suivant").pack(
            side="left")
        secondary_button(header, "⚙️ Gérer les tarifs", command=self.open_tarifs_manager).pack(side="right")

        tarifs = self.db.fetchall("SELECT * FROM tarifs_vitres ORDER BY type_vitre")
        self.tarifs_map = {t["type_vitre"]: t["prix_m2"] for t in tarifs}

        # ---- Zone de saisie multi-lignes ----
        entry_card = card(self)
        entry_card.pack(fill="x", padx=4, pady=(0, 16))

        col_labels = ctk.CTkFrame(entry_card, fg_color="transparent")
        col_labels.pack(fill="x", padx=20, pady=(18, 4))
        for txt, w in [("TYPE DE VITRE", 190), ("LARGEUR (cm)", 90), ("HAUTEUR (cm)", 90), ("QTÉ", 55), ("REPÈRE", 65)]:
            ctk.CTkLabel(col_labels, text=txt, font=font(9, "bold"), text_color=COLORS["text_muted"],
                         width=w, anchor="w").pack(side="left", padx=4)
        ctk.CTkLabel(col_labels, text="MONTANT LIGNE", font=font(9, "bold"), text_color=COLORS["text_muted"],
                     anchor="e").pack(side="left", fill="x", expand=True, padx=4)
        ctk.CTkFrame(col_labels, fg_color="transparent", width=34).pack(side="left")

        self.lines_container = ctk.CTkFrame(entry_card, fg_color="transparent")
        self.lines_container.pack(fill="x", padx=20)
        self.line_widgets = []

        secondary_button(entry_card, "+ Ajouter une ligne", command=lambda: self._add_line(focus=True),
                          height=32).pack(fill="x", padx=20, pady=(6, 12))

        totals_row = ctk.CTkFrame(entry_card, fg_color=COLORS["bg_input"], corner_radius=10)
        totals_row.pack(fill="x", padx=20, pady=(0, 16))
        tot_inner = ctk.CTkFrame(totals_row, fg_color="transparent")
        tot_inner.pack(fill="x", padx=16, pady=10)
        ctk.CTkLabel(tot_inner, text="SURFACE TOTALE", font=font(9, "bold"),
                     text_color=COLORS["text_secondary"]).pack(side="left")
        self.surface_totale_lbl = ctk.CTkLabel(tot_inner, text="0.00 m²", font=font(13, "bold"),
                                                 text_color=COLORS["text_primary"])
        self.surface_totale_lbl.pack(side="left", padx=(8, 24))
        ctk.CTkLabel(tot_inner, text="MONTANT TOTAL", font=font(9, "bold"),
                     text_color=COLORS["text_secondary"]).pack(side="left")
        self.montant_totale_lbl = ctk.CTkLabel(tot_inner, text="0 FCFA", font=font(15, "bold"),
                                                 text_color=COLORS["gold"])
        self.montant_totale_lbl.pack(side="left", padx=(8, 0))

        primary_button(entry_card, "💾 Enregistrer toutes les lignes dans l'historique",
                        command=self._save_all_lines).pack(fill="x", padx=20, pady=(0, 8))
        pdf_row = ctk.CTkFrame(entry_card, fg_color="transparent")
        pdf_row.pack(fill="x", padx=20, pady=(0, 20))
        secondary_button(pdf_row, "📄 Générer le PDF", command=self._export_pdf).pack(
            side="left", fill="x", expand=True, padx=(0, 6))
        secondary_button(pdf_row, "🖨️ Imprimer", command=self._print_pdf).pack(
            side="left", fill="x", expand=True, padx=(6, 0))

        for _ in range(4):
            self._add_line()

        # ---- Historique ----
        ctk.CTkLabel(self, text="Historique des commandes", font=font(14, "bold"),
                     text_color=COLORS["text_primary"]).pack(anchor="w", pady=(0, 8), padx=4)
        self.history_frame = ctk.CTkFrame(self, fg_color="transparent")
        self.history_frame.pack(fill="x", padx=4)

    def _add_line(self, type_vitre=None, largeur="", hauteur="", quantite="1", focus=False):
        types = list(self.tarifs_map.keys()) or ["—"]
        default_type = type_vitre or (self.line_widgets[-1][0].get() if self.line_widgets else types[0])

        row = ctk.CTkFrame(self.lines_container, fg_color=COLORS["bg_input"], corner_radius=8)
        row.pack(fill="x", pady=3)

        type_var = ctk.StringVar(value=default_type if default_type in types else types[0])
        type_menu = ctk.CTkOptionMenu(row, values=types, variable=type_var, width=190, height=32,
                                       corner_radius=6, fg_color=COLORS["bg_dark"], button_color=COLORS["gold"],
                                       button_hover_color=COLORS["gold_light"], text_color=COLORS["text_primary"],
                                       font=font(11), command=lambda v: self._recalc_all())
        type_menu.pack(side="left", padx=(6, 4), pady=6)

        largeur_e = ctk.CTkEntry(row, width=90, height=32, corner_radius=6, fg_color=COLORS["bg_dark"],
                                  border_width=0, font=font(11))
        largeur_e.insert(0, largeur)
        largeur_e.pack(side="left", padx=4, pady=6)

        hauteur_e = ctk.CTkEntry(row, width=90, height=32, corner_radius=6, fg_color=COLORS["bg_dark"],
                                  border_width=0, font=font(11))
        hauteur_e.insert(0, hauteur)
        hauteur_e.pack(side="left", padx=4, pady=6)

        quantite_e = ctk.CTkEntry(row, width=55, height=32, corner_radius=6, fg_color=COLORS["bg_dark"],
                                   border_width=0, font=font(11))
        quantite_e.insert(0, quantite)
        quantite_e.pack(side="left", padx=4, pady=6)

        repere_e = ctk.CTkEntry(row, width=65, height=32, placeholder_text="N1")
        repere_e.pack(side="left", padx=4, pady=6)

        montant_lbl = ctk.CTkLabel(row, text="0 FCFA", font=font(11, "bold"), text_color=COLORS["gold"],
                                    anchor="e")
        montant_lbl.pack(side="left", fill="x", expand=True, padx=8)

        entry_tuple = [type_var, largeur_e, hauteur_e, quantite_e, montant_lbl, type_menu, repere_e]

        def remove():
            row.destroy()
            self.line_widgets.remove(entry_tuple)
            self._recalc_all()

        ctk.CTkButton(row, text="✕", width=28, height=28, corner_radius=6, fg_color="transparent",
                      hover_color=COLORS["danger"], text_color=COLORS["text_secondary"],
                      command=remove).pack(side="left", padx=(4, 6), pady=6)

        self.line_widgets.append(entry_tuple)

        def go_next(event, current=entry_tuple):
            idx = self.line_widgets.index(current)
            if idx == len(self.line_widgets) - 1:
                self._add_line(focus=True)
            else:
                self.line_widgets[idx + 1][1].focus_set()
            return "break"

        # Entrée : Largeur -> Hauteur -> Quantité -> (ligne suivante ou nouvelle ligne)
        largeur_e.bind("<Return>", lambda e: (hauteur_e.focus_set(), "break")[1])
        largeur_e.bind("<KeyRelease>", lambda e: self._recalc_all())
        hauteur_e.bind("<Return>", lambda e: (quantite_e.focus_set(), "break")[1])
        hauteur_e.bind("<KeyRelease>", lambda e: self._recalc_all())
        quantite_e.bind("<Return>", go_next)
        quantite_e.bind("<KeyRelease>", lambda e: self._recalc_all())

        if focus:
            largeur_e.focus_set()

    def _line_values(self, entry_tuple):
        type_var, largeur_e, hauteur_e, quantite_e, montant_lbl, type_menu, repere_e = entry_tuple
        try:
            largeur = float(largeur_e.get().replace(",", "."))
        except ValueError:
            largeur = 0
        try:
            hauteur = float(hauteur_e.get().replace(",", "."))
        except ValueError:
            hauteur = 0
        try:
            quantite = float(quantite_e.get().replace(",", "."))
        except ValueError:
            quantite = 0
        prix_m2 = self.tarifs_map.get(type_var.get(), 0)
        largeur /= 100
        hauteur /= 100
        surface = largeur * hauteur * quantite
        montant = surface * prix_m2
        return type_var.get(), largeur, hauteur, quantite, prix_m2, surface, montant

    def _recalc_all(self):
        total_surface = 0
        total_montant = 0
        for entry_tuple in self.line_widgets:
            *_, surface, montant = self._line_values(entry_tuple)
            entry_tuple[4].configure(text=f"{montant:,.0f} FCFA".replace(",", " "))
            total_surface += surface
            total_montant += montant
        self.surface_totale_lbl.configure(text=f"{total_surface:.3f} m²")
        self.montant_totale_lbl.configure(text=f"{total_montant:,.0f} FCFA".replace(",", " "))

    def _current_lines_data(self):
        """Retourne les lignes valides (surface > 0) actuellement saisies, prêtes pour le PDF."""
        data = []
        for entry_tuple in self.line_widgets:
            type_vitre, largeur, hauteur, quantite, prix_m2, surface, montant = self._line_values(entry_tuple)
            if surface <= 0:
                continue
            data.append({"type_vitre": type_vitre, "largeur": largeur, "hauteur": hauteur,
                         "quantite": quantite, "surface": surface, "montant": montant,
                         "repere": entry_tuple[6].get().strip()})
        return data

    def _export_pdf(self):
        lignes = self._current_lines_data()
        if not lignes:
            return
        total_surface = sum(l["surface"] for l in lignes)
        total_montant = sum(l["montant"] for l in lignes)
        path = filedialog.asksaveasfilename(defaultextension=".pdf", initialfile="Calcul_Vitres.pdf",
                                             filetypes=[("Fichier PDF", "*.pdf")])
        if not path:
            return
        generate_vitres_pdf(path, lignes, total_surface, total_montant)
        open_file(path)

    def _print_pdf(self):
        lignes = self._current_lines_data()
        if not lignes:
            return
        total_surface = sum(l["surface"] for l in lignes)
        total_montant = sum(l["montant"] for l in lignes)
        path = os.path.join(tempfile.gettempdir(), "Calcul_Vitres.pdf")
        generate_vitres_pdf(path, lignes, total_surface, total_montant)
        print_file(path)

    def _save_all_lines(self):
        saved = 0
        for entry_tuple in self.line_widgets:
            type_vitre, largeur, hauteur, quantite, prix_m2, surface, montant = self._line_values(entry_tuple)
            if surface <= 0:
                continue
            self.db.execute(
                "INSERT INTO commandes_vitres (type_vitre, largeur, hauteur, quantite, surface, "
                "prix_unitaire, montant, repere) VALUES (?,?,?,?,?,?,?,?)",
                (type_vitre, largeur, hauteur, int(quantite), surface, prix_m2, montant, entry_tuple[6].get().strip()))
            saved += 1
        if saved == 0:
            return
        # Repartir sur une saisie neuve, prete pour le prochain lot de vitres
        for w in self.lines_container.winfo_children():
            w.destroy()
        self.line_widgets = []
        for _ in range(4):
            self._add_line()
        self._recalc_all()
        self.refresh_history()

    def _refresh_tarifs_dropdown(self):
        tarifs = self.db.fetchall("SELECT * FROM tarifs_vitres ORDER BY type_vitre")
        self.tarifs_map = {t["type_vitre"]: t["prix_m2"] for t in tarifs}
        values = list(self.tarifs_map.keys()) or ["—"]
        for type_var, largeur_e, hauteur_e, quantite_e, montant_lbl, type_menu, repere_e in self.line_widgets:
            type_menu.configure(values=values)
            if type_var.get() not in self.tarifs_map and values:
                type_var.set(values[0])
        self._recalc_all()

    def open_tarifs_manager(self):
        dialog = ctk.CTkToplevel(self)
        dialog.title("Gérer les tarifs des vitres")
        dialog.geometry("420x520")
        dialog.configure(fg_color=COLORS["bg_dark"])
        dialog.transient(self)
        dialog.grab_set()
        dialog.bind("<Escape>", lambda e: dialog.destroy())

        ctk.CTkLabel(dialog, text="Tarifs des vitres (FCFA / m²)", font=font(15, "bold"),
                     text_color=COLORS["text_primary"]).pack(pady=(20, 12))

        list_frame = ctk.CTkScrollableFrame(dialog, fg_color="transparent", height=280)
        list_frame.pack(fill="both", expand=True, padx=20)

        def render_list():
            for w in list_frame.winfo_children():
                w.destroy()
            tarifs = self.db.fetchall("SELECT * FROM tarifs_vitres ORDER BY type_vitre")
            for t in tarifs:
                row = ctk.CTkFrame(list_frame, fg_color=COLORS["bg_card"], corner_radius=8)
                row.pack(fill="x", pady=3)
                ctk.CTkLabel(row, text=t["type_vitre"], font=font(12), text_color=COLORS["text_primary"],
                             anchor="w").pack(side="left", fill="x", expand=True, padx=(10, 4), pady=8)
                prix_e = ctk.CTkEntry(row, width=90, height=32, corner_radius=6,
                                       fg_color=COLORS["bg_input"], border_width=0, font=font(11))
                prix_e.insert(0, str(int(t["prix_m2"])))
                prix_e.pack(side="left", padx=4, pady=6)

                def save_prix(event=None, tid=t["id"], entry=prix_e):
                    try:
                        val = float(entry.get() or 0)
                    except ValueError:
                        return
                    self.db.execute("UPDATE tarifs_vitres SET prix_m2=? WHERE id=?", (val, tid))
                    self._refresh_tarifs_dropdown()

                prix_e.bind("<Return>", save_prix)
                prix_e.bind("<FocusOut>", save_prix)

                def delete_tarif(tid=t["id"]):
                    def do_delete():
                        self.db.execute("DELETE FROM tarifs_vitres WHERE id=?", (tid,))
                        render_list()
                        self._refresh_tarifs_dropdown()
                    confirm_delete(dialog, "Supprimer ce tarif ?", "Cette action est définitive.", do_delete)

                ctk.CTkButton(row, text="✕", width=28, height=28, corner_radius=6,
                              fg_color="transparent", hover_color=COLORS["danger"],
                              text_color=COLORS["text_secondary"], command=delete_tarif).pack(
                    side="left", padx=(4, 8), pady=6)

        render_list()

        add_row = ctk.CTkFrame(dialog, fg_color="transparent")
        add_row.pack(fill="x", padx=20, pady=(12, 0))
        new_type_e = ctk.CTkEntry(add_row, height=38, corner_radius=8, fg_color=COLORS["bg_input"],
                                   border_color=COLORS["border"], font=font(12),
                                   placeholder_text="Nouveau type (ex: FUMÉ 6mm)")
        new_type_e.pack(side="left", fill="x", expand=True, padx=(0, 6))
        new_prix_e = ctk.CTkEntry(add_row, width=90, height=38, corner_radius=8, fg_color=COLORS["bg_input"],
                                   border_color=COLORS["border"], font=font(12), placeholder_text="Prix/m²")
        new_prix_e.pack(side="left")

        def add_tarif():
            nom = new_type_e.get().strip()
            if not nom:
                return
            try:
                prix = float(new_prix_e.get() or 0)
            except ValueError:
                prix = 0
            self.db.execute("INSERT OR IGNORE INTO tarifs_vitres (type_vitre, prix_m2) VALUES (?,?)",
                             (nom, prix))
            new_type_e.delete(0, "end")
            new_prix_e.delete(0, "end")
            render_list()
            self._refresh_tarifs_dropdown()

        primary_button(dialog, "+ Ajouter ce tarif", command=add_tarif).pack(fill="x", padx=20, pady=(10, 8))
        secondary_button(dialog, "Fermer", command=dialog.destroy).pack(fill="x", padx=20, pady=(0, 20))

    def refresh_history(self):
        for w in self.history_frame.winfo_children():
            w.destroy()
        rows = self.db.fetchall("SELECT * FROM commandes_vitres ORDER BY id DESC LIMIT 100")
        if not rows:
            ctk.CTkLabel(self.history_frame, text="Aucune commande enregistrée pour le moment.",
                         font=font(12), text_color=COLORS["text_muted"]).pack(pady=40)
            return

        header_row = ctk.CTkFrame(self.history_frame, fg_color=COLORS["bg_sidebar"], corner_radius=8, height=36)
        header_row.pack(fill="x", pady=(0, 4))
        for txt, w in [("TYPE", 130), ("DIMENSIONS", 140), ("QTÉ", 50), ("SURFACE", 90)]:
            ctk.CTkLabel(header_row, text=txt, font=font(10, "bold"), text_color=COLORS["gold"],
                         width=w, anchor="w").pack(side="left", padx=8)
        ctk.CTkLabel(header_row, text="MONTANT", font=font(10, "bold"), text_color=COLORS["gold"],
                     width=110, anchor="e").pack(side="left", padx=8)
        ctk.CTkFrame(header_row, fg_color="transparent", width=30).pack(side="left")

        for i, r in enumerate(rows):
            bg = COLORS["bg_card"] if i % 2 == 0 else COLORS["bg_dark"]
            row = ctk.CTkFrame(self.history_frame, fg_color=bg, corner_radius=8, height=40)
            row.pack(fill="x", pady=1)
            row.pack_propagate(False)
            ctk.CTkLabel(row, text=(r["repere"] + " · " if r["repere"] else "") + r["type_vitre"], font=font(11, "bold"), text_color=COLORS["gold"],
                         width=130, anchor="w").pack(side="left", padx=8)
            ctk.CTkLabel(row, text=f"{r['largeur']:.2f} × {r['hauteur']:.2f} m", font=font(11),
                         text_color=COLORS["text_secondary"], width=140, anchor="w").pack(side="left", padx=8)
            ctk.CTkLabel(row, text=str(int(r["quantite"])), font=font(11),
                         text_color=COLORS["text_primary"], width=50, anchor="w").pack(side="left", padx=8)
            ctk.CTkLabel(row, text=f"{r['surface']:.3f} m²", font=font(11),
                         text_color=COLORS["text_primary"], width=90, anchor="w").pack(side="left", padx=8)
            ctk.CTkLabel(row, text=f"{r['montant']:,.0f} FCFA".replace(",", " "), font=font(11, "bold"),
                         text_color=COLORS["text_primary"], width=110, anchor="e").pack(side="left", padx=8)

            def delete_commande(cmd_id=r["id"], type_v=r["type_vitre"], montant=r["montant"]):
                def do_delete():
                    libelle = f"Vitre {type_v} ({montant:,.0f} FCFA)".replace(",", " ")
                    self.db.move_to_corbeille("commandes_vitres", cmd_id, libelle, "Calcul Vitres")
                    self.refresh_history()
                confirm_delete(self, "Supprimer cette entrée ?",
                                "Elle restera 30 jours dans la Corbeille, restaurable si besoin.", do_delete)

            ctk.CTkButton(row, text="✕", width=26, height=26, corner_radius=6,
                          fg_color="transparent", hover_color=COLORS["danger"],
                          text_color=COLORS["text_secondary"], command=delete_commande).pack(
                side="left", padx=(4, 8))
