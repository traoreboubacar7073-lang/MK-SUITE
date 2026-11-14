"""
MK Suite - Recherche globale
Cherche en même temps parmi les clients, devis, factures, reçus,
fournisseurs, employés, commandes sourcing et dépenses — pendant, côté
ordinateur, de SearchScreen côté téléphone (lib/screens/search_screen.dart).
Résultat cliquable : ferme la fenêtre de recherche et va directement à la
fiche correspondante (grâce aux paramètres `focus_id`/`focus_numero` déjà
supportés par ClientsView et DevisFacturesView).
"""
import customtkinter as ctk
from ui.theme import COLORS, font, title_font, search_entry


class RechercheGlobaleDialog(ctk.CTkToplevel):
    def __init__(self, app, db):
        super().__init__(app)
        self.app = app
        self.db = db
        self.title("Recherche globale")
        self.geometry("640x580")
        self.minsize(480, 400)
        self.configure(fg_color=COLORS["bg_dark"])
        self.transient(app)
        self.grab_set()
        self.bind("<Escape>", lambda e: self.destroy())

        header = ctk.CTkFrame(self, fg_color="transparent")
        header.pack(fill="x", padx=20, pady=(18, 8))
        ctk.CTkLabel(header, text="🔍 Recherche globale", font=title_font(18),
                     text_color=COLORS["text_primary"]).pack(anchor="w")
        ctk.CTkLabel(
            header,
            text="Clients, devis, factures, reçus, fournisseurs, employés, sourcing, dépenses",
            font=font(11), text_color=COLORS["text_secondary"],
        ).pack(anchor="w", pady=(2, 0))

        self.query_var = ctk.StringVar()
        self.query_var.trace_add("write", lambda *a: self._search())
        entry = search_entry(self, self.query_var, "Tape un nom, un numéro, un téléphone…")
        entry.pack(fill="x", padx=20, pady=(10, 10))
        entry.focus_set()

        self.results_frame = ctk.CTkScrollableFrame(self, fg_color="transparent")
        self.results_frame.pack(fill="both", expand=True, padx=20, pady=(0, 18))

        self._empty_state("Commence à taper pour chercher partout dans l'application.")

    def _empty_state(self, message):
        for w in self.results_frame.winfo_children():
            w.destroy()
        ctk.CTkLabel(self.results_frame, text=message, font=font(12),
                     text_color=COLORS["text_muted"]).pack(pady=40)

    def _search(self):
        q = self.query_var.get().strip()
        for w in self.results_frame.winfo_children():
            w.destroy()
        if not q:
            self._empty_state("Commence à taper pour chercher partout dans l'application.")
            return

        like = f"%{q}%"
        total = 0

        clients = self.db.fetchall(
            "SELECT * FROM clients WHERE nom LIKE ? OR telephone LIKE ? OR code LIKE ? "
            "ORDER BY nom LIMIT 6", (like, like, like))
        total += self._section(
            "👤 Clients", clients, lambda r: r["nom"],
            lambda r: r["telephone"] or "Sans téléphone",
            lambda r: self._goto("clients", focus_id=r["id"]))

        devis = self.db.fetchall(
            "SELECT d.*, c.nom AS client_nom FROM devis d LEFT JOIN clients c ON c.id = d.client_id "
            "WHERE d.numero LIKE ? OR d.objet LIKE ? OR c.nom LIKE ? "
            "ORDER BY d.id DESC LIMIT 6", (like, like, like))
        total += self._section(
            "📋 Devis", devis, lambda r: r["numero"],
            lambda r: r["client_nom"] or "Client non renseigné",
            lambda r: self._goto("devis", initial_mode="devis", focus_numero=r["numero"]))

        factures = self.db.fetchall(
            "SELECT f.*, c.nom AS client_nom FROM factures f LEFT JOIN clients c ON c.id = f.client_id "
            "WHERE f.numero LIKE ? OR f.description LIKE ? OR c.nom LIKE ? "
            "ORDER BY f.id DESC LIMIT 6", (like, like, like))
        total += self._section(
            "🧾 Factures", factures, lambda r: r["numero"],
            lambda r: r["client_nom"] or "Client non renseigné",
            lambda r: self._goto("devis", initial_mode="factures", focus_numero=r["numero"]))

        recus = self.db.fetchall(
            "SELECT r.*, c.nom AS client_nom FROM recus r LEFT JOIN clients c ON c.id = r.client_id "
            "WHERE r.numero LIKE ? OR r.motif LIKE ? OR c.nom LIKE ? "
            "ORDER BY r.id DESC LIMIT 6", (like, like, like))
        total += self._section(
            "🧻 Reçus", recus, lambda r: r["numero"],
            lambda r: r["client_nom"] or "Client non renseigné",
            lambda r: self._goto("devis", initial_mode="recus", focus_numero=r["numero"]))

        fournisseurs = self.db.fetchall(
            "SELECT * FROM fournisseurs WHERE nom LIKE ? OR categorie_produits LIKE ? "
            "ORDER BY nom LIMIT 6", (like, like))
        total += self._section(
            "🏭 Fournisseurs", fournisseurs, lambda r: r["nom"],
            lambda r: r["categorie_produits"] or "—",
            lambda r: self._goto("fournisseurs"))

        employes = self.db.fetchall(
            "SELECT * FROM employes WHERE nom LIKE ? OR poste LIKE ? ORDER BY nom LIMIT 6", (like, like))
        total += self._section(
            "👔 Employés", employes, lambda r: r["nom"], lambda r: r["poste"] or "—",
            lambda r: self._goto("employes"))

        sourcing = self.db.fetchall(
            "SELECT * FROM sourcing_commandes WHERE numero LIKE ? OR designation LIKE ? "
            "ORDER BY id DESC LIMIT 6", (like, like))
        total += self._section(
            "🚚 Sourcing", sourcing, lambda r: r["numero"] or "—", lambda r: r["designation"] or "—",
            lambda r: self._goto("sourcing"))

        depenses = self.db.fetchall(
            "SELECT * FROM depenses WHERE description LIKE ? OR beneficiaire LIKE ? OR categorie LIKE ? "
            "ORDER BY id DESC LIMIT 6", (like, like, like))
        total += self._section(
            "💳 Dépenses", depenses, lambda r: r["categorie"] or "Dépense",
            lambda r: r["beneficiaire"] or (r["description"] or "—"),
            lambda r: self._goto("depenses"))

        if total == 0:
            ctk.CTkLabel(self.results_frame, text=f"Aucun résultat pour « {q} ».",
                         font=font(12), text_color=COLORS["text_muted"]).pack(pady=40)

    def _section(self, titre, rows, title_fn, subtitle_fn, on_click):
        if not rows:
            return 0
        ctk.CTkLabel(self.results_frame, text=titre, font=font(11, "bold"),
                     text_color=COLORS["gold"]).pack(anchor="w", pady=(6, 4))
        for r in rows:
            self._result_row(title_fn(r), subtitle_fn(r), on_click)
        return len(rows)

    def _result_row(self, titre, sous_titre, on_click):
        row = ctk.CTkFrame(self.results_frame, fg_color=COLORS["bg_card"], corner_radius=8, cursor="hand2")
        row.pack(fill="x", pady=2)
        inner = ctk.CTkFrame(row, fg_color="transparent")
        inner.pack(fill="x", padx=12, pady=8)
        lbl1 = ctk.CTkLabel(inner, text=titre, font=font(13, "bold"),
                             text_color=COLORS["text_primary"], anchor="w")
        lbl1.pack(anchor="w")
        lbl2 = ctk.CTkLabel(inner, text=sous_titre, font=font(11),
                             text_color=COLORS["text_secondary"], anchor="w")
        lbl2.pack(anchor="w")
        # Le clic doit fonctionner peu importe où sur la ligne on clique — le
        # conteneur ET chacun de ses enfants directs ont donc leur propre
        # binding vers le même callback.
        for w in (row, inner, lbl1, lbl2):
            w.bind("<Button-1>", lambda e, cb=on_click: cb())

    def _goto(self, page, **kwargs):
        self.destroy()
        self.app.show_page(page, **kwargs)
