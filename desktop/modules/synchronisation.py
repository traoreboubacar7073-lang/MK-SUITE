"""
MK Suite - Module Synchronisation
Synchronise les données entre cet ordinateur et l'application mobile (téléphone),
en Wi-Fi local uniquement — aucune connexion internet, aucun serveur distant.

Fonctionnement, exactement le même des deux côtés (voir modules/sync_service.py) :
  - un des deux appareils démarre son serveur local (bouton "Démarrer le serveur") ;
  - l'autre appareil entre son adresse IP et appuie sur "Synchroniser" ;
  - les données des deux appareils sont fusionnées (la modification la plus
    récente l'emporte), puis les DEUX appareils ont exactement les mêmes
    données, quel que soit celui qui a démarré la synchro.
"""
import queue
import threading
import customtkinter as ctk
from datetime import datetime

from ui.theme import COLORS, font, title_font, card, primary_button, secondary_button, search_entry
from ui.widgets import section_title
from modules.sync_service import SyncServer, can_reach, sync_with, SYNC_PORT
from modules.sync_peers import charger_peers, enregistrer_peer, supprimer_peer


class SynchronisationView(ctk.CTkScrollableFrame):
    def __init__(self, parent, db, **kwargs):
        super().__init__(parent, fg_color="transparent", **kwargs)
        self.db = db
        # Le serveur doit survivre à la navigation entre pages (show_page()
        # détruit et recrée cette vue à chaque fois) — on le range donc sur
        # le DatabaseManager, seul objet partagé qui vit aussi longtemps que
        # l'application, plutôt que sur self (qui, lui, est jeté à chaque
        # changement de page).
        if not hasattr(db, "_sync_server"):
            db._sync_server = SyncServer(db)
        self.server = db._sync_server
        # Pré-remplissage : l'adresse enregistrée la plus récente (persistée
        # sur disque, survit donc aussi à un redémarrage de l'application) —
        # à défaut, la dernière utilisée dans CETTE session (mémoire seule,
        # voir toggle_server/do_sync plus bas) si l'utilisateur avait déjà
        # tapé une adresse avant que cette fonctionnalité n'existe.
        peers_enregistres = charger_peers()
        valeur_initiale = peers_enregistres[0]["ip"] if peers_enregistres else getattr(db, "_sync_last_peer", "")
        self.peer_var = ctk.StringVar(value=valeur_initiale)
        self.check_result = None  # None = pas encore vérifié, True/False = résultat
        self.busy = False
        # Tkinter n'est pas thread-safe : les threads de fond (vérification,
        # synchro) ne touchent JAMAIS directement aux widgets ni à self.after
        # — ils déposent seulement un callback dans cette file, et c'est une
        # boucle sur le thread principal (_poll_queue, ci-dessous) qui les
        # exécute. Appeler self.after() depuis un autre thread est un piège
        # classique : ça lève parfois "main thread is not in main loop" selon
        # le moment exact, une race difficile à reproduire de façon fiable.
        self._ui_queue = queue.Queue()
        self._destroyed = False
        self.bind("<Destroy>", self._on_destroy)
        self.build()
        self._poll_queue()

    def _on_destroy(self, event):
        if event.widget is self:
            self._destroyed = True

    def _poll_queue(self):
        if self._destroyed:
            return
        try:
            while True:
                callback = self._ui_queue.get_nowait()
                try:
                    callback()
                except Exception:
                    pass
        except queue.Empty:
            pass
        if not self._destroyed:
            self.after(80, self._poll_queue)

    # ---------------- Construction ----------------

    def build(self):
        header = ctk.CTkFrame(self, fg_color="transparent")
        header.pack(fill="x", padx=4, pady=(4, 8))
        section_title(header, "Synchronisation",
                      "Échange tes données avec l'application mobile, en Wi-Fi local").pack(side="left")

        info_card = card(self, fg_color=COLORS["bg_input"])
        info_card.pack(fill="x", padx=4, pady=(0, 16))
        ctk.CTkLabel(
            info_card,
            text="ℹ️ Les deux appareils doivent être connectés au MÊME réseau Wi-Fi — aucune donnée "
                 "ne passe par internet. En cas de conflit, la modification la plus récente est "
                 "conservée. Les suppressions (et les restaurations depuis la corbeille) se "
                 "propagent aussi automatiquement.",
            font=font(11), text_color=COLORS["text_secondary"], wraplength=900,
            justify="left").pack(anchor="w", padx=16, pady=10)

        # ----- Section serveur -----
        server_card = card(self)
        server_card.pack(fill="x", padx=4, pady=(0, 16))
        inner = ctk.CTkFrame(server_card, fg_color="transparent")
        inner.pack(fill="x", padx=18, pady=16)

        row1 = ctk.CTkFrame(inner, fg_color="transparent")
        row1.pack(fill="x")
        ctk.CTkLabel(row1, text="Recevoir une synchronisation", font=font(14, "bold"),
                     text_color=COLORS["text_primary"], anchor="w").pack(side="left")
        self.server_badge = ctk.CTkLabel(row1, text="", font=font(11, "bold"), corner_radius=8)
        self.server_badge.pack(side="left", padx=(10, 0))

        ctk.CTkLabel(inner, text="Démarre le serveur ici pour que le téléphone puisse t'envoyer sa "
                                   "synchronisation. Laisse cet écran ouvert pendant l'échange.",
                     font=font(11), text_color=COLORS["text_secondary"], anchor="w",
                     wraplength=820, justify="left").pack(anchor="w", pady=(4, 10))

        row2 = ctk.CTkFrame(inner, fg_color="transparent")
        row2.pack(fill="x")
        self.address_lbl = ctk.CTkLabel(row2, text="", font=font(13, "bold"),
                                         text_color=COLORS["gold"], anchor="w")
        self.address_lbl.pack(side="left")
        self.server_btn = primary_button(row2, "", command=self.toggle_server, width=200)
        self.server_btn.pack(side="right")

        from modules.glass_ai_settings import open_scanner_settings
        secondary_button(inner, "Configurer le scanner IA manuscrit…",
                         command=lambda: open_scanner_settings(self)).pack(anchor="w", pady=(12, 0))
        ctk.CTkLabel(inner, text="Option distincte : le scanner IA utilise Internet ; la synchronisation reste locale.",
                     font=font(10), wraplength=820).pack(anchor="w", pady=(4, 0))

        # ----- Section connexion à l'autre appareil -----
        peer_card = card(self)
        peer_card.pack(fill="x", padx=4, pady=(0, 16))
        pinner = ctk.CTkFrame(peer_card, fg_color="transparent")
        pinner.pack(fill="x", padx=18, pady=16)

        ctk.CTkLabel(pinner, text="Synchroniser avec un autre appareil", font=font(14, "bold"),
                     text_color=COLORS["text_primary"], anchor="w").pack(anchor="w")
        ctk.CTkLabel(pinner, text="Entre l'adresse IP affichée sur l'autre appareil (celui-ci doit "
                                   "avoir démarré son serveur), puis synchronise.",
                     font=font(11), text_color=COLORS["text_secondary"], anchor="w",
                     wraplength=820, justify="left").pack(anchor="w", pady=(4, 10))

        row3 = ctk.CTkFrame(pinner, fg_color="transparent")
        row3.pack(fill="x")
        self.peer_entry = search_entry(row3, self.peer_var, placeholder="ex: 192.168.1.24",
                                        width=220)
        self.peer_entry.pack(side="left")
        self.peer_entry.bind("<KeyRelease>", lambda e: self._reset_check())

        self.check_btn = secondary_button(row3, "Vérifier", command=self.check_peer, width=120)
        self.check_btn.pack(side="left", padx=(10, 0))
        self.sync_btn = primary_button(row3, "🔄 Synchroniser maintenant", command=self.do_sync, width=220)
        self.sync_btn.pack(side="left", padx=(10, 0))

        self.check_status_lbl = ctk.CTkLabel(pinner, text="", font=font(11, "bold"), anchor="w")
        self.check_status_lbl.pack(anchor="w", pady=(8, 0))

        # ----- Adresses enregistrées (raccourcis) -----
        # Ni l'un ni l'autre n'est packé ici : _refresh_peers_row() gère les
        # deux (et leur ORDRE d'affichage — libellé d'abord, puis la rangée)
        # à chaque appel, y compris le tout premier, pour ne jamais dépendre
        # de l'ordre d'empaquetage initial.
        self.peers_label = ctk.CTkLabel(pinner, text="Adresses enregistrées", font=font(10, "bold"),
                                          text_color=COLORS["text_muted"], anchor="w")
        self.peers_row = ctk.CTkFrame(pinner, fg_color="transparent")
        self._refresh_peers_row()

        # ----- Journal -----
        log_card = card(self)
        log_card.pack(fill="both", expand=True, padx=4, pady=(0, 16))
        linner = ctk.CTkFrame(log_card, fg_color="transparent")
        linner.pack(fill="both", expand=True, padx=18, pady=16)
        ctk.CTkLabel(linner, text="Journal", font=font(14, "bold"),
                     text_color=COLORS["text_primary"], anchor="w").pack(anchor="w", pady=(0, 8))
        self.log_frame = ctk.CTkFrame(linner, fg_color="transparent")
        self.log_frame.pack(fill="both", expand=True)
        self._log_empty()

        self._refresh_server_ui()

    def _log_empty(self):
        for w in self.log_frame.winfo_children():
            w.destroy()
        ctk.CTkLabel(self.log_frame, text="Aucune synchronisation effectuée pour l'instant.",
                     font=font(11), text_color=COLORS["text_muted"]).pack(anchor="w", pady=12)

    # ---------------- Serveur ----------------

    def _refresh_server_ui(self):
        if self.server.is_running:
            self.server_badge.configure(text="● Actif", text_color=COLORS["success"])
            addr = getattr(self.db, "_sync_last_local_ip", None)
            self.address_lbl.configure(
                text=f"En écoute sur {addr}:{SYNC_PORT}" if addr else f"En écoute sur le port {SYNC_PORT}")
            self.server_btn.configure(text="Arrêter le serveur", fg_color=COLORS["danger"],
                                       hover_color="#c73e42")
        else:
            self.server_badge.configure(text="● Arrêté", text_color=COLORS["text_muted"])
            self.address_lbl.configure(text="Le serveur n'est pas démarré")
            self.server_btn.configure(text="Démarrer le serveur", fg_color=COLORS["gold"],
                                       hover_color=COLORS["gold_light"])

    def toggle_server(self):
        if self.server.is_running:
            self.server.stop()
            self._refresh_server_ui()
            return
        ip = self.server.start()
        if ip is None and not self.server.is_running:
            self._add_log_line("❌ Impossible de démarrer le serveur (le port est peut-être déjà "
                                "utilisé par une autre instance de MK Suite).", error=True)
        else:
            self.db._sync_last_local_ip = ip
        self._refresh_server_ui()

    # ---------------- Vérification / synchro avec un pair ----------------

    def _reset_check(self):
        self.check_result = None
        self.check_status_lbl.configure(text="")

    def _refresh_peers_row(self):
        for w in self.peers_row.winfo_children():
            w.destroy()
        self.peers_label.pack_forget()
        self.peers_row.pack_forget()
        peers = charger_peers()
        if not peers:
            return
        self.peers_label.pack(anchor="w", pady=(12, 4))
        self.peers_row.pack(anchor="w", fill="x")
        for p in peers:
            ip = p["ip"]
            chip = ctk.CTkFrame(self.peers_row, fg_color=COLORS["bg_input"], corner_radius=8)
            chip.pack(side="left", padx=(0, 8), pady=2)
            ctk.CTkButton(
                chip, text=ip, font=font(11), fg_color="transparent", hover_color=COLORS["bg_card_hover"],
                text_color=COLORS["text_primary"], corner_radius=8, height=28, width=max(90, len(ip) * 8),
                command=lambda ip=ip: self._use_peer(ip),
            ).pack(side="left", padx=(4, 0), pady=2)
            ctk.CTkButton(
                chip, text="✕", font=font(10), fg_color="transparent", hover_color=COLORS["bg_card_hover"],
                text_color=COLORS["text_muted"], corner_radius=8, height=28, width=24,
                command=lambda ip=ip: self._forget_peer(ip),
            ).pack(side="left", padx=(0, 2), pady=2)

    def _use_peer(self, ip):
        self.peer_var.set(ip)
        self._reset_check()

    def _forget_peer(self, ip):
        supprimer_peer(ip)
        self._refresh_peers_row()

    def _set_busy(self, busy):
        self.busy = busy
        state = "disabled" if busy else "normal"
        self.check_btn.configure(state=state)
        self.sync_btn.configure(state=state)
        self.server_btn.configure(state=state)

    def check_peer(self):
        host = self.peer_var.get().strip()
        if not host:
            self.check_status_lbl.configure(text="Entre d'abord une adresse IP.", text_color=COLORS["warning"])
            return
        self._set_busy(True)
        self.check_status_lbl.configure(text="Vérification en cours…", text_color=COLORS["text_secondary"])

        def worker():
            ok = can_reach(host)
            self._ui_queue.put(lambda: self._on_check_done(host, ok))

        threading.Thread(target=worker, daemon=True).start()

    def _on_check_done(self, host, ok):
        self._set_busy(False)
        self.check_result = ok
        if ok:
            self.check_status_lbl.configure(text=f"✅ MK Suite répond bien à {host}.",
                                             text_color=COLORS["success"])
            enregistrer_peer(host)
            self._refresh_peers_row()
        else:
            self.check_status_lbl.configure(
                text=f"❌ Aucune réponse de {host} — vérifie que l'autre appareil a démarré son "
                     "serveur et que les deux sont sur le même Wi-Fi.",
                text_color=COLORS["danger"])

    def do_sync(self):
        host = self.peer_var.get().strip()
        if not host:
            self.check_status_lbl.configure(text="Entre d'abord une adresse IP.", text_color=COLORS["warning"])
            return
        self.db._sync_last_peer = host
        self._set_busy(True)
        self._add_log_line(f"⏳ Synchronisation avec {host} en cours…")

        def worker():
            try:
                log = sync_with(self.db, host)
                self._ui_queue.put(lambda: self._on_sync_done(host, log, None))
            except Exception as e:
                self._ui_queue.put(lambda: self._on_sync_done(host, None, e))

        threading.Thread(target=worker, daemon=True).start()

    def _on_sync_done(self, host, log, error):
        self._set_busy(False)
        if error is not None:
            self._add_log_line(f"❌ Échec de la synchronisation avec {host} : {error}", error=True)
            return
        self._add_log_line(f"✅ Synchronisation avec {host} terminée — "
                            f"{log.inserted} nouvelle(s) ligne(s), {log.updated} mise(s) à jour.")
        for line in log.lines:
            self._add_log_line(f"    · {line}")
        enregistrer_peer(host)
        self._refresh_peers_row()

    # ---------------- Journal ----------------

    def _add_log_line(self, text, error=False):
        # Efface le message "aucune synchro" au premier vrai événement.
        children = self.log_frame.winfo_children()
        if len(children) == 1 and not getattr(self, "_has_real_log", False):
            for w in children:
                w.destroy()
            self._has_real_log = True

        row = ctk.CTkFrame(self.log_frame, fg_color="transparent")
        row.pack(fill="x", anchor="w", pady=1)
        ts = datetime.now().strftime("%H:%M:%S")
        ctk.CTkLabel(row, text=ts, font=font(10), text_color=COLORS["text_muted"],
                     width=60, anchor="w").pack(side="left")
        color = COLORS["danger"] if error else COLORS["text_primary"]
        ctk.CTkLabel(row, text=text, font=font(11), text_color=color, anchor="w",
                     wraplength=780, justify="left").pack(side="left", fill="x", expand=True)
