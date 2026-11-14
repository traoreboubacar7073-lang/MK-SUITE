"""
MK SUITE - Logiciel de gestion MK Entreprise & Sourcing
Développé pour Boubacar - Bamako, Mali
"""
import customtkinter as ctk
from PIL import Image
import sys
import os
from datetime import datetime
from resource_path import resource_path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from ui.theme import apply_theme, COLORS, font, title_font
from database.db_manager import DatabaseManager
from modules.dashboard import DashboardView
from modules.clients import ClientsView
from modules.devis_factures import DevisFacturesView
from modules.depenses import DepensesView
from modules.fournisseurs import FournisseursView
from modules.employes import EmployesView
from modules.sourcing import SourcingView
from modules.calcul_vitres import CalculVitresView
from modules.budget import BudgetView
from modules.corbeille import CorbeilleView
from modules.synchronisation import SynchronisationView
from modules.relances import RelancesView
from modules.sauvegarde import SauvegardeView
from modules.recherche_globale import RechercheGlobaleDialog
from modules.notifications import NotificationsDialog, compute_alerts

apply_theme()

NAV_ITEMS = [
    ("dashboard", "🏠", "Tableau de bord"),
    ("clients", "👥", "Clients"),
    ("devis", "📋", "Devis & Factures"),
    ("relances", "🔔", "Rappels impayés"),
    ("sourcing", "🚚", "Sourcing"),
    ("depenses", "💳", "Dépenses"),
    ("vitres", "📐", "Calcul Vitres"),
    ("budget", "📊", "Contrôle Budget"),
    ("fournisseurs", "🏭", "Fournisseurs"),
    ("employes", "👔", "Employés / Paie"),
    ("corbeille", "🗑️", "Corbeille"),
    ("sauvegarde", "💾", "Sauvegarde"),
    ("sync", "🔄", "Synchronisation"),
]


class MKSuiteApp(ctk.CTk):
    def __init__(self):
        super().__init__()
        self.title("MK Suite 1.1.2 — Gestion MK Entreprise")
        self._center_window(1360, 820)
        self.minsize(1100, 700)
        self.configure(fg_color=COLORS["bg_dark"])
        self._set_window_icon()

        self.db = DatabaseManager()
        self.db.purge_corbeille_ancienne(jours=30)
        self.nav_buttons = {}
        self.active_view = None
        self.current_page = None

        self._build_sidebar()
        self._build_main_area()
        self.show_page("dashboard")

    def _center_window(self, width, height):
        self.update_idletasks()
        screen_w = self.winfo_screenwidth()
        screen_h = self.winfo_screenheight()
        x = max(0, (screen_w - width) // 2)
        y = max(0, (screen_h - height) // 2 - 20)
        self.geometry(f"{width}x{height}+{x}+{y}")

    def _set_window_icon(self):
        try:
            icon_path = resource_path("assets", "icon.ico")
            if os.path.exists(icon_path):
                self.iconbitmap(icon_path)
        except Exception:
            pass  # Sur certains systèmes (Linux/macOS) .ico n'est pas supporté — sans conséquence

    # ---------------- SIDEBAR ----------------
    def _build_sidebar(self):
        self.sidebar = ctk.CTkFrame(self, fg_color=COLORS["bg_sidebar"], width=208,
                                     corner_radius=0)
        self.sidebar.pack(side="left", fill="y")
        self.sidebar.pack_propagate(False)

        # Logo / branding
        brand = ctk.CTkFrame(self.sidebar, fg_color="transparent")
        brand.pack(fill="x", padx=20, pady=(22, 12))

        logo_path = resource_path("assets", "logo.png")
        if os.path.exists(logo_path):
            pil_img = Image.open(logo_path)
            logo_img = ctk.CTkImage(light_image=pil_img, dark_image=pil_img, size=(50, 50))
            ctk.CTkLabel(brand, image=logo_img, text="").pack(side="left")
            text_col = ctk.CTkFrame(brand, fg_color="transparent")
            text_col.pack(side="left", padx=(12, 0))
            ctk.CTkLabel(text_col, text="MK ENTREPRISE", font=ctk.CTkFont(family="Segoe UI", size=13, weight="bold"),
                         text_color=COLORS["gold"], anchor="w").pack(anchor="w")
            ctk.CTkLabel(text_col, text="SUITE DE GESTION", font=font(9),
                         text_color=COLORS["text_secondary"], anchor="w").pack(anchor="w")
        else:
            ctk.CTkLabel(brand, text="MK", font=ctk.CTkFont(family="Segoe UI", size=28, weight="bold"),
                         text_color=COLORS["gold"]).pack(side="left")
            ctk.CTkLabel(brand, text="SUITE", font=ctk.CTkFont(family="Segoe UI", size=28, weight="normal"),
                         text_color=COLORS["text_primary"]).pack(side="left", padx=(4, 0))

        ctk.CTkLabel(self.sidebar, text="Aluminium · Volet · Inox · Alu Gobonne",
                     font=font(9), text_color=COLORS["text_muted"], wraplength=168,
                     justify="left").pack(padx=20, anchor="w", pady=(0, 12))

        sep = ctk.CTkFrame(self.sidebar, fg_color=COLORS["border"], height=1)
        sep.pack(fill="x", padx=16, pady=(0, 8))

        # Nav items — dans une zone scrollable pour rester accessible même si la fenêtre
        # est petite ou qu'on ajoute encore des modules plus tard
        self.nav_scroll = ctk.CTkScrollableFrame(self.sidebar, fg_color="transparent",
                                                   scrollbar_button_color=COLORS["bg_card_hover"],
                                                   scrollbar_button_hover_color=COLORS["gold"])
        self.nav_scroll.pack(fill="both", expand=True, padx=0, pady=0)
        for key, icon, label in NAV_ITEMS:
            self._add_nav_button(key, icon, label)

        # Footer (fixé en bas, packé AVANT la zone scrollable pour réserver sa place)
        footer = ctk.CTkFrame(self.sidebar, fg_color="transparent")
        footer.pack(side="bottom", fill="x", padx=20, pady=24)
        sep2 = ctk.CTkFrame(footer, fg_color=COLORS["border"], height=1)
        sep2.pack(fill="x", pady=(0, 12))
        ctk.CTkLabel(footer, text="MK Entreprise", font=font(11, "bold"),
                     text_color=COLORS["text_secondary"]).pack(anchor="w")
        footer_row = ctk.CTkFrame(footer, fg_color="transparent")
        footer_row.pack(fill="x", pady=(2, 0))
        ctk.CTkLabel(footer_row, text="Bamako, Mali", font=font(10),
                     text_color=COLORS["text_muted"]).pack(side="left")
        ctk.CTkLabel(footer_row, text="MK Suite v1.0", font=font(9),
                     text_color=COLORS["gold"]).pack(side="right")

    def _add_nav_button(self, key, icon, label):
        wrapper = ctk.CTkFrame(self.nav_scroll, fg_color="transparent")
        wrapper.pack(fill="x", padx=10, pady=1)

        accent = ctk.CTkFrame(wrapper, fg_color="transparent", width=3, height=36, corner_radius=2)
        accent.pack(side="left", fill="y", padx=(0, 0))

        btn = ctk.CTkButton(
            wrapper, text=f" {icon}  {label}", anchor="w",
            fg_color="transparent", hover_color=COLORS["bg_card_hover"],
            text_color=COLORS["text_secondary"], font=font(13),
            corner_radius=8, height=36,
            command=lambda: self.show_page(key)
        )
        btn.pack(side="left", fill="x", expand=True)
        self.nav_buttons[key] = btn
        self.nav_accents = getattr(self, "nav_accents", {})
        self.nav_accents[key] = accent

    def _set_active_nav(self, key):
        for k, btn in self.nav_buttons.items():
            accent = self.nav_accents.get(k)
            if k == key:
                btn.configure(fg_color=COLORS["bg_card"], text_color=COLORS["gold"],
                              font=font(13, "bold"))
                if accent:
                    accent.configure(fg_color=COLORS["gold"])
            else:
                btn.configure(fg_color="transparent", text_color=COLORS["text_secondary"],
                              font=font(13))
                if accent:
                    accent.configure(fg_color="transparent")

    # ---------------- MAIN AREA ----------------
    def _build_main_area(self):
        self.main_area = ctk.CTkFrame(self, fg_color=COLORS["bg_dark"], corner_radius=0)
        self.main_area.pack(side="right", fill="both", expand=True)

        self._build_top_bar()

        self.content_container = ctk.CTkFrame(self.main_area, fg_color="transparent")
        self.content_container.pack(fill="both", expand=True, padx=28, pady=(0, 24))

    def _build_top_bar(self):
        top_bar = ctk.CTkFrame(self.main_area, fg_color=COLORS["bg_dark"], corner_radius=0, height=56)
        top_bar.pack(fill="x", padx=28, pady=(18, 12))
        top_bar.pack_propagate(False)

        left = ctk.CTkFrame(top_bar, fg_color="transparent")
        left.pack(side="left", fill="y")
        self.breadcrumb_icon = ctk.CTkLabel(left, text="🏠", font=font(16), text_color=COLORS["gold"])
        self.breadcrumb_icon.pack(side="left")
        self.breadcrumb_lbl = ctk.CTkLabel(left, text="Tableau de bord", font=font(13, "bold"),
                                            text_color=COLORS["text_secondary"])
        self.breadcrumb_lbl.pack(side="left", padx=(8, 0))

        right = ctk.CTkFrame(top_bar, fg_color=COLORS["bg_card"], corner_radius=10, border_width=1,
                              border_color=COLORS["border"])
        right.pack(side="right", ipady=6, ipadx=14)
        self.clock_lbl = ctk.CTkLabel(right, text="", font=font(12), text_color=COLORS["text_secondary"])
        self.clock_lbl.pack()
        self._tick_clock()

        # Recherche globale — accessible depuis n'importe quelle page (bouton
        # dans la barre du haut + raccourci clavier Ctrl+F), pour ne jamais
        # avoir à deviner dans quel module se trouve un client/devis/facture.
        search_btn = ctk.CTkButton(
            top_bar, text="🔍 Rechercher (Ctrl+F)", command=self._open_recherche_globale,
            fg_color=COLORS["bg_card"], hover_color=COLORS["bg_card_hover"],
            text_color=COLORS["text_secondary"], font=font(12), corner_radius=10,
            height=36, border_width=1, border_color=COLORS["border"])
        search_btn.pack(side="right", padx=(0, 10))
        self.bind_all("<Control-f>", lambda e: self._open_recherche_globale())

        # Cloche de notifications — remplace l'ancien encart "Alertes" du
        # tableau de bord (comme sur Winner Style) : un badge indique le
        # nombre de points à surveiller, un clic ouvre le détail et permet
        # d'aller directement à la facture/au devis concerné.
        self.bell_frame = ctk.CTkFrame(top_bar, fg_color="transparent", width=40, height=36)
        self.bell_frame.pack(side="right", padx=(0, 10))
        self.bell_frame.pack_propagate(False)
        self.bell_btn = ctk.CTkButton(
            self.bell_frame, text="🔔", command=self._open_notifications,
            fg_color=COLORS["bg_card"], hover_color=COLORS["bg_card_hover"],
            text_color=COLORS["text_secondary"], font=font(15), corner_radius=10,
            width=40, height=36, border_width=1, border_color=COLORS["border"])
        self.bell_btn.pack(fill="both", expand=True)
        self.bell_badge = ctk.CTkLabel(
            self.bell_frame, text="", font=font(9, "bold"), text_color="white",
            fg_color=COLORS["danger"], corner_radius=8, width=16, height=16)
        self._refresh_notifications_badge()

        sep = ctk.CTkFrame(self.main_area, fg_color=COLORS["border"], height=1)
        sep.pack(fill="x", padx=28)

    def _open_recherche_globale(self):
        RechercheGlobaleDialog(self, self.db)

    def _open_notifications(self):
        NotificationsDialog(self, self.db, anchor_widget=self.bell_btn,
                             on_close=self._refresh_notifications_badge)

    def _refresh_notifications_badge(self):
        if not hasattr(self, "bell_badge"):
            return  # la barre du haut n'est pas encore entièrement construite (1er appel via _tick_clock)
        try:
            count = len(compute_alerts(self.db))
        except Exception:
            count = 0
        if count > 0:
            self.bell_badge.configure(text=str(count) if count <= 9 else "9+")
            self.bell_badge.place(relx=1.0, rely=0.0, x=-2, y=2, anchor="ne")
        else:
            self.bell_badge.place_forget()

    def _tick_clock(self):
        import locale
        now = datetime.now()
        jours = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"]
        mois_noms = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet",
                     "août", "septembre", "octobre", "novembre", "décembre"]
        txt = f"{jours[now.weekday()]} {now.day} {mois_noms[now.month-1]} {now.year}  ·  {now.strftime('%H:%M')}"
        self.clock_lbl.configure(text=txt)
        self._refresh_notifications_badge()
        self.after(30000, self._tick_clock)

    def show_page(self, key, **kwargs):
        if self.current_page == key and not kwargs:
            return
        self.current_page = key
        self._set_active_nav(key)
        self._refresh_notifications_badge()

        icon_map = dict((k, i) for k, i, l in NAV_ITEMS)
        label_map = dict((k, l) for k, i, l in NAV_ITEMS)
        self.breadcrumb_icon.configure(text=icon_map.get(key, ""))
        self.breadcrumb_lbl.configure(text=label_map.get(key, ""))

        for w in self.content_container.winfo_children():
            w.destroy()

        if key == "dashboard":
            DashboardView(self.content_container, self.db, app=self).pack(fill="both", expand=True)
        elif key == "clients":
            ClientsView(self.content_container, self.db, **kwargs).pack(fill="both", expand=True)
        elif key == "devis":
            DevisFacturesView(self.content_container, self.db, **kwargs).pack(fill="both", expand=True)
        elif key == "relances":
            RelancesView(self.content_container, self.db, app=self, **kwargs).pack(fill="both", expand=True)
        elif key == "sourcing":
            SourcingView(self.content_container, self.db).pack(fill="both", expand=True)
        elif key == "depenses":
            DepensesView(self.content_container, self.db).pack(fill="both", expand=True)
        elif key == "vitres":
            CalculVitresView(self.content_container, self.db).pack(fill="both", expand=True)
        elif key == "budget":
            BudgetView(self.content_container, self.db).pack(fill="both", expand=True)
        elif key == "fournisseurs":
            FournisseursView(self.content_container, self.db).pack(fill="both", expand=True)
        elif key == "employes":
            EmployesView(self.content_container, self.db).pack(fill="both", expand=True)
        elif key == "corbeille":
            CorbeilleView(self.content_container, self.db).pack(fill="both", expand=True)
        elif key == "sauvegarde":
            SauvegardeView(self.content_container, self.db).pack(fill="both", expand=True)
        elif key == "sync":
            SynchronisationView(self.content_container, self.db).pack(fill="both", expand=True)
        else:
            self._placeholder_page(key)

    def _placeholder_page(self, key):
        label_map = dict((k, l) for k, i, l in NAV_ITEMS)
        frame = ctk.CTkFrame(self.content_container, fg_color="transparent")
        frame.pack(fill="both", expand=True)
        ctk.CTkLabel(frame, text="🚧", font=font(40)).pack(pady=(120, 10))
        ctk.CTkLabel(frame, text=f"Module « {label_map.get(key, key)} » — Prochaine étape",
                     font=title_font(18), text_color=COLORS["text_primary"]).pack()
        ctk.CTkLabel(frame, text="Ce module sera construit dans la suite du développement.",
                     font=font(12), text_color=COLORS["text_secondary"]).pack(pady=(6, 0))

    def on_close(self):
        self.db.close()
        self.destroy()


if __name__ == "__main__":
    from splash import SplashScreen

    app = MKSuiteApp()
    app.protocol("WM_DELETE_WINDOW", app.on_close)
    app.withdraw()  # caché pendant que le splash s'affiche

    def show_main_app():
        app.deiconify()

    splash = SplashScreen(app, on_ready=show_main_app)
    app.mainloop()
