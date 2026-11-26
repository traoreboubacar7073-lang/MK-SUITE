"""
MK Suite - Tableau de bord principal
"""
import customtkinter as ctk
import os
import shutil
from datetime import datetime, timedelta
from tkinter import filedialog
from ui.theme import COLORS, font, title_font, card, secondary_button, primary_button
from ui.widgets import KPICard, section_title, status_badge
from matplotlib.figure import Figure
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
import matplotlib
matplotlib.use("Agg")


class DashboardView(ctk.CTkScrollableFrame):
    def __init__(self, parent, db, app=None, **kwargs):
        super().__init__(parent, fg_color="transparent", **kwargs)
        self.db = db
        self.app = app
        self.build()

    def build(self):
        # En-tête
        header = ctk.CTkFrame(self, fg_color="transparent")
        header.pack(fill="x", padx=4, pady=(4, 20))
        section_title(header, "Tableau de bord",
                      f"Bienvenue • {datetime.now().strftime('%A %d %B %Y')}").pack(side="left")
        primary_button(header, "💾 Sauvegarder mes données", command=self._backup_data,
                        height=38).pack(side="right")

        # ---- KPIs ----
        kpi_row = ctk.CTkFrame(self, fg_color="transparent")
        kpi_row.pack(fill="x", padx=4, pady=(0, 20))
        kpi_row.grid_columnconfigure((0, 1, 2, 3), weight=1, uniform="kpi")

        ca_mois = self._get_ca_mois()
        depenses_mois = self._get_depenses_mois()
        factures_impayees = self._get_factures_impayees()
        nb_clients = self._get_nb_clients()

        KPICard(kpi_row, "Chiffre d'affaires (mois)", ca_mois, suffix=" FCFA", icon="💰",
                accent=COLORS["gold"], subtitle="Factures émises ce mois",
                on_click=lambda: self._goto("devis", initial_mode="factures")).grid(
            row=0, column=0, padx=8, pady=4, sticky="nsew")
        KPICard(kpi_row, "Dépenses (mois)", depenses_mois, suffix=" FCFA", icon="📉",
                accent=COLORS["danger"], subtitle="Total des sorties",
                on_click=lambda: self._goto("depenses")).grid(
            row=0, column=1, padx=8, pady=4, sticky="nsew")
        KPICard(kpi_row, "Factures impayées", factures_impayees, suffix=" FCFA", icon="⚠️",
                accent=COLORS["warning"], subtitle="À recouvrer",
                on_click=lambda: self._goto("devis", initial_mode="factures")).grid(
            row=0, column=2, padx=8, pady=4, sticky="nsew")
        KPICard(kpi_row, "Clients actifs", nb_clients, suffix="", icon="👥",
                accent=COLORS["info"], subtitle="Base client totale",
                on_click=lambda: self._goto("clients")).grid(
            row=0, column=3, padx=8, pady=4, sticky="nsew")

        # ---- Graphique + activité récente ----
        mid_row = ctk.CTkFrame(self, fg_color="transparent")
        mid_row.pack(fill="both", expand=True, padx=4, pady=(0, 16))
        mid_row.grid_columnconfigure(0, weight=2)
        mid_row.grid_columnconfigure(1, weight=1)

        chart_card = card(mid_row)
        chart_card.grid(row=0, column=0, sticky="nsew", padx=(0, 8))
        chart_head = ctk.CTkFrame(chart_card, fg_color="transparent")
        chart_head.pack(fill="x", padx=20, pady=(18, 10))
        ctk.CTkLabel(chart_head, text="Évolution du chiffre d'affaires (6 derniers mois)",
                     font=font(14, "bold"), text_color=COLORS["text_primary"]).pack(side="left")
        voir_tout = ctk.CTkLabel(chart_head, text="Voir toutes les factures →", font=font(11, "bold"),
                                  text_color=COLORS["gold"], cursor="hand2")
        voir_tout.pack(side="right")
        voir_tout.bind("<Button-1>", lambda e: self._goto("devis", initial_mode="factures"))
        self._build_chart(chart_card)

        activity_card = card(mid_row)
        activity_card.grid(row=0, column=1, sticky="nsew", padx=(8, 0))
        ctk.CTkLabel(activity_card, text="Activité récente", font=font(14, "bold"),
                     text_color=COLORS["text_primary"]).pack(anchor="w", padx=20, pady=(18, 10))
        self._build_activity_feed(activity_card)

    def _goto(self, page, **kwargs):
        if self.app:
            self.app.show_page(page, **kwargs)

    def _get_ca_mois(self):
        month = datetime.now().strftime("%Y-%m")
        row = self.db.fetchone(
            "SELECT COALESCE(SUM(montant_ttc),0) as t FROM factures WHERE date_facture LIKE ?",
            (f"{month}%",))
        return row["t"] if row else 0

    def _get_depenses_mois(self):
        month = datetime.now().strftime("%Y-%m")
        row = self.db.fetchone(
            "SELECT COALESCE(SUM(montant),0) as t FROM depenses WHERE date_depense LIKE ?",
            (f"{month}%",))
        return row["t"] if row else 0

    def _get_factures_impayees(self):
        row = self.db.fetchone(
            "SELECT COALESCE(SUM(reste_a_payer),0) as t FROM factures WHERE statut != 'Payée'")
        return row["t"] if row else 0

    def _get_nb_clients(self):
        row = self.db.fetchone("SELECT COUNT(*) as c FROM clients")
        return row["c"] if row else 0

    def _build_chart(self, parent):
        fig = Figure(figsize=(6, 3), dpi=100, facecolor=COLORS["bg_card"])
        ax = fig.add_subplot(111)
        ax.set_facecolor(COLORS["bg_card"])

        months, values = [], []
        for i in range(5, -1, -1):
            d = datetime.now() - timedelta(days=i * 30)
            month_key = d.strftime("%Y-%m")
            months.append(d.strftime("%b"))
            row = self.db.fetchone(
                "SELECT COALESCE(SUM(montant_ttc),0) as t FROM factures WHERE date_facture LIKE ?",
                (f"{month_key}%",))
            values.append(row["t"] if row else 0)

        ax.plot(months, values, color=COLORS["gold"], linewidth=2.5, marker="o",
                markersize=6, markerfacecolor=COLORS["gold_light"])
        ax.fill_between(months, values, color=COLORS["gold"], alpha=0.12)

        for spine in ax.spines.values():
            spine.set_color(COLORS["border"])
        ax.spines["top"].set_visible(False)
        ax.spines["right"].set_visible(False)
        ax.tick_params(colors=COLORS["text_secondary"], labelsize=9)
        ax.grid(axis="y", color=COLORS["border"], linewidth=0.5, alpha=0.5)

        canvas = FigureCanvasTkAgg(fig, master=parent)
        canvas.draw()
        canvas.get_tk_widget().pack(fill="both", expand=True, padx=16, pady=(0, 16))

    def _build_activity_feed(self, parent):
        activities = []
        for r in self.db.fetchall(
                "SELECT 'Facture' as type, numero, montant_ttc, date_facture FROM factures "
                "ORDER BY id DESC LIMIT 4"):
            activities.append(("📄", f"Facture {r['numero']}", f"{r['montant_ttc']:,.0f} FCFA".replace(",", " "),
                                lambda n=r["numero"]: self._goto("devis", initial_mode="factures", focus_numero=n)))
        for r in self.db.fetchall(
                "SELECT id, nom, date_premier_contact FROM clients ORDER BY id DESC LIMIT 3"):
            activities.append(("👤", "Nouveau client", r["nom"],
                                lambda cid=r["id"]: self._goto("clients", focus_id=cid)))

        if not activities:
            ctk.CTkLabel(parent, text="Aucune activité pour le moment.\nCommence par ajouter un client\nou créer un devis.",
                         font=font(12), text_color=COLORS["text_muted"], justify="left").pack(
                anchor="w", padx=20, pady=20)
            return

        for icon, title, sub, click_target in activities[:6]:
            row = ctk.CTkFrame(parent, fg_color="transparent", cursor="hand2")
            row.pack(fill="x", padx=20, pady=6)
            row.bind("<Button-1>", lambda e, fn=click_target: fn())
            icon_lbl = ctk.CTkLabel(row, text=icon, font=font(16), width=24, cursor="hand2")
            icon_lbl.pack(side="left")
            icon_lbl.bind("<Button-1>", lambda e, fn=click_target: fn())
            txt = ctk.CTkFrame(row, fg_color="transparent", cursor="hand2")
            txt.pack(side="left", fill="x", expand=True, padx=(8, 0))
            txt.bind("<Button-1>", lambda e, fn=click_target: fn())
            title_lbl = ctk.CTkLabel(txt, text=title, font=font(12, "bold"), text_color=COLORS["text_primary"],
                                      anchor="w", cursor="hand2")
            title_lbl.pack(anchor="w")
            title_lbl.bind("<Button-1>", lambda e, fn=click_target: fn())
            sub_lbl = ctk.CTkLabel(txt, text=sub, font=font(11), text_color=COLORS["text_secondary"],
                                    anchor="w", cursor="hand2")
            sub_lbl.pack(anchor="w")
            sub_lbl.bind("<Button-1>", lambda e, fn=click_target: fn())
        ctk.CTkFrame(parent, fg_color="transparent", height=10).pack()

    def _backup_data(self):
        """Copie le fichier de base de données actuel vers un emplacement choisi par l'utilisateur
        (clé USB, Google Drive synchronisé, etc.) — pour ne jamais perdre les données."""
        default_name = f"MK_Suite_Sauvegarde_{datetime.now().strftime('%Y-%m-%d_%Hh%M')}.db"
        path = filedialog.asksaveasfilename(defaultextension=".db", initialfile=default_name,
                                             filetypes=[("Base de données MK Suite", "*.db")])
        if not path:
            return
        try:
            shutil.copy(self.db.db_path, path)
            self._show_backup_confirmation(path)
        except Exception as e:
            self._show_backup_confirmation(None, error=str(e))

    def _show_backup_confirmation(self, path, error=None):
        dialog = ctk.CTkToplevel(self)
        dialog.title("Sauvegarde")
        dialog.geometry("380x180")
        dialog.configure(fg_color=COLORS["bg_dark"])
        dialog.transient(self)
        dialog.grab_set()
        dialog.bind("<Escape>", lambda e: dialog.destroy())
        if error:
            ctk.CTkLabel(dialog, text="❌", font=font(28)).pack(pady=(24, 4))
            ctk.CTkLabel(dialog, text="Échec de la sauvegarde", font=font(14, "bold"),
                         text_color=COLORS["text_primary"]).pack()
            ctk.CTkLabel(dialog, text=error, font=font(10), text_color=COLORS["text_secondary"],
                         wraplength=320).pack(pady=8)
        else:
            ctk.CTkLabel(dialog, text="✅", font=font(28)).pack(pady=(24, 4))
            ctk.CTkLabel(dialog, text="Sauvegarde réussie !", font=font(14, "bold"),
                         text_color=COLORS["text_primary"]).pack()
            ctk.CTkLabel(dialog, text=f"Copie enregistrée dans :\n{path}", font=font(10),
                         text_color=COLORS["text_secondary"], wraplength=320,
                         justify="center").pack(pady=8)
        secondary_button(dialog, "Fermer", command=dialog.destroy).pack(fill="x", padx=32, pady=(8, 20))
