"""
MK Suite - Sauvegarde et restauration
Exporte une copie complète de la base de données (mk_entreprise.db) vers un
emplacement choisi par l'utilisateur (clé USB, dossier synchronisé Google
Drive/OneDrive...) et permet de restaurer une sauvegarde précédente — le
filet de sécurité si l'ordinateur est perdu, volé, ou réinstallé.

Pendant, côté ordinateur, de BackupService côté téléphone
(lib/services/backup_service.dart) — en plus simple ici : la base SQLite
est un seul fichier, une copie suffit (pas besoin d'un export JSON table
par table comme sur mobile, où chaque sauvegarde doit passer par le
sélecteur de partage natif plutôt que par un accès direct au fichier).
"""
import os
import shutil
import sqlite3
import sys
from datetime import datetime
from tkinter import filedialog, messagebox
import customtkinter as ctk
from ui.theme import COLORS, font, card, primary_button, secondary_button
from ui.widgets import section_title


class SauvegardeView(ctk.CTkScrollableFrame):
    def __init__(self, parent, db, **kwargs):
        super().__init__(parent, fg_color="transparent", **kwargs)
        self.db = db
        self.build()

    def build(self):
        header = ctk.CTkFrame(self, fg_color="transparent")
        header.pack(fill="x", padx=4, pady=(4, 16))
        section_title(header, "Sauvegarde", "Protège toutes tes données MK Suite").pack(side="left")

        secondary_button(self, "Importer les coordonnées entreprise…",
                         command=self._import_profile).pack(anchor="w", padx=4, pady=(0, 12))

        # -------- Export --------
        export_card = card(self, fg_color=COLORS["bg_card"])
        export_card.pack(fill="x", padx=4, pady=(0, 16))
        inner = ctk.CTkFrame(export_card, fg_color="transparent")
        inner.pack(fill="x", padx=20, pady=18)
        ctk.CTkLabel(inner, text="💾 Exporter une sauvegarde", font=font(15, "bold"),
                     text_color=COLORS["text_primary"]).pack(anchor="w")
        ctk.CTkLabel(
            inner,
            text="Enregistre une copie complète de toutes tes données (clients, devis, factures, "
                 "reçus, dépenses, employés...) dans un seul fichier, à garder en lieu sûr — clé USB, "
                 "dossier synchronisé Google Drive/OneDrive, ou tout autre emplacement de ton choix.",
            font=font(11), text_color=COLORS["text_secondary"], wraplength=760, justify="left",
        ).pack(anchor="w", pady=(4, 14))
        primary_button(inner, "💾 Enregistrer une sauvegarde…", command=self._exporter).pack(anchor="w")

        # -------- Restauration --------
        restore_card = card(self, fg_color=COLORS["bg_card"])
        restore_card.pack(fill="x", padx=4, pady=(0, 16))
        inner2 = ctk.CTkFrame(restore_card, fg_color="transparent")
        inner2.pack(fill="x", padx=20, pady=18)
        ctk.CTkLabel(inner2, text="♻️ Restaurer une sauvegarde", font=font(15, "bold"),
                     text_color=COLORS["text_primary"]).pack(anchor="w")
        ctk.CTkLabel(
            inner2,
            text="Remplace TOUTES les données actuelles par celles d'un fichier de sauvegarde "
                 "précédemment exporté. À utiliser avec précaution : les données présentes sur cet "
                 "ordinateur avant la restauration seront perdues.",
            font=font(11), text_color=COLORS["danger"], wraplength=760, justify="left",
        ).pack(anchor="w", pady=(4, 14))
        secondary_button(inner2, "♻️ Choisir un fichier de sauvegarde…", command=self._restaurer).pack(anchor="w")

        # -------- Emplacement actuel --------
        info_card = ctk.CTkFrame(self, fg_color=COLORS["bg_input"], corner_radius=10)
        info_card.pack(fill="x", padx=4)
        ctk.CTkLabel(
            info_card, text=f"📁 Base de données actuelle : {self.db.db_path}",
            font=font(11), text_color=COLORS["text_muted"], wraplength=900, justify="left",
        ).pack(anchor="w", padx=16, pady=10)

    def _import_profile(self):
        path = filedialog.askopenfilename(filetypes=[("Profil entreprise", "*.json")])
        if not path:
            return
        try:
            from modules.company_profile import import_profile
            from modules.pdf_generator import ENTREPRISE
            ENTREPRISE.clear()
            ENTREPRISE.update(import_profile(path))
            messagebox.showinfo("Coordonnées", "Coordonnées enregistrées sur cet ordinateur.")
        except (ValueError, OSError) as exc:
            messagebox.showerror("Coordonnées", str(exc))

    def _exporter(self):
        horodatage = datetime.now().strftime("%Y-%m-%d_%Hh%M")
        default_name = f"mk-suite-sauvegarde-{horodatage}.db"
        dest = filedialog.asksaveasfilename(
            defaultextension=".db", initialfile=default_name,
            filetypes=[("Base de données MK Suite", "*.db")],
            title="Enregistrer la sauvegarde")
        if not dest:
            return
        try:
            with self.db.lock:
                self.db.conn.commit()
                with sqlite3.connect(dest) as target:
                    self.db.conn.backup(target)
            messagebox.showinfo("Sauvegarde enregistrée", f"Sauvegarde enregistrée avec succès :\n{dest}")
        except Exception as e:
            messagebox.showerror("Erreur", f"Impossible d'enregistrer la sauvegarde :\n{e}")

    def _restaurer(self):
        src = filedialog.askopenfilename(
            filetypes=[("Base de données MK Suite", "*.db"), ("Tous les fichiers", "*.*")],
            title="Choisir un fichier de sauvegarde à restaurer")
        if not src:
            return
        confirm = messagebox.askyesno(
            "Confirmer la restauration",
            "Toutes les données actuellement présentes sur cet ordinateur seront remplacées par "
            "celles de ce fichier de sauvegarde. Cette action ne peut pas être annulée.\n\n"
            "MK Suite va se fermer pour terminer la restauration — tu devras le relancer toi-même "
            "ensuite. Continuer ?")
        if not confirm:
            return

        # On copie d'abord la sauvegarde vers un fichier temporaire (sans toucher
        # à la base actuellement ouverte), et on ne remplace le fichier réel
        # qu'à la toute fin par un remplacement atomique (os.replace) — ainsi,
        # si la copie échoue en cours de route (disque plein, fichier source
        # invalide...), la base de données existante n'est jamais laissée à
        # moitié écrite/corrompue.
        tmp_path = self.db.db_path + ".tmp_restore"
        try:
            with sqlite3.connect(src) as source:
                if source.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
                    raise ValueError("Sauvegarde SQLite endommagée")
                tables = {r[0] for r in source.execute("SELECT name FROM sqlite_master WHERE type='table'")}
                if not {"clients", "devis", "factures"} <= tables:
                    raise ValueError("Ce fichier n'est pas une sauvegarde MK Suite")
                with sqlite3.connect(tmp_path) as target:
                    source.backup(target)
            with self.db.lock:
                self.db.conn.commit()
                self.db.conn.close()
            os.replace(tmp_path, self.db.db_path)
        except Exception as e:
            if os.path.exists(tmp_path):
                try:
                    os.remove(tmp_path)
                except Exception:
                    pass
            messagebox.showerror(
                "Erreur",
                f"Impossible de restaurer cette sauvegarde :\n{e}\n\n"
                "Redémarre MK Suite pour continuer — tes données n'ont pas été modifiées.")
            sys.exit(0)

        messagebox.showinfo(
            "Restauration terminée",
            "La sauvegarde a été restaurée avec succès. MK Suite va maintenant se fermer — "
            "relance l'application pour voir les données restaurées.")
        sys.exit(0)
