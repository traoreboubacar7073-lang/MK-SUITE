"""
MK Suite - Système de design premium
Palette : Bleu marine profond + Or, cohérent avec l'identité MK Entreprise
"""
import customtkinter as ctk

# ---------- Palette de couleurs ----------
COLORS = {
    "bg_dark":        "#0B1220",   # Fond principal, bleu nuit
    "bg_sidebar":     "#0A0E1A",   # Sidebar encore plus sombre
    "bg_card":        "#141C2E",   # Cartes / panneaux
    "bg_card_hover":  "#1B2438",
    "bg_input":       "#1B2438",

    "gold":           "#D4AF37",   # Or - accent principal
    "gold_light":     "#E8C766",
    "gold_dark":      "#B8952E",

    "text_primary":   "#F4F6F9",
    "text_secondary": "#8B94A8",
    "text_muted":     "#5A6478",

    "success":        "#3DD68C",
    "warning":        "#F5A623",
    "danger":         "#E5484D",
    "info":           "#4A9EFF",

    "border":         "#232E45",
}

FONT_FAMILY = "Segoe UI"


def apply_theme():
    ctk.set_appearance_mode("dark")
    ctk.set_default_color_theme("dark-blue")


def font(size=13, weight="normal"):
    return ctk.CTkFont(family=FONT_FAMILY, size=size, weight=weight)


def title_font(size=24):
    return ctk.CTkFont(family=FONT_FAMILY, size=size, weight="bold")


def card(parent, **kwargs):
    defaults = dict(fg_color=COLORS["bg_card"], corner_radius=14, border_width=1,
                     border_color=COLORS["border"])
    defaults.update(kwargs)
    return ctk.CTkFrame(parent, **defaults)


def primary_button(parent, text, command=None, **kwargs):
    defaults = dict(
        fg_color=COLORS["gold"], hover_color=COLORS["gold_light"],
        text_color="#0B1220", font=font(13, "bold"), corner_radius=10, height=40,
    )
    defaults.update(kwargs)
    return ctk.CTkButton(parent, text=text, command=command, **defaults)


def secondary_button(parent, text, command=None, **kwargs):
    defaults = dict(
        fg_color="transparent", hover_color=COLORS["bg_card_hover"],
        text_color=COLORS["text_primary"], border_width=1, border_color=COLORS["border"],
        font=font(13), corner_radius=10, height=40,
    )
    defaults.update(kwargs)
    return ctk.CTkButton(parent, text=text, command=command, **defaults)


def danger_button(parent, text, command=None, **kwargs):
    defaults = dict(
        fg_color="transparent", hover_color=COLORS["danger"],
        text_color=COLORS["danger"], border_width=1, border_color=COLORS["danger"],
        font=font(12), corner_radius=8, height=32,
    )
    defaults.update(kwargs)
    return ctk.CTkButton(parent, text=text, command=command, **defaults)


def search_entry(parent, textvariable, placeholder="🔍 Rechercher...", **kwargs):
    """Champ de recherche stylé qui affiche une bordure dorée au focus, pour un
    retour visuel clair sur l'endroit où l'utilisateur est en train de taper."""
    defaults = dict(height=42, corner_radius=10, fg_color=COLORS["bg_input"],
                     border_color=COLORS["border"], border_width=1, font=font(13))
    defaults.update(kwargs)
    entry = ctk.CTkEntry(parent, textvariable=textvariable, placeholder_text=placeholder, **defaults)
    entry.bind("<FocusIn>", lambda e: entry.configure(border_color=COLORS["gold"]))
    entry.bind("<FocusOut>", lambda e: entry.configure(border_color=COLORS["border"]))
    return entry


def icon_badge(parent, icon, color=None, size=40, icon_size=17):
    """Badge circulaire coloré avec une icône au centre — utilisé pour les KPIs
    et les en-têtes de page pour donner un aspect plus 'logiciel pro'."""
    color = color or COLORS["gold"]
    badge = ctk.CTkFrame(parent, fg_color=color, corner_radius=size // 2, width=size, height=size)
    badge.pack_propagate(False)
    ctk.CTkLabel(badge, text=icon, font=font(icon_size), text_color="#0B1220").pack(expand=True)
    return badge
