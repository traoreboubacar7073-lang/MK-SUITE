"""
MK Suite - Module Devis & Factures
Liste des devis et factures (import Excel inclus), détail avec lignes,
et génération PDF en un clic reprenant exactement l'en-tête MK Entreprise.
"""
import os
import subprocess
import sys
import tempfile
import customtkinter as ctk
from tkinter import filedialog, ttk
from ui.theme import COLORS, font, title_font, card, primary_button, secondary_button, danger_button, search_entry
from ui.widgets import section_title, status_badge, confirm_delete, show_context_menu
from modules.pdf_generator import (generate_devis_pdf, generate_facture_pdf,
                                     generate_recu_pdf, generate_note_pdf, open_file, print_file)
from modules.whatsapp_service import numero_valide, ouvrir_conversation, reveler_dans_explorateur, ouvrir_dialogue_message
from ui.reference_lists import MODE_PAIEMENT


_open_file = open_file  # alias pour compatibilite avec le code existant


STATUT_COLORS_DEVIS = {"Accepté": "success", "Refusé": "danger", "En attente": "warning"}
STATUT_COLORS_FACT = {"Payée": "success", "Partielle": "warning", "Impayée": "danger"}


class DevisFacturesView(ctk.CTkFrame):
    def __init__(self, parent, db, initial_mode=None, focus_numero=None, **kwargs):
        super().__init__(parent, fg_color="transparent", **kwargs)
        self.db = db
        self.mode = "devis"  # ou "factures", "recus", "notes"
        self.build()
        self.refresh_list()
        if initial_mode and initial_mode != "devis":
            self.switch_tab(initial_mode)
        if focus_numero:
            self._focus_on_numero(focus_numero)

    def _focus_on_numero(self, numero):
        """Ouvre directement le detail de l'element correspondant a ce numero
        (utilise quand on arrive depuis un clic sur le tableau de bord)."""
        table_map = {"devis": "devis", "factures": "factures", "recus": "recus", "notes": "notes_client"}
        table = table_map.get(self.mode)
        if not table:
            return
        row = self.db.fetchone(f"SELECT id FROM {table} WHERE numero=?", (numero,))
        if row:
            self.show_detail(row["id"])

    def build(self):
        header = ctk.CTkFrame(self, fg_color="transparent")
        header.pack(fill="x", padx=4, pady=(4, 16))
        section_title(header, "Devis & Factures", "Consulte, crée et exporte tes documents en PDF").pack(
            side="left")
        self.new_btn = primary_button(header, "+ Nouveau devis", command=self.open_new_form)
        self.new_btn.pack(side="right")

        # Onglets Devis / Factures
        tabs = ctk.CTkFrame(self, fg_color=COLORS["bg_card"], corner_radius=10, height=44)
        tabs.pack(fill="x", padx=4, pady=(0, 12))
        self.tab_devis_btn = ctk.CTkButton(
            tabs, text="📋 Devis", command=lambda: self.switch_tab("devis"),
            fg_color=COLORS["gold"], text_color="#0B1220", font=font(13, "bold"),
            corner_radius=8, height=36, width=140)
        self.tab_devis_btn.pack(side="left", padx=6, pady=4)
        self.tab_fact_btn = ctk.CTkButton(
            tabs, text="🧾 Factures", command=lambda: self.switch_tab("factures"),
            fg_color="transparent", text_color=COLORS["text_secondary"], font=font(13),
            corner_radius=8, height=36, width=140)
        self.tab_fact_btn.pack(side="left", padx=6, pady=4)
        self.tab_recu_btn = ctk.CTkButton(
            tabs, text="🧾 Reçus", command=lambda: self.switch_tab("recus"),
            fg_color="transparent", text_color=COLORS["text_secondary"], font=font(13),
            corner_radius=8, height=36, width=140)
        self.tab_recu_btn.pack(side="left", padx=6, pady=4)
        self.tab_note_btn = ctk.CTkButton(
            tabs, text="📝 Notes", command=lambda: self.switch_tab("notes"),
            fg_color="transparent", text_color=COLORS["text_secondary"], font=font(13),
            corner_radius=8, height=36, width=140)
        self.tab_note_btn.pack(side="left", padx=6, pady=4)

        search_row = ctk.CTkFrame(self, fg_color="transparent")
        search_row.pack(fill="x", padx=4, pady=(0, 12))
        self.search_var = ctk.StringVar()
        self.search_var.trace_add("write", lambda *a: self.refresh_list())
        search_field = search_entry(search_row, self.search_var, "🔍 Rechercher un numéro, un client...")
        search_field.pack(fill="x")

        body = ctk.CTkFrame(self, fg_color="transparent")
        body.pack(fill="both", expand=True, padx=4)
        body.grid_columnconfigure(0, weight=1)
        body.grid_columnconfigure(1, weight=0)
        body.grid_rowconfigure(0, weight=1)

        self.list_frame = ctk.CTkFrame(body, fg_color="transparent")
        self.list_frame.grid(row=0, column=0, sticky="nsew", padx=(0, 8))

        self.detail_panel = ctk.CTkScrollableFrame(body, width=360, fg_color=COLORS["bg_card"],
                                                     corner_radius=14, border_width=1,
                                                     border_color=COLORS["border"])
        self.detail_panel.grid(row=0, column=1, sticky="nsew")
        self._show_empty_detail()

    def open_new_form(self):
        if self.mode == "devis":
            self._open_devis_form()
        elif self.mode == "factures":
            self.open_facture_picker()
        elif self.mode == "recus":
            self._open_recu_form()
        else:
            self._open_note_form()

    def open_facture_picker(self):
        """Point de départ pour une nouvelle facture : choisir le client, voir ses devis,
        et soit en reprendre un directement (lignes + montants pré-remplis), soit démarrer
        une facture manuelle si aucun devis ne correspond."""
        dialog = ctk.CTkToplevel(self)
        dialog.title("Nouvelle facture")
        dialog.geometry("440x420")
        dialog.configure(fg_color=COLORS["bg_dark"])
        dialog.transient(self)
        dialog.grab_set()
        dialog.bind("<Escape>", lambda e: dialog.destroy())

        scroll = ctk.CTkScrollableFrame(dialog, fg_color="transparent")
        scroll.pack(fill="both", expand=True)

        ctk.CTkLabel(scroll, text="Nouvelle facture", font=font(16, "bold"),
                     text_color=COLORS["text_primary"]).pack(pady=(24, 4))
        ctk.CTkLabel(scroll, text="Choisis le client, puis un de ses devis si tu veux le reprendre",
                     font=font(11), text_color=COLORS["text_secondary"]).pack(pady=(0, 16))

        clients = self.db.fetchall("SELECT id, nom FROM clients ORDER BY nom")
        client_map = {c["nom"]: c["id"] for c in clients}
        devis_map = {}

        ctk.CTkLabel(scroll, text="Client", font=font(12), text_color=COLORS["text_secondary"],
                     anchor="w").pack(fill="x", padx=32, pady=(0, 2))
        client_var = ctk.StringVar(value=clients[0]["nom"] if clients else "")

        def refresh_devis_list(*args):
            cid = client_map.get(client_var.get())
            devis_map.clear()
            options = ["— Aucun, facture manuelle —"]
            if cid:
                devis_rows = self.db.fetchall(
                    "SELECT * FROM devis WHERE client_id=? AND (converti_facture IS NULL OR "
                    "converti_facture NOT LIKE 'FA-%') ORDER BY id DESC", (cid,))
                for d in devis_rows:
                    label = f"{d['numero']} — {d['objet'] or 'Sans objet'} — {d['montant_ht']:,.0f} FCFA".replace(",", " ")
                    options.append(label)
                    devis_map[label] = d
            devis_menu.configure(values=options)
            devis_var.set(options[0])

        client_menu = ctk.CTkOptionMenu(scroll, values=list(client_map.keys()) or ["Aucun client"],
                                         variable=client_var, command=refresh_devis_list, height=38,
                                         corner_radius=8, fg_color=COLORS["bg_input"],
                                         button_color=COLORS["gold"], button_hover_color=COLORS["gold_light"],
                                         text_color=COLORS["text_primary"])
        client_menu.pack(fill="x", padx=32)

        ctk.CTkLabel(scroll, text="Devis de ce client", font=font(12), text_color=COLORS["text_secondary"],
                     anchor="w").pack(fill="x", padx=32, pady=(14, 2))
        devis_var = ctk.StringVar(value="— Aucun, facture manuelle —")
        devis_menu = ctk.CTkOptionMenu(scroll, values=["— Aucun, facture manuelle —"], variable=devis_var,
                                        height=38, corner_radius=8, fg_color=COLORS["bg_input"],
                                        button_color=COLORS["gold"], button_hover_color=COLORS["gold_light"],
                                        text_color=COLORS["text_primary"])
        devis_menu.pack(fill="x", padx=32)

        refresh_devis_list()

        info_lbl = ctk.CTkLabel(scroll, text="Astuce : seuls les devis pas encore facturés apparaissent ici.",
                                 font=font(10), text_color=COLORS["text_muted"],
                                 wraplength=360, justify="left")
        info_lbl.pack(fill="x", padx=32, pady=(10, 0))

        def go():
            selected_label = devis_var.get()
            chosen_devis = devis_map.get(selected_label)
            dialog.destroy()
            self._open_facture_form(from_devis=chosen_devis)

        primary_button(scroll, "Continuer →", command=go).pack(fill="x", padx=32, pady=(20, 8))
        secondary_button(scroll, "Annuler", command=dialog.destroy).pack(fill="x", padx=32, pady=(0, 20))

    def _client_picker(self, parent):
        clients = self.db.fetchall("SELECT id, nom FROM clients ORDER BY nom")
        client_map = {c["nom"]: c["id"] for c in clients}
        ctk.CTkLabel(parent, text="Client", font=font(12), text_color=COLORS["text_secondary"],
                     anchor="w").pack(fill="x", padx=32, pady=(8, 2))
        client_var = ctk.StringVar(value=clients[0]["nom"] if clients else "")
        ctk.CTkOptionMenu(parent, values=list(client_map.keys()) or ["Aucun client — ajoute-en un d'abord"],
                           variable=client_var, height=38, corner_radius=8, fg_color=COLORS["bg_input"],
                           button_color=COLORS["gold"], button_hover_color=COLORS["gold_light"],
                           text_color=COLORS["text_primary"]).pack(fill="x", padx=32)
        return client_var, client_map

    def _lines_editor(self, parent, initial_lines=None):
        """Zone dynamique pour ajouter des lignes Qté / Description / Prix unitaire.
        Comportement type Excel : 3 lignes affichées par défaut (ou les lignes existantes
        en mode édition), et appuyer sur Entrée dans la dernière ligne crée automatiquement
        la ligne suivante en y plaçant le curseur."""
        ctk.CTkLabel(parent, text="Lignes du document", font=font(12, "bold"),
                     text_color=COLORS["gold"], anchor="w").pack(fill="x", padx=32, pady=(14, 6))
        col_labels = ctk.CTkFrame(parent, fg_color="transparent")
        col_labels.pack(fill="x", padx=32)
        ctk.CTkLabel(col_labels, text="Qté", font=font(9, "bold"), text_color=COLORS["text_muted"],
                     width=45, anchor="w").pack(side="left", padx=(6, 4))
        ctk.CTkLabel(col_labels, text="Description", font=font(9, "bold"), text_color=COLORS["text_muted"],
                     anchor="w").pack(side="left", fill="x", expand=True, padx=4)
        ctk.CTkLabel(col_labels, text="Prix unit.", font=font(9, "bold"), text_color=COLORS["text_muted"],
                     width=90, anchor="w").pack(side="left", padx=4)
        ctk.CTkFrame(col_labels, fg_color="transparent", width=34).pack(side="left")

        lines_container = ctk.CTkFrame(parent, fg_color="transparent")
        lines_container.pack(fill="x", padx=32)
        line_widgets = []

        def add_line(qte="1", desc="", prix="0", focus=False):
            row = ctk.CTkFrame(lines_container, fg_color=COLORS["bg_input"], corner_radius=8)
            row.pack(fill="x", pady=3)
            qte_e = ctk.CTkEntry(row, width=45, height=32, corner_radius=6, fg_color=COLORS["bg_dark"],
                                  border_width=0, font=font(11))
            qte_e.insert(0, qte)
            qte_e.pack(side="left", padx=(6, 4), pady=6)
            desc_e = ctk.CTkEntry(row, height=32, corner_radius=6, fg_color=COLORS["bg_dark"],
                                   border_width=0, font=font(11), placeholder_text="Description")
            desc_e.insert(0, desc)
            desc_e.pack(side="left", fill="x", expand=True, padx=4, pady=6)
            prix_e = ctk.CTkEntry(row, width=90, height=32, corner_radius=6, fg_color=COLORS["bg_dark"],
                                   border_width=0, font=font(11), placeholder_text="Prix unit.")
            prix_e.insert(0, prix)
            prix_e.pack(side="left", padx=4, pady=6)

            def remove():
                row.destroy()
                line_widgets.remove((qte_e, desc_e, prix_e))

            del_btn = ctk.CTkButton(row, text="✕", width=28, height=28, corner_radius=6,
                                     fg_color="transparent", hover_color=COLORS["danger"],
                                     text_color=COLORS["text_secondary"], command=remove)
            del_btn.pack(side="left", padx=(4, 6), pady=6)
            entry_tuple = (qte_e, desc_e, prix_e)
            line_widgets.append(entry_tuple)

            def go_next(event, current=entry_tuple):
                idx = line_widgets.index(current)
                if idx == len(line_widgets) - 1:
                    add_line(focus=True)
                else:
                    line_widgets[idx + 1][0].focus_set()
                return "break"

            # Entrée depuis n'importe quel champ de la ligne -> ligne suivante (ou nouvelle ligne)
            qte_e.bind("<Return>", lambda e: (desc_e.focus_set(), "break")[1])
            desc_e.bind("<Return>", lambda e: (prix_e.focus_set(), "break")[1])
            prix_e.bind("<Return>", go_next)

            if focus:
                qte_e.focus_set()

        if initial_lines:
            for q, d, p in initial_lines:
                add_line(str(q), d, str(p))
            add_line()  # une ligne vide en plus pour continuer à saisir
        else:
            for _ in range(3):
                add_line()
        add_btn = secondary_button(parent, "+ Ajouter une ligne", command=lambda: add_line(focus=True),
                                    height=32)
        add_btn.pack(fill="x", padx=32, pady=(6, 0))
        return line_widgets

    def _open_devis_form(self, existing=None):
        dialog = ctk.CTkToplevel(self)
        dialog.title("Devis")
        dialog.geometry("480x740")
        dialog.configure(fg_color=COLORS["bg_dark"])
        dialog.transient(self)
        dialog.grab_set()
        dialog.bind("<Escape>", lambda e: dialog.destroy())

        scroll = ctk.CTkScrollableFrame(dialog, fg_color="transparent")
        scroll.pack(fill="both", expand=True)

        ctk.CTkLabel(scroll, text="Modifier le devis" if existing else "Nouveau devis",
                     font=font(16, "bold"), text_color=COLORS["text_primary"]).pack(pady=(20, 4))
        numero_actuel = existing["numero"] if existing else self.db.next_numero("DV", "devis")
        ctk.CTkLabel(scroll, text=f"N° : {numero_actuel}", font=font(11),
                     text_color=COLORS["gold"]).pack(pady=(0, 12))

        clients = self.db.fetchall("SELECT id, nom FROM clients ORDER BY nom")
        client_map = {c["nom"]: c["id"] for c in clients}
        default_client = None
        if existing and existing["client_id"]:
            row = self.db.fetchone("SELECT nom FROM clients WHERE id=?", (existing["client_id"],))
            default_client = row["nom"] if row else None
        ctk.CTkLabel(scroll, text="Client", font=font(12), text_color=COLORS["text_secondary"],
                     anchor="w").pack(fill="x", padx=32, pady=(8, 2))
        client_var = ctk.StringVar(value=default_client or (clients[0]["nom"] if clients else ""))
        client_menu_form = ctk.CTkOptionMenu(
            scroll, values=list(client_map.keys()) or ["Aucun client — ajoute-en un d'abord"],
            variable=client_var, height=38, corner_radius=8, fg_color=COLORS["bg_input"],
            button_color=COLORS["gold"], button_hover_color=COLORS["gold_light"],
            text_color=COLORS["text_primary"])

        # "Devis rapide" : pour un nouveau devis seulement (pas en modification —
        # là, le client existe déjà forcément), on peut taper directement le nom
        # d'un client au lieu de passer par le module Clients — un vrai client
        # est quand même créé en base au moment d'enregistrer (avec un code
        # CL-xxx normal), seule l'étape du formulaire complet est court-circuitée.
        quick_frame = None
        quick_nom_e = quick_tel_e = None
        quick_var = ctk.BooleanVar(value=not existing and not clients)
        if not existing:
            def toggle_quick():
                if quick_var.get():
                    client_menu_form.pack_forget()
                    quick_frame.pack(fill="x", padx=32, pady=(0, 2))
                else:
                    quick_frame.pack_forget()
                    client_menu_form.pack(fill="x", padx=32)

            ctk.CTkCheckBox(scroll, text="+ Nouveau client rapide (sans passer par le module Clients)",
                             variable=quick_var, command=toggle_quick, font=font(11),
                             text_color=COLORS["text_secondary"], fg_color=COLORS["gold"],
                             hover_color=COLORS["gold_light"]).pack(fill="x", padx=32, pady=(6, 6))
            quick_frame = ctk.CTkFrame(scroll, fg_color="transparent")
            quick_nom_e = ctk.CTkEntry(quick_frame, height=38, corner_radius=8, fg_color=COLORS["bg_input"],
                                        border_color=COLORS["border"], font=font(13),
                                        placeholder_text="Nom du client")
            quick_nom_e.pack(fill="x", pady=(0, 6))
            quick_tel_e = ctk.CTkEntry(quick_frame, height=38, corner_radius=8, fg_color=COLORS["bg_input"],
                                        border_color=COLORS["border"], font=font(13),
                                        placeholder_text="Téléphone (optionnel — utile pour l'envoi WhatsApp)")
            quick_tel_e.pack(fill="x")

        if quick_var.get():
            quick_frame.pack(fill="x", padx=32, pady=(0, 2))
        else:
            client_menu_form.pack(fill="x", padx=32)

        ctk.CTkLabel(scroll, text="Objet", font=font(12), text_color=COLORS["text_secondary"],
                     anchor="w").pack(fill="x", padx=32, pady=(10, 2))
        objet_e = ctk.CTkEntry(scroll, height=38, corner_radius=8, fg_color=COLORS["bg_input"],
                                border_color=COLORS["border"], font=font(13))
        if existing:
            objet_e.insert(0, existing["objet"] or "")
        objet_e.pack(fill="x", padx=32)

        ctk.CTkLabel(scroll, text="Validité (jours)", font=font(12), text_color=COLORS["text_secondary"],
                     anchor="w").pack(fill="x", padx=32, pady=(10, 2))
        validite_e = ctk.CTkEntry(scroll, height=38, corner_radius=8, fg_color=COLORS["bg_input"],
                                   border_color=COLORS["border"], font=font(13))
        validite_e.insert(0, str(existing["validite_jours"]) if existing else "30")
        validite_e.pack(fill="x", padx=32)

        ctk.CTkLabel(scroll, text="Statut", font=font(12), text_color=COLORS["text_secondary"],
                     anchor="w").pack(fill="x", padx=32, pady=(10, 2))
        statut_var = ctk.StringVar(value=existing["statut"] if existing else "En attente")
        ctk.CTkOptionMenu(scroll, values=["En attente", "Accepté", "Refusé"], variable=statut_var,
                           height=38, corner_radius=8, fg_color=COLORS["bg_input"],
                           button_color=COLORS["gold"], button_hover_color=COLORS["gold_light"],
                           text_color=COLORS["text_primary"]).pack(fill="x", padx=32)

        ctk.CTkLabel(scroll, text="Appliquer la TVA (18%) — sera repris automatiquement lors de la "
                                    "conversion en facture", font=font(11), text_color=COLORS["text_secondary"],
                     anchor="w", wraplength=400, justify="left").pack(fill="x", padx=32, pady=(10, 2))
        tva_defaut = "Oui" if (existing["appliquer_tva"] if existing else 1) else "Non"
        tva_var = ctk.StringVar(value=tva_defaut)
        ctk.CTkOptionMenu(scroll, values=["Oui", "Non"], variable=tva_var, height=38, corner_radius=8,
                           fg_color=COLORS["bg_input"], button_color=COLORS["gold"],
                           button_hover_color=COLORS["gold_light"],
                           text_color=COLORS["text_primary"]).pack(fill="x", padx=32)

        initial_lines = None
        if existing:
            lignes_ex = self.db.fetchall("SELECT * FROM lignes_devis WHERE devis_numero=?",
                                          (existing["numero"],))
            initial_lines = [(l["quantite"], l["description"], l["prix_unitaire"]) for l in lignes_ex]
        line_widgets = self._lines_editor(scroll, initial_lines=initial_lines)

        def save():
            client_id = None
            if not existing and quick_var.get():
                nom_rapide = quick_nom_e.get().strip()
                if not nom_rapide:
                    return
                code = self.db.next_code("CL", "clients")
                client_id = self.db.execute(
                    "INSERT INTO clients (code, nom, telephone, type_client, statut) VALUES (?,?,?,?,?)",
                    (code, nom_rapide, quick_tel_e.get().strip(), "Particulier", "Actif"))
            else:
                if not client_map:
                    return
                client_id = client_map.get(client_var.get())
            lignes_valides = [(q, d, p) for (q, d, p) in
                               [(qe.get(), de.get(), pe.get()) for qe, de, pe in line_widgets]
                               if d.strip()]
            if not lignes_valides:
                return
            from datetime import datetime, timedelta
            try:
                validite = int(validite_e.get() or 30)
            except ValueError:
                validite = 30
            date_limite = (datetime.now() + timedelta(days=validite)).strftime("%Y-%m-%d")
            total_ht = 0
            for q, d, p in lignes_valides:
                try:
                    qf, pf = float(q or 1), float(p or 0)
                except ValueError:
                    qf, pf = 1, 0
                total_ht += qf * pf

            if existing:
                numero = existing["numero"]
                self.db.execute(
                    "UPDATE devis SET client_id=?, objet=?, montant_ht=?, validite_jours=?, "
                    "date_limite=?, statut=?, appliquer_tva=? WHERE id=?",
                    (client_id, objet_e.get(), total_ht, validite,
                     date_limite, statut_var.get(), 1 if tva_var.get() == "Oui" else 0, existing["id"]))
                self.db.execute("DELETE FROM lignes_devis WHERE devis_numero=?", (numero,))
            else:
                numero = self.db.next_numero("DV", "devis")
                self.db.execute(
                    "INSERT INTO devis (numero, client_id, objet, montant_ht, statut, validite_jours, "
                    "date_limite, appliquer_tva) VALUES (?,?,?,?,?,?,?,?)",
                    (numero, client_id, objet_e.get(), total_ht, statut_var.get(),
                     validite, date_limite, 1 if tva_var.get() == "Oui" else 0))

            for q, d, p in lignes_valides:
                try:
                    qf, pf = float(q or 1), float(p or 0)
                except ValueError:
                    qf, pf = 1, 0
                self.db.execute(
                    "INSERT INTO lignes_devis (devis_numero, quantite, description, prix_unitaire, "
                    "total_ligne) VALUES (?,?,?,?,?)", (numero, qf, d, pf, qf * pf))
            dialog.destroy()
            self.refresh_list()
            if existing:
                self._show_devis_detail(existing["id"])

        primary_button(scroll, "Enregistrer les modifications" if existing else "Enregistrer le devis",
                        command=save).pack(fill="x", padx=32, pady=(20, 8))
        secondary_button(scroll, "Annuler", command=dialog.destroy).pack(fill="x", padx=32, pady=(0, 20))


    def _open_facture_form(self, existing=None, from_devis=None):
        dialog = ctk.CTkToplevel(self)
        dialog.title("Facture")
        dialog.geometry("480x820")
        dialog.configure(fg_color=COLORS["bg_dark"])
        dialog.transient(self)
        dialog.grab_set()
        dialog.bind("<Escape>", lambda e: dialog.destroy())

        scroll = ctk.CTkScrollableFrame(dialog, fg_color="transparent")
        scroll.pack(fill="both", expand=True)

        ctk.CTkLabel(scroll, text="Modifier la facture" if existing else "Nouvelle facture",
                     font=font(16, "bold"), text_color=COLORS["text_primary"]).pack(pady=(20, 4))
        numero_actuel = existing["numero"] if existing else self.db.next_numero("FA", "factures")
        ctk.CTkLabel(scroll, text=f"N° : {numero_actuel}", font=font(11),
                     text_color=COLORS["gold"]).pack(pady=(0, 4))
        if from_devis:
            badge_row = ctk.CTkFrame(scroll, fg_color=COLORS["bg_input"], corner_radius=8)
            badge_row.pack(padx=32, pady=(4, 8), fill="x")
            ctk.CTkLabel(badge_row, text=f"📋 Générée à partir du devis {from_devis['numero']} — "
                                          f"lignes et montants déjà repris, il ne reste que la réduction "
                                          f"à ajuster si besoin.",
                         font=font(10), text_color=COLORS["gold"], wraplength=380,
                         justify="left").pack(padx=10, pady=8)

        clients = self.db.fetchall("SELECT id, nom FROM clients ORDER BY nom")
        client_map = {c["nom"]: c["id"] for c in clients}
        default_client = None
        if existing and existing["client_id"]:
            row = self.db.fetchone("SELECT nom FROM clients WHERE id=?", (existing["client_id"],))
            default_client = row["nom"] if row else None
        elif from_devis and from_devis["client_id"]:
            row = self.db.fetchone("SELECT nom FROM clients WHERE id=?", (from_devis["client_id"],))
            default_client = row["nom"] if row else None
        ctk.CTkLabel(scroll, text="Client", font=font(12), text_color=COLORS["text_secondary"],
                     anchor="w").pack(fill="x", padx=32, pady=(8, 2))
        client_var = ctk.StringVar(value=default_client or (clients[0]["nom"] if clients else ""))
        ctk.CTkOptionMenu(scroll, values=list(client_map.keys()) or ["Aucun client — ajoute-en un d'abord"],
                           variable=client_var, height=38, corner_radius=8, fg_color=COLORS["bg_input"],
                           button_color=COLORS["gold"], button_hover_color=COLORS["gold_light"],
                           text_color=COLORS["text_primary"]).pack(fill="x", padx=32)

        ctk.CTkLabel(scroll, text="Description", font=font(12), text_color=COLORS["text_secondary"],
                     anchor="w").pack(fill="x", padx=32, pady=(10, 2))
        desc_e = ctk.CTkEntry(scroll, height=38, corner_radius=8, fg_color=COLORS["bg_input"],
                               border_color=COLORS["border"], font=font(13))
        if existing:
            desc_e.insert(0, existing["description"] or "")
        elif from_devis:
            desc_e.insert(0, from_devis["objet"] or "")
        desc_e.pack(fill="x", padx=32)

        initial_lines = None
        if existing:
            lignes_ex = self.db.fetchall("SELECT * FROM lignes_facture WHERE facture_numero=?",
                                          (existing["numero"],))
            initial_lines = [(l["quantite"], l["description"], l["prix_unitaire"]) for l in lignes_ex]
        elif from_devis:
            lignes_ex = self.db.fetchall("SELECT * FROM lignes_devis WHERE devis_numero=?",
                                          (from_devis["numero"],))
            initial_lines = [(l["quantite"], l["description"], l["prix_unitaire"]) for l in lignes_ex]
        line_widgets = self._lines_editor(scroll, initial_lines=initial_lines)

        ctk.CTkLabel(scroll, text="Appliquer la TVA (18%) sur cette facture ?", font=font(12),
                     text_color=COLORS["text_secondary"], anchor="w").pack(fill="x", padx=32, pady=(14, 2))
        tva_defaut = "Oui"
        if existing:
            tva_defaut = "Oui" if (existing["tva"] or 0) > 0 else "Non"
        elif from_devis:
            tva_defaut = "Oui" if from_devis["appliquer_tva"] else "Non"
        tva_var = ctk.StringVar(value=tva_defaut)
        ctk.CTkOptionMenu(scroll, values=["Oui", "Non"], variable=tva_var, height=38, corner_radius=8,
                           fg_color=COLORS["bg_input"], button_color=COLORS["gold"],
                           button_hover_color=COLORS["gold_light"],
                           text_color=COLORS["text_primary"]).pack(fill="x", padx=32)

        row2 = ctk.CTkFrame(scroll, fg_color="transparent")
        row2.pack(fill="x", padx=32, pady=(14, 0))
        reduc_col = ctk.CTkFrame(row2, fg_color="transparent")
        reduc_col.pack(side="left", fill="x", expand=True, padx=(0, 6))
        ctk.CTkLabel(reduc_col, text="Réduction (%)", font=font(12), text_color=COLORS["text_secondary"],
                     anchor="w").pack(fill="x")
        reduc_e = ctk.CTkEntry(reduc_col, height=38, corner_radius=8, fg_color=COLORS["bg_input"],
                                border_color=COLORS["border"], font=font(13))
        reduc_e.insert(0, str(existing["reduction_pct"]) if existing else "0")
        reduc_e.pack(fill="x")

        avance_col = ctk.CTkFrame(row2, fg_color="transparent")
        avance_col.pack(side="left", fill="x", expand=True, padx=(6, 0))
        ctk.CTkLabel(avance_col, text="Avance reçue (FCFA)", font=font(12), text_color=COLORS["text_secondary"],
                     anchor="w").pack(fill="x")
        avance_e = ctk.CTkEntry(avance_col, height=38, corner_radius=8, fg_color=COLORS["bg_input"],
                                 border_color=COLORS["border"], font=font(13))
        avance_e.insert(0, str(existing["avance_recue"]) if existing else "0")
        avance_e.pack(fill="x")

        ctk.CTkLabel(scroll, text="Mode de paiement", font=font(12), text_color=COLORS["text_secondary"],
                     anchor="w").pack(fill="x", padx=32, pady=(10, 2))
        mode_var = ctk.StringVar(value=(existing["mode_paiement"] if existing and existing["mode_paiement"]
                                         else "Espèces"))
        ctk.CTkOptionMenu(scroll, values=MODE_PAIEMENT,
                           variable=mode_var, height=38, corner_radius=8, fg_color=COLORS["bg_input"],
                           button_color=COLORS["gold"], button_hover_color=COLORS["gold_light"],
                           text_color=COLORS["text_primary"]).pack(fill="x", padx=32)

        ctk.CTkLabel(scroll, text="Statut (rempli automatiquement selon l'avance, "
                                    "modifiable si besoin)", font=font(11), text_color=COLORS["text_secondary"],
                     anchor="w", wraplength=400, justify="left").pack(fill="x", padx=32, pady=(10, 2))
        statut_var = ctk.StringVar(value=existing["statut"] if existing else "Impayée")
        statut_menu = ctk.CTkOptionMenu(scroll, values=["Impayée", "Partielle", "Payée"], variable=statut_var,
                           height=38, corner_radius=8, fg_color=COLORS["bg_input"],
                           button_color=COLORS["gold"], button_hover_color=COLORS["gold_light"],
                           text_color=COLORS["text_primary"])
        statut_menu.pack(fill="x", padx=32)

        def suggest_statut(event=None):
            try:
                av = float(avance_e.get() or 0)
            except ValueError:
                av = 0
            if av <= 0:
                statut_var.set("Impayée")
            else:
                statut_var.set("Partielle")
        avance_e.bind("<KeyRelease>", suggest_statut)

        def save():
            if not client_map:
                return
            lignes_valides = [(qe.get(), de.get(), pe.get()) for qe, de, pe in line_widgets
                               if de.get().strip()]
            if not lignes_valides:
                return
            total_ht = 0
            for q, d, p in lignes_valides:
                try:
                    qf, pf = float(q or 1), float(p or 0)
                except ValueError:
                    qf, pf = 1, 0
                total_ht += qf * pf
            try:
                reduc_pct = float(reduc_e.get() or 0)
                avance = float(avance_e.get() or 0)
            except ValueError:
                reduc_pct, avance = 0, 0
            montant_ht_net = total_ht * (1 - reduc_pct / 100)
            tva = montant_ht_net * 0.18 if tva_var.get() == "Oui" else 0
            montant_ttc = montant_ht_net + tva
            reste = max(montant_ttc - avance, 0)
            statut = statut_var.get()

            if existing:
                numero = existing["numero"]
                self.db.execute(
                    "UPDATE factures SET client_id=?, description=?, montant_ht=?, reduction_pct=?, "
                    "montant_ht_net=?, tva=?, montant_ttc=?, avance_recue=?, reste_a_payer=?, "
                    "statut=?, mode_paiement=? WHERE id=?",
                    (client_map.get(client_var.get()), desc_e.get(), total_ht, reduc_pct,
                     montant_ht_net, tva, montant_ttc, avance, reste, statut, mode_var.get(),
                     existing["id"]))
                self.db.execute("DELETE FROM lignes_facture WHERE facture_numero=?", (numero,))
            else:
                numero = self.db.next_numero("FA", "factures")
                devis_numero_source = from_devis["numero"] if from_devis else None
                self.db.execute(
                    "INSERT INTO factures (numero, devis_numero, client_id, description, montant_ht, "
                    "reduction_pct, montant_ht_net, tva, montant_ttc, avance_recue, reste_a_payer, "
                    "statut, mode_paiement) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
                    (numero, devis_numero_source, client_map.get(client_var.get()), desc_e.get(), total_ht,
                     reduc_pct, montant_ht_net, tva, montant_ttc, avance, reste, statut, mode_var.get()))
                if from_devis:
                    self.db.execute("UPDATE devis SET converti_facture=? WHERE id=?",
                                     (numero, from_devis["id"]))

            for q, d, p in lignes_valides:
                try:
                    qf, pf = float(q or 1), float(p or 0)
                except ValueError:
                    qf, pf = 1, 0
                self.db.execute(
                    "INSERT INTO lignes_facture (facture_numero, quantite, description, prix_unitaire, "
                    "total_ligne) VALUES (?,?,?,?,?)", (numero, qf, d, pf, qf * pf))
            dialog.destroy()
            self.refresh_list()
            if existing:
                self._show_facture_detail(existing["id"])

        primary_button(scroll, "Enregistrer les modifications" if existing else "Enregistrer la facture",
                        command=save).pack(fill="x", padx=32, pady=(20, 8))
        secondary_button(scroll, "Annuler", command=dialog.destroy).pack(fill="x", padx=32, pady=(0, 20))

    def _open_recu_form(self, existing=None):
        dialog = ctk.CTkToplevel(self)
        dialog.title("Reçu")
        dialog.geometry("440x580")
        dialog.configure(fg_color=COLORS["bg_dark"])
        dialog.transient(self)
        dialog.grab_set()
        dialog.bind("<Escape>", lambda e: dialog.destroy())

        scroll = ctk.CTkScrollableFrame(dialog, fg_color="transparent")
        scroll.pack(fill="both", expand=True)

        ctk.CTkLabel(scroll, text="Modifier le reçu" if existing else "Nouveau reçu",
                     font=font(16, "bold"), text_color=COLORS["text_primary"]).pack(pady=(24, 4))
        numero_actuel = existing["numero"] if existing else self.db.next_numero("RC", "recus")
        ctk.CTkLabel(scroll, text=f"N° : {numero_actuel}", font=font(11),
                     text_color=COLORS["gold"]).pack(pady=(0, 12))

        clients = self.db.fetchall("SELECT id, nom FROM clients ORDER BY nom")
        client_map = {c["nom"]: c["id"] for c in clients}
        default_client = None
        if existing and existing["client_id"]:
            row = self.db.fetchone("SELECT nom FROM clients WHERE id=?", (existing["client_id"],))
            default_client = row["nom"] if row else None
        ctk.CTkLabel(scroll, text="Client", font=font(12), text_color=COLORS["text_secondary"],
                     anchor="w").pack(fill="x", padx=32, pady=(8, 2))
        client_var = ctk.StringVar(value=default_client or (clients[0]["nom"] if clients else ""))
        ctk.CTkOptionMenu(scroll, values=list(client_map.keys()) or ["Aucun client — ajoute-en un d'abord"],
                           variable=client_var, height=38, corner_radius=8, fg_color=COLORS["bg_input"],
                           button_color=COLORS["gold"], button_hover_color=COLORS["gold_light"],
                           text_color=COLORS["text_primary"]).pack(fill="x", padx=32)

        factures = self.db.fetchall("SELECT numero FROM factures ORDER BY id DESC")
        ctk.CTkLabel(scroll, text="Facture liée (optionnel)", font=font(12), text_color=COLORS["text_secondary"],
                     anchor="w").pack(fill="x", padx=32, pady=(10, 2))
        fact_var = ctk.StringVar(value=(existing["facture_numero"] if existing and existing["facture_numero"]
                                         else "Aucune"))
        ctk.CTkOptionMenu(scroll, values=["Aucune"] + [f["numero"] for f in factures], variable=fact_var,
                           height=38, corner_radius=8, fg_color=COLORS["bg_input"],
                           button_color=COLORS["gold"], button_hover_color=COLORS["gold_light"],
                           text_color=COLORS["text_primary"]).pack(fill="x", padx=32)

        fields = {}

        def add_field(label, key, value=""):
            ctk.CTkLabel(scroll, text=label, font=font(12), text_color=COLORS["text_secondary"],
                         anchor="w").pack(fill="x", padx=32, pady=(10, 2))
            entry = ctk.CTkEntry(scroll, height=38, corner_radius=8, fg_color=COLORS["bg_input"],
                                  border_color=COLORS["border"], font=font(13))
            entry.insert(0, value)
            entry.pack(fill="x", padx=32)
            fields[key] = entry

        add_field("Motif", "motif", existing["motif"] if existing else "")
        add_field("Montant reçu (FCFA)", "montant", str(existing["montant_recu"]) if existing else "")
        add_field("Reçu par", "recu_par", existing["recu_par"] if existing else "")

        ctk.CTkLabel(scroll, text="Mode de paiement", font=font(12), text_color=COLORS["text_secondary"],
                     anchor="w").pack(fill="x", padx=32, pady=(10, 2))
        mode_var = ctk.StringVar(value=(existing["mode_paiement"] if existing and existing["mode_paiement"]
                                         else "Espèces"))
        ctk.CTkOptionMenu(scroll, values=MODE_PAIEMENT,
                           variable=mode_var, height=38, corner_radius=8, fg_color=COLORS["bg_input"],
                           button_color=COLORS["gold"], button_hover_color=COLORS["gold_light"],
                           text_color=COLORS["text_primary"]).pack(fill="x", padx=32)

        def save():
            if not client_map:
                return
            try:
                montant = float(fields["montant"].get() or 0)
            except ValueError:
                return
            fact_liee = None if fact_var.get() == "Aucune" else fact_var.get()
            if existing:
                self.db.execute(
                    "UPDATE recus SET client_id=?, facture_numero=?, motif=?, montant_recu=?, "
                    "mode_paiement=?, recu_par=? WHERE id=?",
                    (client_map.get(client_var.get()), fact_liee, fields["motif"].get(), montant,
                     mode_var.get(), fields["recu_par"].get(), existing["id"]))
            else:
                numero = self.db.next_numero("RC", "recus")
                self.db.execute(
                    "INSERT INTO recus (numero, client_id, facture_numero, motif, montant_recu, "
                    "mode_paiement, recu_par) VALUES (?,?,?,?,?,?,?)",
                    (numero, client_map.get(client_var.get()), fact_liee, fields["motif"].get(), montant,
                     mode_var.get(), fields["recu_par"].get()))
            dialog.destroy()
            self.refresh_list()
            if existing:
                self._show_recu_detail(existing["id"])

        primary_button(scroll, "Enregistrer les modifications" if existing else "Enregistrer le reçu",
                        command=save).pack(fill="x", padx=32, pady=(20, 8))
        secondary_button(scroll, "Annuler", command=dialog.destroy).pack(fill="x", padx=32, pady=(0, 20))

    def _open_note_form(self, existing=None):
        dialog = ctk.CTkToplevel(self)
        dialog.title("Note")
        dialog.geometry("440x540")
        dialog.configure(fg_color=COLORS["bg_dark"])
        dialog.transient(self)
        dialog.grab_set()
        dialog.bind("<Escape>", lambda e: dialog.destroy())

        scroll = ctk.CTkScrollableFrame(dialog, fg_color="transparent")
        scroll.pack(fill="both", expand=True)

        ctk.CTkLabel(scroll, text="Modifier la note" if existing else "Nouvelle note",
                     font=font(16, "bold"), text_color=COLORS["text_primary"]).pack(pady=(24, 12))

        clients = self.db.fetchall("SELECT id, nom FROM clients ORDER BY nom")
        client_map = {c["nom"]: c["id"] for c in clients}
        default_client = None
        if existing and existing["client_id"]:
            row = self.db.fetchone("SELECT nom FROM clients WHERE id=?", (existing["client_id"],))
            default_client = row["nom"] if row else None
        ctk.CTkLabel(scroll, text="Client", font=font(12), text_color=COLORS["text_secondary"],
                     anchor="w").pack(fill="x", padx=32, pady=(0, 2))
        client_var = ctk.StringVar(value=default_client or (clients[0]["nom"] if clients else ""))
        ctk.CTkOptionMenu(scroll, values=list(client_map.keys()) or ["Aucun client — ajoute-en un d'abord"],
                           variable=client_var, height=38, corner_radius=8, fg_color=COLORS["bg_input"],
                           button_color=COLORS["gold"], button_hover_color=COLORS["gold_light"],
                           text_color=COLORS["text_primary"]).pack(fill="x", padx=32)

        fields = {}

        def add_field(label, key, value=""):
            ctk.CTkLabel(scroll, text=label, font=font(12), text_color=COLORS["text_secondary"],
                         anchor="w").pack(fill="x", padx=32, pady=(10, 2))
            entry = ctk.CTkEntry(scroll, height=38, corner_radius=8, fg_color=COLORS["bg_input"],
                                  border_color=COLORS["border"], font=font(13))
            entry.insert(0, value)
            entry.pack(fill="x", padx=32)
            fields[key] = entry

        add_field("Objet", "objet", existing["objet"] if existing else "")

        ctk.CTkLabel(scroll, text="Contenu", font=font(12), text_color=COLORS["text_secondary"],
                     anchor="w").pack(fill="x", padx=32, pady=(10, 2))
        contenu_box = ctk.CTkTextbox(scroll, height=120, corner_radius=8, fg_color=COLORS["bg_input"],
                                      font=font(13))
        if existing:
            contenu_box.insert("1.0", existing["contenu"] or "")
        contenu_box.pack(fill="x", padx=32)

        add_field("Rédigé par", "redige_par", existing["redige_par"] if existing else "")

        def save():
            if not client_map:
                return
            if existing:
                self.db.execute(
                    "UPDATE notes_client SET client_id=?, objet=?, contenu=?, redige_par=? WHERE id=?",
                    (client_map.get(client_var.get()), fields["objet"].get(),
                     contenu_box.get("1.0", "end").strip(), fields["redige_par"].get(), existing["id"]))
            else:
                numero = self.db.next_numero("NT", "notes_client")
                self.db.execute(
                    "INSERT INTO notes_client (numero, client_id, objet, contenu, redige_par) "
                    "VALUES (?,?,?,?,?)",
                    (numero, client_map.get(client_var.get()), fields["objet"].get(),
                     contenu_box.get("1.0", "end").strip(), fields["redige_par"].get()))
            dialog.destroy()
            self.refresh_list()
            if existing:
                self._show_note_detail(existing["id"])

        primary_button(scroll, "Enregistrer les modifications" if existing else "Enregistrer la note",
                        command=save).pack(fill="x", padx=32, pady=(20, 8))
        secondary_button(scroll, "Annuler", command=dialog.destroy).pack(fill="x", padx=32, pady=(0, 20))

    def switch_tab(self, mode):
        self.mode = mode
        buttons = {"devis": self.tab_devis_btn, "factures": self.tab_fact_btn,
                   "recus": self.tab_recu_btn, "notes": self.tab_note_btn}
        for key, btn in buttons.items():
            if key == mode:
                btn.configure(fg_color=COLORS["gold"], text_color="#0B1220", font=font(13, "bold"))
            else:
                btn.configure(fg_color="transparent", text_color=COLORS["text_secondary"], font=font(13))
        new_labels = {"devis": "+ Nouveau devis", "factures": "+ Nouvelle facture",
                      "recus": "+ Nouveau reçu", "notes": "+ Nouvelle note"}
        self.new_btn.configure(text=new_labels[mode])
        self._show_empty_detail()
        self.refresh_list()

    def _show_empty_detail(self):
        for w in self.detail_panel.winfo_children():
            w.destroy()
        icon = "📋" if self.mode == "devis" else "🧾"
        ctk.CTkLabel(self.detail_panel, text=icon, font=font(40)).pack(pady=(60, 10))
        ctk.CTkLabel(self.detail_panel, text="Sélectionne un document\npour voir le détail",
                     font=font(13), text_color=COLORS["text_secondary"], justify="center").pack()

    def _style_treeview(self):
        style = ttk.Style()
        try:
            style.theme_use("clam")
        except Exception:
            pass
        style.configure("MK.Treeview",
                         background=COLORS["bg_card"], fieldbackground=COLORS["bg_card"],
                         foreground=COLORS["text_primary"], rowheight=34, borderwidth=0,
                         font=("Segoe UI", 11))
        style.configure("MK.Treeview.Heading",
                         background=COLORS["bg_sidebar"], foreground=COLORS["gold"],
                         font=("Segoe UI", 10, "bold"), borderwidth=0, relief="flat")
        style.map("MK.Treeview",
                  background=[("selected", COLORS["bg_card_hover"])],
                  foreground=[("selected", COLORS["gold"])])
        style.layout("MK.Treeview", [('MK.Treeview.treearea', {'sticky': 'nswe'})])

    def refresh_list(self):
        for w in self.list_frame.winfo_children():
            w.destroy()
        query = self.search_var.get().strip()

        if self.mode == "devis":
            sql = ("SELECT d.*, c.nom as client_nom FROM devis d "
                   "LEFT JOIN clients c ON c.id = d.client_id ")
            if query:
                sql += "WHERE d.numero LIKE ? OR c.nom LIKE ? ORDER BY d.id DESC"
                rows = self.db.fetchall(sql, (f"%{query}%", f"%{query}%"))
            else:
                sql += "ORDER BY d.id DESC"
                rows = self.db.fetchall(sql)
        elif self.mode == "factures":
            sql = ("SELECT f.*, c.nom as client_nom FROM factures f "
                   "LEFT JOIN clients c ON c.id = f.client_id ")
            if query:
                sql += "WHERE f.numero LIKE ? OR c.nom LIKE ? ORDER BY f.id DESC"
                rows = self.db.fetchall(sql, (f"%{query}%", f"%{query}%"))
            else:
                sql += "ORDER BY f.id DESC"
                rows = self.db.fetchall(sql)

        elif self.mode == "recus":
            sql = ("SELECT r.*, c.nom as client_nom FROM recus r "
                   "LEFT JOIN clients c ON c.id = r.client_id ")
            if query:
                sql += "WHERE r.numero LIKE ? OR c.nom LIKE ? ORDER BY r.id DESC"
                rows = self.db.fetchall(sql, (f"%{query}%", f"%{query}%"))
            else:
                sql += "ORDER BY r.id DESC"
                rows = self.db.fetchall(sql)
        else:  # notes
            sql = ("SELECT n.*, c.nom as client_nom FROM notes_client n "
                   "LEFT JOIN clients c ON c.id = n.client_id ")
            if query:
                sql += "WHERE n.objet LIKE ? OR c.nom LIKE ? ORDER BY n.id DESC"
                rows = self.db.fetchall(sql, (f"%{query}%", f"%{query}%"))
            else:
                sql += "ORDER BY n.id DESC"
                rows = self.db.fetchall(sql)

        if not rows:
            label = {"devis": "devis", "factures": "facture", "recus": "reçu",
                      "notes": "note"}[self.mode]
            ctk.CTkLabel(self.list_frame, text=f"Aucun{'e' if label=='note' else ''} {label} trouvé{'e' if label=='note' else ''}.",
                         font=font(12), text_color=COLORS["text_muted"]).pack(pady=40)
            return

        self._style_treeview()
        self._rows_by_id = {r["id"]: r for r in rows}

        tree_frame = ctk.CTkFrame(self.list_frame, fg_color=COLORS["bg_card"], corner_radius=10)
        tree_frame.pack(fill="both", expand=True)

        columns = ("numero", "client", "info", "statut")
        tree = ttk.Treeview(tree_frame, columns=columns, show="headings", style="MK.Treeview",
                             selectmode="browse")
        tree.heading("numero", text="N°")
        tree.heading("client", text="CLIENT")
        tree.heading("info", text="DATE / MONTANT")
        tree.heading("statut", text="STATUT")
        tree.column("numero", width=130, anchor="w")
        tree.column("client", width=240, anchor="w")
        tree.column("info", width=220, anchor="w")
        tree.column("statut", width=120, anchor="w")

        for r in rows:
            num_text = r["numero"] or "—"
            client_nom = r["client_nom"] or "Client non renseigné"
            if self.mode == "devis":
                info = f"{(r['date_devis'] or '')[:10]} · {r['montant_ht']:,.0f} FCFA".replace(",", " ")
                statut = r["statut"]
            elif self.mode == "factures":
                info = f"{(r['date_facture'] or '')[:10]} · {r['montant_ttc']:,.0f} FCFA".replace(",", " ")
                statut = r["statut"]
            elif self.mode == "recus":
                info = f"{(r['date_recu'] or '')[:10]} · {r['montant_recu']:,.0f} FCFA".replace(",", " ")
                statut = ""
            else:
                info = f"{(r['date_note'] or '')[:10]} · {r['objet'] or ''}"
                statut = ""
            tree.insert("", "end", iid=str(r["id"]), values=(num_text, client_nom, info, statut))

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
            row_id = int(row_iid)
            r = self._rows_by_id.get(row_id)
            if not r:
                return
            items = [(f"👁 Voir le détail", lambda: self.show_detail(row_id))]
            if self.mode == "devis":
                items.append(("📄 Générer le PDF", lambda:
                               self._export_devis(self.db.fetchone("SELECT * FROM devis WHERE id=?", (row_id,)),
                                                   self.db.fetchone("SELECT * FROM clients WHERE id=?", (r["client_id"],)) if r["client_id"] else None,
                                                   self.db.fetchall("SELECT * FROM lignes_devis WHERE devis_numero=?", (r["numero"],)))))
                items.append(("🖨️ Imprimer", lambda:
                               self._print_devis(self.db.fetchone("SELECT * FROM devis WHERE id=?", (row_id,)),
                                                  self.db.fetchone("SELECT * FROM clients WHERE id=?", (r["client_id"],)) if r["client_id"] else None,
                                                  self.db.fetchall("SELECT * FROM lignes_devis WHERE devis_numero=?", (r["numero"],)))))
                items.append((None, None))
                items.append(("🗑 Supprimer", lambda: self._delete_devis(row_id)))
            elif self.mode == "factures":
                items.append(("📄 Générer le PDF", lambda:
                               self._export_facture(self.db.fetchone("SELECT * FROM factures WHERE id=?", (row_id,)),
                                                     self.db.fetchone("SELECT * FROM clients WHERE id=?", (r["client_id"],)) if r["client_id"] else None,
                                                     self.db.fetchall("SELECT * FROM lignes_facture WHERE facture_numero=?", (r["numero"],)))))
                items.append(("🖨️ Imprimer", lambda:
                               self._print_facture(self.db.fetchone("SELECT * FROM factures WHERE id=?", (row_id,)),
                                                    self.db.fetchone("SELECT * FROM clients WHERE id=?", (r["client_id"],)) if r["client_id"] else None,
                                                    self.db.fetchall("SELECT * FROM lignes_facture WHERE facture_numero=?", (r["numero"],)))))
                items.append((None, None))
                items.append(("🗑 Supprimer", lambda: self._delete_facture(row_id)))
            elif self.mode == "recus":
                items.append(("📄 Générer le PDF", lambda:
                               self._export_recu(self.db.fetchone("SELECT * FROM recus WHERE id=?", (row_id,)),
                                                  self.db.fetchone("SELECT * FROM clients WHERE id=?", (r["client_id"],)) if r["client_id"] else None)))
                items.append(("🖨️ Imprimer", lambda:
                               self._print_recu(self.db.fetchone("SELECT * FROM recus WHERE id=?", (row_id,)),
                                                 self.db.fetchone("SELECT * FROM clients WHERE id=?", (r["client_id"],)) if r["client_id"] else None)))
                items.append((None, None))
                items.append(("🗑 Supprimer", lambda: self._delete_recu(row_id)))
            else:
                items.append(("📄 Générer le PDF", lambda:
                               self._export_note(self.db.fetchone("SELECT * FROM notes_client WHERE id=?", (row_id,)),
                                                  self.db.fetchone("SELECT * FROM clients WHERE id=?", (r["client_id"],)) if r["client_id"] else None)))
                items.append(("🖨️ Imprimer", lambda:
                               self._print_note(self.db.fetchone("SELECT * FROM notes_client WHERE id=?", (row_id,)),
                                                 self.db.fetchone("SELECT * FROM clients WHERE id=?", (r["client_id"],)) if r["client_id"] else None)))
                items.append((None, None))
                items.append(("🗑 Supprimer", lambda: self._delete_note(row_id)))
            show_context_menu(tree, event, items)

        tree.bind("<Button-3>", on_right_click)

        vsb = ttk.Scrollbar(tree_frame, orient="vertical", command=tree.yview)
        tree.configure(yscrollcommand=vsb.set)
        tree.pack(side="left", fill="both", expand=True, padx=(1, 0), pady=1)
        vsb.pack(side="right", fill="y")

    def show_detail(self, row_id):
        if self.mode == "devis":
            self._show_devis_detail(row_id)
        elif self.mode == "factures":
            self._show_facture_detail(row_id)
        elif self.mode == "recus":
            self._show_recu_detail(row_id)
        else:
            self._show_note_detail(row_id)

    def _show_devis_detail(self, devis_id):
        r = self.db.fetchone("SELECT * FROM devis WHERE id=?", (devis_id,))
        if not r:
            return
        client = self.db.fetchone("SELECT * FROM clients WHERE id=?", (r["client_id"],)) if r["client_id"] else None
        lignes = self.db.fetchall("SELECT * FROM lignes_devis WHERE devis_numero=?", (r["numero"],))

        for w in self.detail_panel.winfo_children():
            w.destroy()

        head = ctk.CTkFrame(self.detail_panel, fg_color="transparent")
        head.pack(fill="x", padx=24, pady=(24, 12))
        ctk.CTkLabel(head, text=r["numero"], font=font(16, "bold"),
                     text_color=COLORS["gold"]).pack(anchor="w")
        ctk.CTkLabel(head, text=client["nom"] if client else "Client non renseigné", font=font(13),
                     text_color=COLORS["text_primary"]).pack(anchor="w", pady=(2, 6))
        status_badge(head, r["statut"], STATUT_COLORS_DEVIS.get(r["statut"], "neutral")).pack(anchor="w")

        info_card = ctk.CTkFrame(self.detail_panel, fg_color=COLORS["bg_input"], corner_radius=10)
        info_card.pack(fill="x", padx=24, pady=8)
        for label, val in [("Objet", r["objet"] or "—"), ("Date", (r["date_devis"] or "")[:10]),
                            ("Validité", f"{r['validite_jours']} jours")]:
            row = ctk.CTkFrame(info_card, fg_color="transparent")
            row.pack(fill="x", padx=12, pady=4)
            ctk.CTkLabel(row, text=label, font=font(11), text_color=COLORS["text_secondary"]).pack(side="left")
            ctk.CTkLabel(row, text=val, font=font(11, "bold"), text_color=COLORS["text_primary"]).pack(side="right")
        ctk.CTkFrame(info_card, fg_color="transparent", height=8).pack()

        # ---- Contenu complet des lignes — visible sans passer par Modifier ou PDF ----
        if lignes:
            ctk.CTkLabel(self.detail_panel, text=f"Contenu du devis ({len(lignes)} ligne(s))",
                         font=font(11, "bold"), text_color=COLORS["gold"], anchor="w").pack(
                fill="x", padx=24, pady=(10, 4))
            lignes_card = ctk.CTkFrame(self.detail_panel, fg_color=COLORS["bg_input"], corner_radius=10)
            lignes_card.pack(fill="x", padx=24, pady=(0, 4))
            for l in lignes:
                lrow = ctk.CTkFrame(lignes_card, fg_color="transparent")
                lrow.pack(fill="x", padx=12, pady=6)
                ctk.CTkLabel(lrow, text=f"{l['quantite']:g} × {l['description']}", font=font(11),
                             text_color=COLORS["text_primary"], anchor="w", wraplength=240,
                             justify="left").pack(anchor="w")
                sub = ctk.CTkFrame(lrow, fg_color="transparent")
                sub.pack(fill="x")
                ctk.CTkLabel(sub, text=f"{l['prix_unitaire']:,.0f} FCFA / unité".replace(",", " "),
                             font=font(10), text_color=COLORS["text_secondary"]).pack(side="left")
                ctk.CTkLabel(sub, text=f"{l['total_ligne']:,.0f} FCFA".replace(",", " "),
                             font=font(10, "bold"), text_color=COLORS["gold"]).pack(side="right")
            ctk.CTkFrame(lignes_card, fg_color="transparent", height=6).pack()

        total_card = ctk.CTkFrame(self.detail_panel, fg_color=COLORS["gold"], corner_radius=10)
        total_card.pack(fill="x", padx=24, pady=8)
        ctk.CTkLabel(total_card, text="MONTANT HT", font=font(11, "bold"), text_color="#0B1220").pack(
            pady=(10, 0))
        ctk.CTkLabel(total_card, text=f"{r['montant_ht']:,.0f} FCFA".replace(",", " "),
                     font=font(18, "bold"), text_color="#0B1220").pack(pady=(0, 10))

        btn_row = ctk.CTkFrame(self.detail_panel, fg_color="transparent")
        btn_row.pack(fill="x", padx=24, pady=(16, 20))
        primary_button(btn_row, "📄 Générer le PDF",
                        command=lambda: self._export_devis(r, client, lignes)).pack(fill="x", pady=4)
        secondary_button(btn_row, "🖨️ Imprimer",
                        command=lambda: self._print_devis(r, client, lignes)).pack(fill="x", pady=4)
        primary_button(btn_row, "💬 Envoyer par WhatsApp",
                        command=lambda: self._whatsapp_devis(r, client, lignes),
                        fg_color="#25D366", hover_color="#1FAE56", text_color="white").pack(fill="x", pady=4)
        secondary_button(btn_row, "✏️ Modifier",
                          command=lambda: self._open_devis_form(existing=r)).pack(fill="x", pady=2)
        if r["converti_facture"] and r["converti_facture"].startswith("FA-"):
            secondary_button(btn_row, f"✓ Converti en {r['converti_facture']}",
                              command=None, state="disabled", height=32).pack(fill="x", pady=2)
        elif r["statut"] == "Accepté":
            primary_button(btn_row, "🔄 Convertir en facture",
                            command=lambda: self._convert_to_facture(r, lignes),
                            fg_color=COLORS["success"], hover_color=COLORS["success"]).pack(fill="x", pady=4)
        for statut in ["Accepté", "Refusé", "En attente"]:
            if statut != r["statut"]:
                secondary_button(btn_row, f"Marquer « {statut} »",
                                  command=lambda s=statut, did=devis_id: self._update_devis_statut(did, s),
                                  height=32).pack(fill="x", pady=2)
        danger_button(btn_row, "Supprimer ce devis",
                      command=lambda: self._delete_devis(devis_id)).pack(fill="x", pady=(8, 0))

    def _convert_to_facture(self, devis_row, lignes):
        """Transforme un devis accepté en facture, en reprenant les lignes et en
        appliquant la TVA 18% uniquement si le devis a été créé avec cette option."""
        numero_facture = self.db.next_numero("FA", "factures")
        montant_ht = devis_row["montant_ht"]
        tva = montant_ht * 0.18 if devis_row["appliquer_tva"] else 0
        montant_ttc = montant_ht + tva
        self.db.execute(
            "INSERT INTO factures (numero, devis_numero, client_id, description, montant_ht, "
            "reduction_pct, montant_ht_net, tva, montant_ttc, avance_recue, reste_a_payer, statut) "
            "VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
            (numero_facture, devis_row["numero"], devis_row["client_id"], devis_row["objet"],
             montant_ht, 0, montant_ht, tva, montant_ttc, 0, montant_ttc, "Impayée"))
        for l in lignes:
            self.db.execute(
                "INSERT INTO lignes_facture (facture_numero, quantite, description, prix_unitaire, "
                "total_ligne) VALUES (?,?,?,?,?)",
                (numero_facture, l["quantite"], l["description"], l["prix_unitaire"], l["total_ligne"]))
        self.db.execute("UPDATE devis SET converti_facture=? WHERE id=?",
                         (numero_facture, devis_row["id"]))
        self.refresh_list()
        self._show_devis_detail(devis_row["id"])

    def _update_devis_statut(self, devis_id, statut):
        self.db.execute("UPDATE devis SET statut=? WHERE id=?", (statut, devis_id))
        self.refresh_list()
        self._show_devis_detail(devis_id)

    def _delete_devis(self, devis_id):
        r = self.db.fetchone("SELECT numero FROM devis WHERE id=?", (devis_id,))
        numero = r["numero"] if r else ""

        def do_delete():
            self.db.move_to_corbeille("devis", devis_id, f"Devis {numero}", "Devis & Factures")
            self.refresh_list()
            self._show_empty_detail()

        confirm_delete(self, f"Supprimer le devis {numero} ?",
                        "Il restera 30 jours dans la Corbeille, restaurable si besoin.",
                        do_delete)

    def _show_facture_detail(self, facture_id):
        r = self.db.fetchone("SELECT * FROM factures WHERE id=?", (facture_id,))
        if not r:
            return
        client = self.db.fetchone("SELECT * FROM clients WHERE id=?", (r["client_id"],)) if r["client_id"] else None
        lignes = self.db.fetchall("SELECT * FROM lignes_facture WHERE facture_numero=?", (r["numero"],))

        for w in self.detail_panel.winfo_children():
            w.destroy()

        head = ctk.CTkFrame(self.detail_panel, fg_color="transparent")
        head.pack(fill="x", padx=24, pady=(24, 12))
        ctk.CTkLabel(head, text=r["numero"], font=font(16, "bold"),
                     text_color=COLORS["gold"]).pack(anchor="w")
        ctk.CTkLabel(head, text=client["nom"] if client else "Client non renseigné", font=font(13),
                     text_color=COLORS["text_primary"]).pack(anchor="w", pady=(2, 6))
        status_badge(head, r["statut"], STATUT_COLORS_FACT.get(r["statut"], "neutral")).pack(anchor="w")

        info_card = ctk.CTkFrame(self.detail_panel, fg_color=COLORS["bg_input"], corner_radius=10)
        info_card.pack(fill="x", padx=24, pady=8)
        for label, val in [
            ("Date", (r["date_facture"] or "")[:10]),
            ("Montant HT", f"{r['montant_ht']:,.0f} FCFA".replace(",", " ")),
            ("TVA (18%)", f"{r['tva']:,.0f} FCFA".replace(",", " ")),
            ("Avance reçue", f"{r['avance_recue']:,.0f} FCFA".replace(",", " ")),
        ]:
            row = ctk.CTkFrame(info_card, fg_color="transparent")
            row.pack(fill="x", padx=12, pady=4)
            ctk.CTkLabel(row, text=label, font=font(11), text_color=COLORS["text_secondary"]).pack(side="left")
            ctk.CTkLabel(row, text=val, font=font(11, "bold"), text_color=COLORS["text_primary"]).pack(side="right")
        ctk.CTkFrame(info_card, fg_color="transparent", height=8).pack()

        if lignes:
            ctk.CTkLabel(self.detail_panel, text=f"Contenu de la facture ({len(lignes)} ligne(s))",
                         font=font(11, "bold"), text_color=COLORS["gold"], anchor="w").pack(
                fill="x", padx=24, pady=(2, 4))
            lignes_card = ctk.CTkFrame(self.detail_panel, fg_color=COLORS["bg_input"], corner_radius=10)
            lignes_card.pack(fill="x", padx=24, pady=(0, 4))
            for l in lignes:
                lrow = ctk.CTkFrame(lignes_card, fg_color="transparent")
                lrow.pack(fill="x", padx=12, pady=6)
                ctk.CTkLabel(lrow, text=f"{l['quantite']:g} × {l['description']}", font=font(11),
                             text_color=COLORS["text_primary"], anchor="w", wraplength=240,
                             justify="left").pack(anchor="w")
                sub = ctk.CTkFrame(lrow, fg_color="transparent")
                sub.pack(fill="x")
                ctk.CTkLabel(sub, text=f"{l['prix_unitaire']:,.0f} FCFA / unité".replace(",", " "),
                             font=font(10), text_color=COLORS["text_secondary"]).pack(side="left")
                ctk.CTkLabel(sub, text=f"{l['total_ligne']:,.0f} FCFA".replace(",", " "),
                             font=font(10, "bold"), text_color=COLORS["gold"]).pack(side="right")
            ctk.CTkFrame(lignes_card, fg_color="transparent", height=6).pack()

        reste = r["reste_a_payer"]
        total_card = ctk.CTkFrame(self.detail_panel,
                                   fg_color=COLORS["danger"] if reste > 0 else COLORS["success"],
                                   corner_radius=10)
        total_card.pack(fill="x", padx=24, pady=8)
        label_txt = "RESTE À PAYER" if reste > 0 else "SOLDÉE"
        ctk.CTkLabel(total_card, text=label_txt, font=font(11, "bold"), text_color="#0B1220").pack(
            pady=(10, 0))
        ctk.CTkLabel(total_card, text=f"{reste:,.0f} FCFA".replace(",", " "),
                     font=font(18, "bold"), text_color="#0B1220").pack(pady=(0, 10))

        btn_row = ctk.CTkFrame(self.detail_panel, fg_color="transparent")
        btn_row.pack(fill="x", padx=24, pady=(16, 20))
        primary_button(btn_row, "📄 Générer le PDF",
                        command=lambda: self._export_facture(r, client, lignes)).pack(fill="x", pady=4)
        secondary_button(btn_row, "🖨️ Imprimer",
                        command=lambda: self._print_facture(r, client, lignes)).pack(fill="x", pady=4)
        primary_button(btn_row, "💬 Envoyer par WhatsApp",
                        command=lambda: self._whatsapp_facture(r, client, lignes),
                        fg_color="#25D366", hover_color="#1FAE56", text_color="white").pack(fill="x", pady=4)
        secondary_button(btn_row, "✏️ Modifier",
                          command=lambda: self._open_facture_form(existing=r)).pack(fill="x", pady=2)
        if reste > 0:
            primary_button(btn_row, "💰 Enregistrer un paiement",
                            command=lambda: self._open_paiement_form(facture_id, reste),
                            fg_color=COLORS["success"], hover_color=COLORS["success"]).pack(fill="x", pady=4)
        danger_button(btn_row, "Supprimer cette facture",
                      command=lambda: self._delete_facture(facture_id)).pack(fill="x", pady=(8, 0))

    def _open_paiement_form(self, facture_id, reste_actuel):
        dialog = ctk.CTkToplevel(self)
        dialog.title("Enregistrer un paiement")
        dialog.geometry("380x280")
        dialog.configure(fg_color=COLORS["bg_dark"])
        dialog.transient(self)
        dialog.grab_set()
        dialog.bind("<Escape>", lambda e: dialog.destroy())

        ctk.CTkLabel(dialog, text="Enregistrer un paiement", font=font(15, "bold"),
                     text_color=COLORS["text_primary"]).pack(pady=(24, 4))
        ctk.CTkLabel(dialog, text=f"Reste à payer actuel : {reste_actuel:,.0f} FCFA".replace(",", " "),
                     font=font(12), text_color=COLORS["text_secondary"]).pack(pady=(0, 16))

        ctk.CTkLabel(dialog, text="Montant reçu (FCFA)", font=font(12), text_color=COLORS["text_secondary"],
                     anchor="w").pack(fill="x", padx=32, pady=(0, 2))
        montant_e = ctk.CTkEntry(dialog, height=40, corner_radius=8, fg_color=COLORS["bg_input"],
                                  border_color=COLORS["border"], font=font(13))
        montant_e.insert(0, str(int(reste_actuel)))
        montant_e.pack(fill="x", padx=32)

        def confirm():
            try:
                montant = float(montant_e.get() or 0)
            except ValueError:
                return
            r = self.db.fetchone("SELECT * FROM factures WHERE id=?", (facture_id,))
            nouvelle_avance = r["avance_recue"] + montant
            nouveau_reste = max(r["montant_ttc"] - nouvelle_avance, 0)
            statut = "Payée" if nouveau_reste == 0 else "Partielle"
            self.db.execute(
                "UPDATE factures SET avance_recue=?, reste_a_payer=?, statut=? WHERE id=?",
                (nouvelle_avance, nouveau_reste, statut, facture_id))
            dialog.destroy()
            self.refresh_list()
            self._show_facture_detail(facture_id)

        primary_button(dialog, "Confirmer le paiement", command=confirm).pack(fill="x", padx=32, pady=(20, 8))
        secondary_button(dialog, "Annuler", command=dialog.destroy).pack(fill="x", padx=32)

    def _delete_facture(self, facture_id):
        r = self.db.fetchone("SELECT numero FROM factures WHERE id=?", (facture_id,))
        numero = r["numero"] if r else ""

        def do_delete():
            self.db.move_to_corbeille("factures", facture_id, f"Facture {numero}", "Devis & Factures")
            self.refresh_list()
            self._show_empty_detail()

        confirm_delete(self, f"Supprimer la facture {numero} ?",
                        "Elle restera 30 jours dans la Corbeille, restaurable si besoin.",
                        do_delete)

    def _show_recu_detail(self, recu_id):
        r = self.db.fetchone("SELECT * FROM recus WHERE id=?", (recu_id,))
        if not r:
            return
        client = self.db.fetchone("SELECT * FROM clients WHERE id=?", (r["client_id"],)) if r["client_id"] else None

        for w in self.detail_panel.winfo_children():
            w.destroy()

        head = ctk.CTkFrame(self.detail_panel, fg_color="transparent")
        head.pack(fill="x", padx=24, pady=(24, 12))
        ctk.CTkLabel(head, text=r["numero"], font=font(16, "bold"),
                     text_color=COLORS["gold"]).pack(anchor="w")
        ctk.CTkLabel(head, text=client["nom"] if client else "Client non renseigné", font=font(13),
                     text_color=COLORS["text_primary"]).pack(anchor="w", pady=(2, 6))

        info_card = ctk.CTkFrame(self.detail_panel, fg_color=COLORS["bg_input"], corner_radius=10)
        info_card.pack(fill="x", padx=24, pady=8)
        for label, val in [("Date", (r["date_recu"] or "")[:10]), ("Motif", r["motif"] or "—"),
                            ("Facture liée", r["facture_numero"] or "—"),
                            ("Mode de paiement", r["mode_paiement"] or "—"),
                            ("Reçu par", r["recu_par"] or "—")]:
            row = ctk.CTkFrame(info_card, fg_color="transparent")
            row.pack(fill="x", padx=12, pady=4)
            ctk.CTkLabel(row, text=label, font=font(11), text_color=COLORS["text_secondary"]).pack(side="left")
            ctk.CTkLabel(row, text=val, font=font(11, "bold"), text_color=COLORS["text_primary"]).pack(side="right")
        ctk.CTkFrame(info_card, fg_color="transparent", height=8).pack()

        total_card = ctk.CTkFrame(self.detail_panel, fg_color=COLORS["gold"], corner_radius=10)
        total_card.pack(fill="x", padx=24, pady=8)
        ctk.CTkLabel(total_card, text="MONTANT REÇU", font=font(11, "bold"), text_color="#0B1220").pack(
            pady=(10, 0))
        ctk.CTkLabel(total_card, text=f"{r['montant_recu']:,.0f} FCFA".replace(",", " "),
                     font=font(18, "bold"), text_color="#0B1220").pack(pady=(0, 10))

        btn_row = ctk.CTkFrame(self.detail_panel, fg_color="transparent")
        btn_row.pack(fill="x", padx=24, pady=(16, 20))
        primary_button(btn_row, "📄 Générer le PDF",
                        command=lambda: self._export_recu(r, client)).pack(fill="x", pady=4)
        secondary_button(btn_row, "🖨️ Imprimer",
                        command=lambda: self._print_recu(r, client)).pack(fill="x", pady=4)
        primary_button(btn_row, "💬 Envoyer par WhatsApp",
                        command=lambda: self._whatsapp_recu(r, client),
                        fg_color="#25D366", hover_color="#1FAE56", text_color="white").pack(fill="x", pady=4)
        secondary_button(btn_row, "✏️ Modifier",
                          command=lambda: self._open_recu_form(existing=r)).pack(fill="x", pady=2)
        danger_button(btn_row, "Supprimer ce reçu",
                      command=lambda: self._delete_recu(recu_id)).pack(fill="x", pady=(8, 0))

    def _delete_recu(self, recu_id):
        r = self.db.fetchone("SELECT numero FROM recus WHERE id=?", (recu_id,))
        numero = r["numero"] if r else "reçu"

        def do_delete():
            self.db.move_to_corbeille("recus", recu_id, f"Reçu {numero}", "Devis & Factures")
            self.refresh_list()
            self._show_empty_detail()

        confirm_delete(self, "Supprimer ce reçu ?",
                        "Il restera 30 jours dans la Corbeille, restaurable si besoin.", do_delete)

    def _show_note_detail(self, note_id):
        r = self.db.fetchone("SELECT * FROM notes_client WHERE id=?", (note_id,))
        if not r:
            return
        client = self.db.fetchone("SELECT * FROM clients WHERE id=?", (r["client_id"],)) if r["client_id"] else None

        for w in self.detail_panel.winfo_children():
            w.destroy()

        head = ctk.CTkFrame(self.detail_panel, fg_color="transparent")
        head.pack(fill="x", padx=24, pady=(24, 12))
        ctk.CTkLabel(head, text=r["numero"] or "Note", font=font(16, "bold"),
                     text_color=COLORS["gold"]).pack(anchor="w")
        ctk.CTkLabel(head, text=client["nom"] if client else "Client non renseigné", font=font(13),
                     text_color=COLORS["text_primary"]).pack(anchor="w", pady=(2, 6))
        ctk.CTkLabel(head, text=r["objet"] or "", font=font(12), text_color=COLORS["text_secondary"]).pack(
            anchor="w")

        content_card = ctk.CTkFrame(self.detail_panel, fg_color=COLORS["bg_input"], corner_radius=10)
        content_card.pack(fill="x", padx=24, pady=12)
        ctk.CTkLabel(content_card, text=r["contenu"] or "—", font=font(12), wraplength=280,
                     justify="left", text_color=COLORS["text_primary"]).pack(padx=14, pady=14, anchor="w")

        btn_row = ctk.CTkFrame(self.detail_panel, fg_color="transparent")
        btn_row.pack(fill="x", padx=24, pady=(16, 20))
        primary_button(btn_row, "📄 Générer le PDF",
                        command=lambda: self._export_note(r, client)).pack(fill="x", pady=4)
        secondary_button(btn_row, "🖨️ Imprimer",
                        command=lambda: self._print_note(r, client)).pack(fill="x", pady=4)
        secondary_button(btn_row, "✏️ Modifier",
                          command=lambda: self._open_note_form(existing=r)).pack(fill="x", pady=2)
        danger_button(btn_row, "Supprimer cette note",
                      command=lambda: self._delete_note(note_id)).pack(fill="x", pady=(8, 0))

    def _delete_note(self, note_id):
        r = self.db.fetchone("SELECT numero, objet FROM notes_client WHERE id=?", (note_id,))
        libelle = f"Note {r['numero'] or ''} — {r['objet'] or ''}".strip() if r else "Note"

        def do_delete():
            self.db.move_to_corbeille("notes_client", note_id, libelle, "Devis & Factures")
            self.refresh_list()
            self._show_empty_detail()

        confirm_delete(self, "Supprimer cette note ?",
                        "Elle restera 30 jours dans la Corbeille, restaurable si besoin.", do_delete)

    def _export_recu(self, recu_row, client_row):
        default_name = f"{recu_row['numero']}.pdf"
        path = filedialog.asksaveasfilename(defaultextension=".pdf", initialfile=default_name,
                                             filetypes=[("Fichier PDF", "*.pdf")])
        if not path:
            return
        generate_recu_pdf(path, recu_row, client_row)
        _open_file(path)

    def _export_note(self, note_row, client_row):
        default_name = f"{note_row['numero'] or 'note'}.pdf"
        path = filedialog.asksaveasfilename(defaultextension=".pdf", initialfile=default_name,
                                             filetypes=[("Fichier PDF", "*.pdf")])
        if not path:
            return
        generate_note_pdf(path, note_row, client_row)
        _open_file(path)

    def _export_devis(self, devis_row, client_row, lignes):
        default_name = f"{devis_row['numero']}.pdf"
        path = filedialog.asksaveasfilename(defaultextension=".pdf", initialfile=default_name,
                                             filetypes=[("Fichier PDF", "*.pdf")])
        if not path:
            return
        generate_devis_pdf(path, devis_row, client_row, lignes)
        _open_file(path)

    def _export_facture(self, facture_row, client_row, lignes):
        default_name = f"{facture_row['numero']}.pdf"
        path = filedialog.asksaveasfilename(defaultextension=".pdf", initialfile=default_name,
                                             filetypes=[("Fichier PDF", "*.pdf")])
        if not path:
            return
        generate_facture_pdf(path, facture_row, client_row, lignes)
        _open_file(path)

    def _print_recu(self, recu_row, client_row):
        path = os.path.join(tempfile.gettempdir(), f"{recu_row['numero']}.pdf")
        generate_recu_pdf(path, recu_row, client_row)
        print_file(path)

    def _print_note(self, note_row, client_row):
        path = os.path.join(tempfile.gettempdir(), f"{note_row['numero'] or 'note'}.pdf")
        generate_note_pdf(path, note_row, client_row)
        print_file(path)

    def _print_devis(self, devis_row, client_row, lignes):
        path = os.path.join(tempfile.gettempdir(), f"{devis_row['numero']}.pdf")
        generate_devis_pdf(path, devis_row, client_row, lignes)
        print_file(path)

    def _print_facture(self, facture_row, client_row, lignes):
        path = os.path.join(tempfile.gettempdir(), f"{facture_row['numero']}.pdf")
        generate_facture_pdf(path, facture_row, client_row, lignes)
        print_file(path)

    def _whatsapp_message_dialog(self, telephone, message_defaut, on_reveal_pdf):
        """Fenêtre d'envoi WhatsApp réutilisable — voir
        `modules/whatsapp_service.ouvrir_dialogue_message` (extraite là-bas
        pour être partagée avec `modules/relances.py`, sans dupliquer cette
        fenêtre). Ce petit relais garde le même nom de méthode qu'avant pour
        que les appels existants (`self._whatsapp_message_dialog(...)`
        ci-dessous) n'aient rien à changer."""
        ouvrir_dialogue_message(self, telephone, message_defaut, on_reveal_pdf)

    def _whatsapp_devis(self, devis_row, client_row, lignes):
        path = os.path.join(tempfile.gettempdir(), f"{devis_row['numero']}.pdf")
        generate_devis_pdf(path, devis_row, client_row, lignes)
        nom = client_row["nom"] if client_row else ""
        montant_txt = f"{devis_row['montant_ht']:,.0f}".replace(",", " ")
        message = (f"Bonjour {nom}, voici votre devis {devis_row['numero']} d'un montant de "
                   f"{montant_txt} FCFA. Merci de votre confiance — MK Entreprise.")
        telephone = client_row["telephone"] if client_row else ""
        self._whatsapp_message_dialog(telephone, message, lambda: reveler_dans_explorateur(path))

    def _whatsapp_facture(self, facture_row, client_row, lignes):
        path = os.path.join(tempfile.gettempdir(), f"{facture_row['numero']}.pdf")
        generate_facture_pdf(path, facture_row, client_row, lignes)
        nom = client_row["nom"] if client_row else ""
        montant_txt = f"{facture_row['montant_ttc']:,.0f}".replace(",", " ")
        reste = facture_row["reste_a_payer"] or 0
        if reste > 0:
            reste_txt = f"{reste:,.0f}".replace(",", " ")
            suite = f" Reste à payer : {reste_txt} FCFA."
        else:
            suite = " Facture soldée, merci !"
        message = (f"Bonjour {nom}, voici votre facture {facture_row['numero']} d'un montant de "
                   f"{montant_txt} FCFA.{suite} — MK Entreprise.")
        telephone = client_row["telephone"] if client_row else ""
        self._whatsapp_message_dialog(telephone, message, lambda: reveler_dans_explorateur(path))

    def _whatsapp_recu(self, recu_row, client_row):
        path = os.path.join(tempfile.gettempdir(), f"{recu_row['numero']}.pdf")
        generate_recu_pdf(path, recu_row, client_row)
        nom = client_row["nom"] if client_row else ""
        montant_txt = f"{recu_row['montant_recu']:,.0f}".replace(",", " ")
        message = (f"Bonjour {nom}, voici votre reçu {recu_row['numero']} d'un montant de "
                   f"{montant_txt} FCFA. Merci de votre confiance — MK Entreprise.")
        telephone = client_row["telephone"] if client_row else ""
        self._whatsapp_message_dialog(telephone, message, lambda: reveler_dans_explorateur(path))
