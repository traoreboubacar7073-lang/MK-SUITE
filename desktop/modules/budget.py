"""
MK Suite - Module Contrôle Budget
Compare le budget mensuel alloué (saisi par catégorie) aux dépenses réelles
du registre Dépenses, avec écart, % utilisé et alerte — comme l'onglet Excel.
"""
import customtkinter as ctk
from datetime import datetime
from ui.theme import COLORS, font, title_font, card, primary_button, secondary_button
from ui.widgets import section_title, status_badge
from ui.reference_lists import CATEGORIE_DEPENSE, MOIS


class BudgetView(ctk.CTkFrame):
    def __init__(self, parent, db, **kwargs):
        super().__init__(parent, fg_color="transparent", **kwargs)
        self.db = db
        self.mois_var = ctk.StringVar(value=MOIS[datetime.now().month - 1])
        self.annee_var = ctk.StringVar(value=str(datetime.now().year))
        self.build()
        self.refresh()

    def build(self):
        header = ctk.CTkFrame(self, fg_color="transparent")
        header.pack(fill="x", padx=4, pady=(4, 16))
        section_title(header, "Contrôle Budget",
                      "Compare le budget alloué aux dépenses réelles, mois par mois").pack(side="left")

        selector = ctk.CTkFrame(self, fg_color="transparent")
        selector.pack(fill="x", padx=4, pady=(0, 16))
        ctk.CTkLabel(selector, text="Mois analysé :", font=font(12), text_color=COLORS["text_secondary"]).pack(
            side="left", padx=(0, 8))
        mois_menu = ctk.CTkOptionMenu(selector, values=MOIS, variable=self.mois_var,
                                       command=lambda v: self.refresh(), height=36, width=150,
                                       corner_radius=8, fg_color=COLORS["bg_input"],
                                       button_color=COLORS["gold"], button_hover_color=COLORS["gold_light"],
                                       text_color=COLORS["text_primary"])
        mois_menu.pack(side="left", padx=(0, 16))
        ctk.CTkLabel(selector, text="Année :", font=font(12), text_color=COLORS["text_secondary"]).pack(
            side="left", padx=(0, 8))
        annee_entry = ctk.CTkEntry(selector, textvariable=self.annee_var, height=36, width=90,
                                    corner_radius=8, fg_color=COLORS["bg_input"], border_color=COLORS["border"],
                                    font=font(12))
        annee_entry.pack(side="left")
        annee_entry.bind("<Return>", lambda e: self.refresh())
        secondary_button(selector, "Actualiser", command=self.refresh, height=36, width=110).pack(
            side="left", padx=(12, 0))

        self.totals_row = ctk.CTkFrame(self, fg_color="transparent")
        self.totals_row.pack(fill="x", padx=4, pady=(0, 12))

        self.table_frame = ctk.CTkScrollableFrame(self, fg_color="transparent")
        self.table_frame.pack(fill="both", expand=True, padx=4)

    def _mois_index(self):
        return MOIS.index(self.mois_var.get()) + 1

    def refresh(self):
        try:
            annee = int(self.annee_var.get())
        except ValueError:
            annee = datetime.now().year
        mois_num = self._mois_index()
        mois_key = f"{annee}-{mois_num:02d}"

        for w in self.table_frame.winfo_children():
            w.destroy()
        for w in self.totals_row.winfo_children():
            w.destroy()

        header_row = ctk.CTkFrame(self.table_frame, fg_color=COLORS["bg_sidebar"], corner_radius=8, height=40)
        header_row.pack(fill="x", pady=(0, 4))
        cols = [("CATÉGORIE", 220), ("BUDGET ALLOUÉ", 130), ("DÉPENSES RÉELLES", 130),
                ("ÉCART", 120), ("% UTILISÉ", 90)]
        for txt, w in cols:
            ctk.CTkLabel(header_row, text=txt, font=font(10, "bold"), text_color=COLORS["gold"],
                         width=w, anchor="w").pack(side="left", padx=8)
        ctk.CTkLabel(header_row, text="ALERTE", font=font(10, "bold"), text_color=COLORS["gold"],
                     anchor="e").pack(side="right", padx=16)

        total_budget = 0
        total_reel = 0

        for i, categorie in enumerate(CATEGORIE_DEPENSE):
            budget_row = self.db.fetchone(
                "SELECT budget_prevu FROM budget_categories WHERE categorie=? AND mois=? AND annee=?",
                (categorie, self.mois_var.get(), annee))
            budget = budget_row["budget_prevu"] if budget_row else 0

            reel_row = self.db.fetchone(
                "SELECT COALESCE(SUM(montant),0) as t FROM depenses WHERE categorie=? AND date_depense LIKE ?",
                (categorie, f"{mois_key}%"))
            reel = reel_row["t"]

            ecart = budget - reel
            pct = (reel / budget * 100) if budget > 0 else 0
            if pct == 0 and budget == 0:
                alerte, alerte_color = "—", "neutral"
            elif pct < 80:
                alerte, alerte_color = "OK", "success"
            elif pct <= 100:
                alerte, alerte_color = "Attention", "warning"
            else:
                alerte, alerte_color = "Dépassé", "danger"

            total_budget += budget
            total_reel += reel

            self._build_budget_row(categorie, budget, reel, ecart, pct, alerte, alerte_color, i,
                                    mois_num, annee)

        # Ligne TOTAL
        total_row = ctk.CTkFrame(self.table_frame, fg_color=COLORS["gold"], corner_radius=8, height=44)
        total_row.pack(fill="x", pady=(6, 0))
        total_row.pack_propagate(False)
        ctk.CTkLabel(total_row, text="TOTAL", font=font(12, "bold"), text_color="#0B1220",
                     width=220, anchor="w").pack(side="left", padx=8)
        ctk.CTkLabel(total_row, text=f"{total_budget:,.0f}".replace(",", " "), font=font(12, "bold"),
                     text_color="#0B1220", width=130, anchor="w").pack(side="left", padx=8)
        ctk.CTkLabel(total_row, text=f"{total_reel:,.0f}".replace(",", " "), font=font(12, "bold"),
                     text_color="#0B1220", width=130, anchor="w").pack(side="left", padx=8)
        ecart_total = total_budget - total_reel
        ctk.CTkLabel(total_row, text=f"{ecart_total:,.0f}".replace(",", " "), font=font(12, "bold"),
                     text_color="#0B1220", width=120, anchor="w").pack(side="left", padx=8)
        pct_total = (total_reel / total_budget * 100) if total_budget > 0 else 0
        ctk.CTkLabel(total_row, text=f"{pct_total:.1f}%", font=font(12, "bold"),
                     text_color="#0B1220", anchor="e").pack(side="right", padx=16)

        for label, val, color in [
            ("Budget total du mois", f"{total_budget:,.0f} FCFA".replace(",", " "), COLORS["gold"]),
            ("Dépenses réelles", f"{total_reel:,.0f} FCFA".replace(",", " "), COLORS["danger"]),
            ("Écart", f"{ecart_total:,.0f} FCFA".replace(",", " "),
             COLORS["success"] if ecart_total >= 0 else COLORS["danger"]),
        ]:
            c = ctk.CTkFrame(self.totals_row, fg_color=COLORS["bg_card"], corner_radius=10,
                              border_width=1, border_color=COLORS["border"])
            c.pack(side="left", padx=(0, 10), ipady=8, ipadx=16)
            ctk.CTkLabel(c, text=label.upper(), font=font(10, "bold"),
                         text_color=COLORS["text_secondary"]).pack(anchor="w", padx=14, pady=(6, 0))
            ctk.CTkLabel(c, text=val, font=font(15, "bold"), text_color=color).pack(
                anchor="w", padx=14, pady=(0, 6))

    def _build_budget_row(self, categorie, budget, reel, ecart, pct, alerte, alerte_color, idx,
                           mois_num, annee):
        bg = COLORS["bg_card"] if idx % 2 == 0 else COLORS["bg_dark"]
        row = ctk.CTkFrame(self.table_frame, fg_color=bg, corner_radius=8, height=44)
        row.pack(fill="x", pady=1)
        row.pack_propagate(False)

        ctk.CTkLabel(row, text=categorie, font=font(11), text_color=COLORS["text_primary"],
                     width=220, anchor="w").pack(side="left", padx=8)

        budget_entry = ctk.CTkEntry(row, width=110, height=30, corner_radius=6,
                                     fg_color=COLORS["bg_input"], border_width=0, font=font(11))
        budget_entry.insert(0, str(int(budget)))
        budget_entry.pack(side="left", padx=8)

        def save_budget(event=None, cat=categorie, entry=budget_entry, m=self.mois_var.get(), a=annee):
            try:
                new_val = float(entry.get() or 0)
            except ValueError:
                return
            existing = self.db.fetchone(
                "SELECT id FROM budget_categories WHERE categorie=? AND mois=? AND annee=?", (cat, m, a))
            if existing:
                self.db.execute("UPDATE budget_categories SET budget_prevu=? WHERE id=?",
                                 (new_val, existing["id"]))
            else:
                self.db.execute(
                    "INSERT INTO budget_categories (categorie, mois, annee, budget_prevu) VALUES (?,?,?,?)",
                    (cat, m, a, new_val))
            self.refresh()

        budget_entry.bind("<Return>", save_budget)
        budget_entry.bind("<FocusOut>", save_budget)

        ctk.CTkLabel(row, text=f"{reel:,.0f}".replace(",", " "), font=font(11),
                     text_color=COLORS["text_primary"], width=130, anchor="w").pack(side="left", padx=8)
        ecart_color = COLORS["success"] if ecart >= 0 else COLORS["danger"]
        ctk.CTkLabel(row, text=f"{ecart:,.0f}".replace(",", " "), font=font(11, "bold"),
                     text_color=ecart_color, width=120, anchor="w").pack(side="left", padx=8)
        ctk.CTkLabel(row, text=f"{pct:.1f}%", font=font(11), text_color=COLORS["text_secondary"],
                     width=90, anchor="w").pack(side="left", padx=8)

        status_badge(row, alerte, alerte_color).pack(side="right", padx=16)
