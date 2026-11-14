"""
MK Suite - Notifications (cloche dans la barre du haut)
Rassemble les mêmes alertes intelligentes qui vivaient auparavant dans un
encart du tableau de bord (factures en retard, devis qui expirent
bientôt) et les affiche désormais dans une cloche de notifications en
haut de l'application — comme sur Winner Style — avec un badge indiquant
le nombre de points à surveiller.
"""
import customtkinter as ctk
from datetime import datetime, timedelta
from ui.theme import COLORS, font, title_font


def compute_alerts(db):
    """Retourne la liste des alertes en cours : tuples
    (level, icon, title, sub, target_mode, target_numero)."""
    alerts = []

    # Factures en retard : impayées ou partielles, émises il y a plus de 30 jours
    seuil = (datetime.now() - timedelta(days=30)).strftime("%Y-%m-%d")
    factures_retard = db.fetchall(
        "SELECT f.numero, f.reste_a_payer, c.nom as client_nom FROM factures f "
        "LEFT JOIN clients c ON c.id = f.client_id "
        "WHERE f.reste_a_payer > 0 AND f.date_facture < ? ORDER BY f.date_facture ASC LIMIT 5",
        (seuil,))
    for f in factures_retard:
        alerts.append(("danger", "🔴",
                        f"Facture {f['numero']} en retard",
                        f"{f['client_nom'] or 'Client ?'} — {f['reste_a_payer']:,.0f} FCFA dus".replace(",", " "),
                        "factures", f["numero"]))

    # Devis en attente dont la date limite est dépassée ou proche (7 jours)
    proche = (datetime.now() + timedelta(days=7)).strftime("%Y-%m-%d")
    devis_proches = db.fetchall(
        "SELECT d.numero, d.date_limite, c.nom as client_nom FROM devis d "
        "LEFT JOIN clients c ON c.id = d.client_id "
        "WHERE d.statut='En attente' AND d.date_limite IS NOT NULL AND d.date_limite <= ? "
        "ORDER BY d.date_limite ASC LIMIT 5", (proche,))
    today_str = datetime.now().strftime("%Y-%m-%d")
    for d in devis_proches:
        expired = d["date_limite"] < today_str
        alerts.append(("danger" if expired else "warning", "⏰" if not expired else "⛔",
                        f"Devis {d['numero']} " + ("expiré" if expired else "expire bientôt"),
                        f"{d['client_nom'] or 'Client ?'} — limite le {d['date_limite']}",
                        "devis", d["numero"]))

    return alerts[:6]


class NotificationsDialog(ctk.CTkToplevel):
    """Petit panneau qui s'ouvre sous la cloche de la barre du haut —
    équivalent bureau de la feuille de notifications de la version mobile."""

    def __init__(self, app, db, anchor_widget=None, on_close=None):
        super().__init__(app)
        self.app = app
        self.db = db
        self.on_close = on_close
        self.title("Notifications")
        self.configure(fg_color=COLORS["bg_dark"])
        self.transient(app)
        self.resizable(False, False)
        self.grab_set()
        self.bind("<Escape>", lambda e: self.destroy())
        self.protocol("WM_DELETE_WINDOW", self.destroy)

        width, height = 380, 460
        x = app.winfo_rootx() + max(0, app.winfo_width() - width - 28)
        y = app.winfo_rooty() + 90
        if anchor_widget is not None:
            try:
                bx = anchor_widget.winfo_rootx()
                by = anchor_widget.winfo_rooty()
                bw = anchor_widget.winfo_width()
                bh = anchor_widget.winfo_height()
                x = bx + bw - width
                y = by + bh + 6
            except Exception:
                pass
        self.geometry(f"{width}x{height}+{max(x, 0)}+{max(y, 0)}")

        header = ctk.CTkFrame(self, fg_color="transparent")
        header.pack(fill="x", padx=18, pady=(16, 8))
        ctk.CTkLabel(header, text="🔔 Notifications", font=title_font(15),
                     text_color=COLORS["text_primary"]).pack(side="left")

        self.scroll = ctk.CTkScrollableFrame(self, fg_color="transparent")
        self.scroll.pack(fill="both", expand=True, padx=14, pady=(0, 14))

        self._build_list()

    def _build_list(self):
        for w in self.scroll.winfo_children():
            w.destroy()
        alerts = compute_alerts(self.db)
        if not alerts:
            ctk.CTkLabel(self.scroll, text="Rien à signaler pour le moment.",
                         font=font(12), text_color=COLORS["text_muted"]).pack(pady=40)
            return
        for level, icon, title, sub, target_mode, target_numero in alerts:
            self._row(level, icon, title, sub, target_mode, target_numero)

    def _row(self, level, icon, title, sub, target_mode, target_numero):
        color = COLORS["danger"] if level == "danger" else COLORS["warning"]
        row = ctk.CTkFrame(self.scroll, fg_color=COLORS["bg_card"], corner_radius=10, cursor="hand2")
        row.pack(fill="x", pady=4)
        click = lambda e=None, m=target_mode, n=target_numero: self._goto(m, n)
        inner = ctk.CTkFrame(row, fg_color="transparent")
        inner.pack(fill="x", padx=12, pady=10)
        icon_lbl = ctk.CTkLabel(inner, text=icon, font=font(15), text_color=color, width=28)
        icon_lbl.pack(side="left", padx=(0, 8))
        txt = ctk.CTkFrame(inner, fg_color="transparent")
        txt.pack(side="left", fill="x", expand=True)
        title_lbl = ctk.CTkLabel(txt, text=title, font=font(12, "bold"),
                                  text_color=COLORS["text_primary"], anchor="w")
        title_lbl.pack(anchor="w")
        sub_lbl = ctk.CTkLabel(txt, text=sub, font=font(11), text_color=COLORS["text_secondary"], anchor="w")
        sub_lbl.pack(anchor="w")
        for w in (row, inner, icon_lbl, txt, title_lbl, sub_lbl):
            w.bind("<Button-1>", click)

    def _goto(self, target_mode, target_numero):
        self.destroy()
        self.app.show_page("devis", initial_mode=target_mode, focus_numero=target_numero)

    def destroy(self):
        if self.on_close:
            try:
                self.on_close()
            except Exception:
                pass
        super().destroy()
