"""
MK Suite - Composants d'interface réutilisables
"""
import customtkinter as ctk
from ui.theme import COLORS, font, title_font, card, icon_badge


class KPICard(ctk.CTkFrame):
    """Carte indicateur avec animation de compteur montant — cliquable si on_click est fourni"""
    def __init__(self, parent, label, value, suffix="", icon="", accent=None, subtitle=None,
                 on_click=None, **kwargs):
        super().__init__(parent, fg_color=COLORS["bg_card"], corner_radius=16,
                          border_width=1, border_color=COLORS["border"], **kwargs)
        accent = accent or COLORS["gold"]
        self._accent = accent
        self._on_click = on_click
        self.bind("<Enter>", self._on_enter)
        self.bind("<Leave>", self._on_leave)
        if on_click:
            self.configure(cursor="hand2")
            self.bind("<Button-1>", lambda e: on_click())

        top = ctk.CTkFrame(self, fg_color="transparent")
        top.pack(fill="x", padx=18, pady=(18, 0))

        icon_badge(top, icon, accent, size=36, icon_size=15).pack(side="left")

        lbl = ctk.CTkLabel(top, text=label.upper(), font=font(11, "bold"),
                            text_color=COLORS["text_secondary"])
        lbl.pack(side="left", padx=(10, 0))

        self.value_lbl = ctk.CTkLabel(self, text="0" + suffix, font=title_font(28),
                                       text_color=COLORS["text_primary"], anchor="w")
        self.value_lbl.pack(fill="x", padx=18, pady=(6, 4))

        if subtitle:
            sub = ctk.CTkLabel(self, text=subtitle, font=font(11), text_color=COLORS["text_muted"],
                                anchor="w")
            sub.pack(fill="x", padx=18, pady=(0, 16))
        else:
            ctk.CTkFrame(self, fg_color="transparent", height=16).pack()

        # Propage le curseur main et le clic a tous les enfants (labels, icone...)
        if on_click:
            for w in (top, lbl, self.value_lbl):
                w.configure(cursor="hand2")
                w.bind("<Button-1>", lambda e: on_click())
            for w in top.winfo_children():
                w.configure(cursor="hand2")
                w.bind("<Button-1>", lambda e: on_click())

        self._animate_value(value, suffix)

    def _on_enter(self, event=None):
        self.configure(border_color=self._accent)

    def _on_leave(self, event=None):
        self.configure(border_color=COLORS["border"])

    def _animate_value(self, target, suffix, step=0):
        steps = 20
        current = int(target * (step / steps))
        if isinstance(target, float):
            self.value_lbl.configure(text=f"{current:,}".replace(",", " ") + suffix)
        else:
            self.value_lbl.configure(text=f"{current:,}".replace(",", " ") + suffix)
        if step < steps:
            self.after(15, lambda: self._animate_value(target, suffix, step + 1))
        else:
            self.value_lbl.configure(text=f"{target:,.0f}".replace(",", " ") + suffix)


def status_badge(parent, text, status_type="info"):
    color_map = {
        "success": COLORS["success"],
        "warning": COLORS["warning"],
        "danger": COLORS["danger"],
        "info": COLORS["info"],
        "neutral": COLORS["text_muted"],
    }
    color = color_map.get(status_type, COLORS["info"])
    badge = ctk.CTkFrame(parent, fg_color=color, corner_radius=8, height=24)
    lbl = ctk.CTkLabel(badge, text=text, font=font(11, "bold"), text_color="#0B1220")
    lbl.pack(padx=10, pady=2)
    return badge


class DataTable(ctk.CTkScrollableFrame):
    """Table de données stylée avec en-têtes et lignes zébrées"""
    def __init__(self, parent, columns, col_widths=None, **kwargs):
        super().__init__(parent, fg_color="transparent", **kwargs)
        self.columns = columns
        self.col_widths = col_widths or [1] * len(columns)
        self.rows_frame = []
        self._build_header()

    def _build_header(self):
        header = ctk.CTkFrame(self, fg_color=COLORS["bg_sidebar"], corner_radius=8, height=40)
        header.pack(fill="x", pady=(0, 4))
        header.grid_columnconfigure(tuple(range(len(self.columns))), weight=1)
        for i, col in enumerate(self.columns):
            lbl = ctk.CTkLabel(header, text=col.upper(), font=font(11, "bold"),
                                text_color=COLORS["gold"], anchor="w")
            lbl.grid(row=0, column=i, sticky="ew", padx=12, pady=10)
            header.grid_columnconfigure(i, weight=self.col_widths[i])

    def add_row(self, values, on_click=None, tags=None):
        idx = len(self.rows_frame)
        bg = COLORS["bg_card"] if idx % 2 == 0 else COLORS["bg_dark"]
        row = ctk.CTkFrame(self, fg_color=bg, corner_radius=8, height=44)
        row.pack(fill="x", pady=2)
        row.grid_columnconfigure(tuple(range(len(values))), weight=1)
        for i, val in enumerate(values):
            lbl = ctk.CTkLabel(row, text=str(val), font=font(12), text_color=COLORS["text_primary"],
                                anchor="w")
            lbl.grid(row=0, column=i, sticky="ew", padx=12, pady=10)
            row.grid_columnconfigure(i, weight=self.col_widths[i])
            if on_click:
                lbl.bind("<Button-1>", lambda e, v=values: on_click(v))
        if on_click:
            row.bind("<Button-1>", lambda e, v=values: on_click(v))
        self.rows_frame.append(row)
        return row

    def clear(self):
        for row in self.rows_frame:
            row.destroy()
        self.rows_frame = []


def show_context_menu(widget, event, items):
    """Affiche un menu contextuel (clic droit) à la position du curseur.
    items : liste de tuples (libellé, fonction) — utiliser (None, None) pour un séparateur."""
    import tkinter as tk
    menu = tk.Menu(widget, tearoff=0, bg=COLORS["bg_card"], fg=COLORS["text_primary"],
                    activebackground=COLORS["gold"], activeforeground="#0B1220",
                    borderwidth=0, font=("Segoe UI", 10))
    for label, command in items:
        if label is None:
            menu.add_separator()
        else:
            menu.add_command(label=label, command=command)
    try:
        menu.tk_popup(event.x_root, event.y_root)
    finally:
        menu.grab_release()


def confirm_delete(parent, title, message, on_confirm):
    """Ouvre une popup de confirmation avant toute suppression définitive.
    on_confirm est appelé uniquement si l'utilisateur clique sur Supprimer."""
    import customtkinter as ctk
    from ui.theme import primary_button, secondary_button, danger_button

    dialog = ctk.CTkToplevel(parent)
    dialog.title("Confirmation")
    dialog.geometry("380x200")
    dialog.configure(fg_color=COLORS["bg_dark"])
    dialog.transient(parent)
    dialog.grab_set()
    dialog.resizable(False, False)

    ctk.CTkLabel(dialog, text="⚠️", font=font(28)).pack(pady=(24, 4))
    ctk.CTkLabel(dialog, text=title, font=font(14, "bold"),
                 text_color=COLORS["text_primary"]).pack(pady=(0, 4))
    ctk.CTkLabel(dialog, text=message, font=font(11), text_color=COLORS["text_secondary"],
                 wraplength=320, justify="center").pack(pady=(0, 16), padx=20)

    row = ctk.CTkFrame(dialog, fg_color="transparent")
    row.pack()

    def confirm():
        dialog.destroy()
        on_confirm()

    secondary_button(row, "Annuler", command=dialog.destroy, width=130).pack(side="left", padx=6)
    danger_button(row, "Supprimer définitivement", command=confirm, width=170,
                  fg_color=COLORS["danger"], text_color="white").pack(side="left", padx=6)


def section_title(parent, text, subtitle=None):
    frame = ctk.CTkFrame(parent, fg_color="transparent")
    ctk.CTkLabel(frame, text=text, font=title_font(22), text_color=COLORS["text_primary"],
                 anchor="w").pack(anchor="w")
    if subtitle:
        ctk.CTkLabel(frame, text=subtitle, font=font(12), text_color=COLORS["text_secondary"],
                     anchor="w").pack(anchor="w", pady=(2, 0))
    return frame
