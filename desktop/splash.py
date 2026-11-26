"""
MK Suite - Écran de démarrage animé
Affiché brièvement au lancement : logo, barre de progression animée,
petites phrases qui changent — pour donner une vraie sensation de logiciel pro.
"""
import tkinter as tk
import customtkinter as ctk
from PIL import Image
import os
import random
from resource_path import resource_path
from ui.theme import COLORS, font, title_font

LOADING_MESSAGES = [
    "Ouverture de la base de données...",
    "Chargement des clients...",
    "Vérification des factures...",
    "Préparation du tableau de bord...",
    "Presque prêt...",
]


class SplashScreen(ctk.CTkToplevel):
    def __init__(self, master, on_ready):
        super().__init__(master)
        self.on_ready = on_ready
        self.overrideredirect(True)  # pas de barre de titre, look "splash"
        self.configure(fg_color=COLORS["bg_dark"])
        self._center(520, 340)
        self.attributes("-topmost", True)
        try:
            self.attributes("-alpha", 0.0)
        except Exception:
            pass

        container = ctk.CTkFrame(self, fg_color=COLORS["bg_dark"], border_width=1,
                                  border_color=COLORS["border"], corner_radius=18)
        container.pack(fill="both", expand=True, padx=1, pady=1)

        logo_path = resource_path("assets", "logo.png")
        if os.path.exists(logo_path):
            pil_img = Image.open(logo_path)
            self.logo_img = ctk.CTkImage(light_image=pil_img, dark_image=pil_img, size=(84, 84))
            self.logo_lbl = ctk.CTkLabel(container, image=self.logo_img, text="")
            self.logo_lbl.pack(pady=(46, 14))

        title_row = ctk.CTkFrame(container, fg_color="transparent")
        title_row.pack()
        ctk.CTkLabel(title_row, text="MK", font=ctk.CTkFont(family="Segoe UI", size=26, weight="bold"),
                     text_color=COLORS["gold"]).pack(side="left")
        ctk.CTkLabel(title_row, text="SUITE", font=ctk.CTkFont(family="Segoe UI", size=26),
                     text_color=COLORS["text_primary"]).pack(side="left", padx=(4, 0))

        ctk.CTkLabel(container, text="Gestion MK Entreprise", font=font(11),
                     text_color=COLORS["text_secondary"]).pack(pady=(2, 28))

        self.progress = ctk.CTkProgressBar(container, width=340, height=6, corner_radius=3,
                                            fg_color=COLORS["bg_input"], progress_color=COLORS["gold"])
        self.progress.pack(pady=(0, 12))
        self.progress.set(0)

        self.status_lbl = ctk.CTkLabel(container, text=LOADING_MESSAGES[0], font=font(11),
                                        text_color=COLORS["text_muted"])
        self.status_lbl.pack()

        self._step = 0
        self._progress_value = 0.0
        self.after(50, self._fade_in)
        self.after(200, self._animate)

    def _center(self, w, h):
        self.update_idletasks()
        screen_w = self.winfo_screenwidth()
        screen_h = self.winfo_screenheight()
        x = (screen_w - w) // 2
        y = (screen_h - h) // 2 - 20
        self.geometry(f"{w}x{h}+{x}+{y}")

    def _fade_in(self, alpha=0.0):
        try:
            alpha = min(alpha + 0.12, 1.0)
            self.attributes("-alpha", alpha)
            if alpha < 1.0:
                self.after(15, lambda: self._fade_in(alpha))
        except Exception:
            pass

    def _animate(self):
        self._progress_value += random.uniform(0.06, 0.14)
        if self._progress_value >= 1.0:
            self._progress_value = 1.0
        self.progress.set(self._progress_value)

        target_step = min(int(self._progress_value * len(LOADING_MESSAGES)), len(LOADING_MESSAGES) - 1)
        if target_step != self._step:
            self._step = target_step
            self.status_lbl.configure(text=LOADING_MESSAGES[self._step])

        if self._progress_value < 1.0:
            self.after(140, self._animate)
        else:
            self.after(250, self._finish)

    def _finish(self):
        try:
            self.destroy()
        finally:
            self.on_ready()
