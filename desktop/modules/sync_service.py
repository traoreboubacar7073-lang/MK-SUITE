"""
MK Suite - Synchronisation locale Wi-Fi avec la version mobile.

PRINCIPE : aucun serveur internet — ordinateur et téléphone doivent être sur
le même réseau Wi-Fi. L'appareil qui lance la synchronisation fait DEUX
choses avec l'autre appareil (qui doit avoir démarré son serveur local) :
  1. il récupère les données de l'autre appareil (GET /export) et les
     fusionne dans sa propre base ;
  2. il envoie ses propres données à l'autre appareil (POST /import), qui
     fait la même fusion de son côté.
Après ces deux étapes, les deux appareils ont exactement les mêmes données —
peu importe lequel a démarré la synchronisation.

C'est le pendant EXACT, côté ordinateur, de lib/services/sync_service.dart
côté téléphone : même port (8642), mêmes routes (/ping, /export, /import),
même format de paquet JSON, même règle de fusion (sync_id = identité,
updated_at = résolution de conflit "dernière modification l'emporte",
corbeille = journal de suppressions ET restaurations). Les deux DOIVENT
rester en accord — modifier l'un sans l'autre casserait la synchronisation.

Dépendances : uniquement la bibliothèque standard (http.server, urllib,
json, socket, threading) — aucun paquet supplémentaire à installer.
"""
import json
import socket
import threading
import urllib.request
import urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from database.db_manager import now_ms, new_sync_id

SYNC_PORT = 8642
APP_ID = "mk_suite"

# ---------------------------------------------------------------------------
# EXPORT — construit le paquet JSON envoyé à l'autre appareil.
# ---------------------------------------------------------------------------


def _dump_table(conn, table):
    rows = conn.execute(f"SELECT * FROM {table}").fetchall()
    out = []
    for r in rows:
        d = dict(r)
        d.pop("id", None)
        out.append(d)
    return out


def _sync_id_of(conn, table, column, value):
    if value is None:
        return None
    row = conn.execute(f"SELECT sync_id FROM {table} WHERE {column} = ?", (value,)).fetchone()
    return row["sync_id"] if row else None


def export_all(db):
    """`db` est un DatabaseManager (database/db_manager.py). Toute la lecture
    se fait sous verrou pour obtenir un instantané cohérent, même si le
    serveur de synchronisation tourne dans un thread différent de celui de
    l'interface graphique."""
    conn = db.conn

    with db.lock:
        clients = _dump_table(conn, "clients")
        fournisseurs = _dump_table(conn, "fournisseurs")
        employes = _dump_table(conn, "employes")
        tarifs = _dump_table(conn, "tarifs_vitres")

        devis = _dump_table(conn, "devis")
        for d in devis:
            d["client_sync_id_ref"] = _sync_id_of(conn, "clients", "id", d.get("client_id"))

        lignes_devis = _dump_table(conn, "lignes_devis")
        for l in lignes_devis:
            l["devis_sync_id_ref"] = _sync_id_of(conn, "devis", "numero", l.get("devis_numero"))

        factures = _dump_table(conn, "factures")
        for f in factures:
            f["client_sync_id_ref"] = _sync_id_of(conn, "clients", "id", f.get("client_id"))
            f["devis_sync_id_ref"] = (
                _sync_id_of(conn, "devis", "numero", f.get("devis_numero")) if f.get("devis_numero") else None
            )

        lignes_facture = _dump_table(conn, "lignes_facture")
        for l in lignes_facture:
            l["facture_sync_id_ref"] = _sync_id_of(conn, "factures", "numero", l.get("facture_numero"))

        recus = _dump_table(conn, "recus")
        for r in recus:
            r["client_sync_id_ref"] = _sync_id_of(conn, "clients", "id", r.get("client_id"))
            r["facture_sync_id_ref"] = (
                _sync_id_of(conn, "factures", "numero", r.get("facture_numero")) if r.get("facture_numero") else None
            )

        notes = _dump_table(conn, "notes_client")
        for n in notes:
            n["client_sync_id_ref"] = _sync_id_of(conn, "clients", "id", n.get("client_id"))

        depenses = _dump_table(conn, "depenses")
        budget = _dump_table(conn, "budget_categories")

        vitres = _dump_table(conn, "commandes_vitres")
        for v in vitres:
            v["devis_sync_id_ref"] = (
                _sync_id_of(conn, "devis", "numero", v.get("devis_numero")) if v.get("devis_numero") else None
            )
            v["facture_sync_id_ref"] = (
                _sync_id_of(conn, "factures", "numero", v.get("facture_numero")) if v.get("facture_numero") else None
            )

        sourcing = _dump_table(conn, "sourcing_commandes")
        for s in sourcing:
            s["fournisseur_sync_id_ref"] = _sync_id_of(conn, "fournisseurs", "id", s.get("fournisseur_id"))
            s["client_sync_id_ref"] = _sync_id_of(conn, "clients", "id", s.get("client_id"))

        paie = _dump_table(conn, "paie")
        for p in paie:
            p["employe_sync_id_ref"] = _sync_id_of(conn, "employes", "id", p.get("employe_id"))

        corbeille = _dump_table(conn, "corbeille")

    return {
        "app": APP_ID, "version": 2, "document_lines_mode": "snapshot", "exported_at": now_ms(),
        "clients": clients, "fournisseurs": fournisseurs, "employes": employes, "tarifs_vitres": tarifs,
        "devis": devis, "lignes_devis": lignes_devis, "factures": factures, "lignes_facture": lignes_facture,
        "recus": recus, "notes_client": notes, "depenses": depenses, "budget_categories": budget,
        "commandes_vitres": vitres, "sourcing_commandes": sourcing, "paie": paie, "corbeille": corbeille,
    }


# ---------------------------------------------------------------------------
# IMPORT — fusionne un paquet reçu dans la base locale.
# ---------------------------------------------------------------------------


class SyncLog:
    def __init__(self):
        self.lines = []
        self.inserted = 0
        self.updated = 0
        self.has_conflicts = False

    def add(self, line):
        self.lines.append(line)

    def as_dict(self):
        return {"inserted": self.inserted, "updated": self.updated, "lines": self.lines, "hasConflicts": self.has_conflicts}


def import_all(db, dump):
    """`db` est un DatabaseManager. Toute la fusion se fait dans UNE SEULE
    transaction : si une ligne pose problème en cours de route, tout est
    annulé plutôt que de laisser la base à moitié fusionnée."""
    if (dump.get("app") != APP_ID or dump.get("version") != 2
            or dump.get("document_lines_mode") != "snapshot"):
        raise ValueError("Mettez les deux appareils à jour : protocole v2 requis.")
    for key in ("devis", "lignes_devis", "factures", "lignes_facture"):
        if not isinstance(dump.get(key), list):
            raise ValueError("Paquet incomplet : " + key)
    conn = db.conn
    log = SyncLog()
    plans = {}

    def rows_of(key):
        return dump.get(key) or []

    def local_id_by_sync_id(table, sync_id):
        if not sync_id:
            return None
        row = conn.execute(f"SELECT id FROM {table} WHERE sync_id = ?", (sync_id,)).fetchone()
        return row["id"] if row else None

    def local_numero_by_sync_id(table, sync_id, numero_column):
        if not sync_id:
            return None
        row = conn.execute(f"SELECT {numero_column} FROM {table} WHERE sync_id = ?", (sync_id,)).fetchone()
        return row[numero_column] if row else None

    def strip_refs(row):
        return {k: v for k, v in row.items() if not k.endswith("_sync_id_ref")}

    def insert_row(table, row):
        cols = list(row.keys())
        placeholders = ",".join(["?"] * len(cols))
        conn.execute(f"INSERT INTO {table} ({','.join(cols)}) VALUES ({placeholders})",
                     tuple(row[c] for c in cols))

    def update_row(table, row, sync_id):
        cols = [c for c in row.keys() if c != "sync_id"]
        set_clause = ",".join(f"{c} = ?" for c in cols)
        conn.execute(f"UPDATE {table} SET {set_clause} WHERE sync_id = ?",
                     tuple(row[c] for c in cols) + (sync_id,))

    def merge_simple(table, key, unique_field=None, numero_prefix=None, with_year=True, width=3):
        """Fusionne une table par `sync_id` : nouvelle ligne -> insertion (en
        régénérant un numéro/code local si `unique_field` entre en collision
        avec une ligne EXISTANTE différente) ; ligne déjà connue -> mise à
        jour seulement si la version distante est plus récente."""
        for r in rows_of(key):
            sync_id = r.get("sync_id")
            if not sync_id:
                continue
            remote_updated_at = r.get("updated_at") or 0
            local = conn.execute(f"SELECT * FROM {table} WHERE sync_id = ?", (sync_id,)).fetchone()
            if local is None:
                row = strip_refs(dict(r))
                row.pop("id", None)
                if unique_field and row.get(unique_field) is not None:
                    collision = conn.execute(f"SELECT 1 FROM {table} WHERE {unique_field} = ?",
                                              (row[unique_field],)).fetchone()
                    if collision:
                        ancien = row[unique_field]
                        row[unique_field] = (
                            db.next_numero(numero_prefix, table, column=unique_field, with_year=with_year, width=width)
                            if numero_prefix else f"{ancien}-2"
                        )
                        log.add(f"{table} : « {ancien} » existait déjà avec un contenu différent → renommé en « {row[unique_field]} ».")
                insert_row(table, row)
                log.inserted += 1
            else:
                local_updated_at = local["updated_at"] or 0
                if remote_updated_at > local_updated_at:
                    row = strip_refs(dict(r))
                    row.pop("id", None)
                    if unique_field:
                        row.pop(unique_field, None)
                    update_row(table, row, sync_id)
                    log.updated += 1

    def merge_with_fk(table, key, fk_to_ref_table, fk_to_ref_key, fk_to_ref_sync_id_field,
                       unique_field=None, numero_prefix=None):
        """Même principe que merge_simple, mais pour une table qui référence
        une autre par identifiant local (`fk_column`) — résolue ici via le
        sync_id de la ligne parente. `fk_to_ref_sync_id_field` donne, pour
        chaque colonne FK, le nom EXACT du champ `*_sync_id_ref` écrit par
        export_all — ne JAMAIS le déduire du nom de la colonne FK (une
        colonne `devis_numero` ne se termine pas par `_id`)."""
        for r in rows_of(key):
            sync_id = r.get("sync_id")
            if not sync_id:
                continue
            if table in plans and plans[table][sync_id] != "replace":
                continue
            row = dict(r)
            for fk_column, ref_table in fk_to_ref_table.items():
                ref_key_field = fk_to_ref_key[fk_column]
                ref_sync_id = row.pop(fk_to_ref_sync_id_field[fk_column], None)
                # Pas de repli sur la valeur brute distante : un identifiant/
                # numéro local à l'autre appareil n'a aucun sens ici.
                if ref_key_field == "id":
                    row[fk_column] = local_id_by_sync_id(ref_table, ref_sync_id)
                else:
                    row[fk_column] = local_numero_by_sync_id(ref_table, ref_sync_id, ref_key_field)
            row = strip_refs(row)
            remote_updated_at = row.get("updated_at") or 0
            local = conn.execute(f"SELECT * FROM {table} WHERE sync_id = ?", (sync_id,)).fetchone()
            if local is None:
                row.pop("id", None)
                if unique_field and row.get(unique_field) is not None:
                    collision = conn.execute(f"SELECT 1 FROM {table} WHERE {unique_field} = ?",
                                              (row[unique_field],)).fetchone()
                    if collision:
                        ancien = row[unique_field]
                        row[unique_field] = (
                            db.next_numero(numero_prefix, table, column=unique_field) if numero_prefix else f"{ancien}-2"
                        )
                        log.add(f"{table} : « {ancien} » existait déjà avec un contenu différent → renommé en « {row[unique_field]} ».")
                insert_row(table, row)
                log.inserted += 1
            else:
                local_updated_at = local["updated_at"] or 0
                if remote_updated_at > local_updated_at:
                    row.pop("id", None)
                    if unique_field:
                        row.pop(unique_field, None)
                    update_row(table, row, sync_id)
                    log.updated += 1

    def merge_reference(table, key, field):
        """Fusionne une table de RÉFÉRENCE pré-remplie indépendamment sur les
        deux appareils au tout premier lancement (fournisseurs, tarifs de
        vitres) : deux lignes avec la même valeur de `field` mais des
        sync_id différents désignent la MÊME entité — on les fusionne en une
        seule ligne (en adoptant le sync_id DISTANT) plutôt que d'insérer un
        doublon. Adopter le sync_id distant permet aux lignes plus bas dans
        CE MÊME paquet qui référencent cette entité (ex.
        sourcing_commandes.fournisseur_id) de la retrouver via
        local_id_by_sync_id. Comme sync_with() importe toujours AVANT
        d'exporter, les deux appareils convergent vers ce même sync_id dès
        le premier échange complet — quel que soit celui qui a initié."""
        for r in rows_of(key):
            sync_id = r.get("sync_id")
            if not sync_id:
                continue
            remote_updated_at = r.get("updated_at") or 0

            by_sync = conn.execute(f"SELECT * FROM {table} WHERE sync_id = ?", (sync_id,)).fetchone()
            if by_sync is not None:
                local_updated_at = by_sync["updated_at"] or 0
                if remote_updated_at > local_updated_at:
                    row = strip_refs(dict(r))
                    row.pop("id", None)
                    update_row(table, row, sync_id)
                    log.updated += 1
                continue

            val = (r.get(field) or "").strip()
            if val:
                by_field = conn.execute(f"SELECT * FROM {table} WHERE {field} = ?", (val,)).fetchone()
                if by_field is not None:
                    local_updated_at = by_field["updated_at"] or 0
                    data = {"sync_id": sync_id}
                    if remote_updated_at > local_updated_at:
                        row = strip_refs(dict(r))
                        row.pop("id", None)
                        row.pop("sync_id", None)
                        data.update(row)
                    set_clause = ",".join(f"{c} = ?" for c in data.keys())
                    conn.execute(f"UPDATE {table} SET {set_clause} WHERE id = ?",
                                 tuple(data.values()) + (by_field["id"],))
                    continue

            row = strip_refs(dict(r))
            row.pop("id", None)
            insert_row(table, row)
            log.inserted += 1

    def line_signature(rows):
        # Numeric 1 and 1.0 compare equally, and repeated lines stay repeated.
        return sorted(json.dumps([float(r[k]) if r.get(k) is not None else None
                                  for k in ("quantite",)] + [r.get("description")] +
                                 [float(r[k]) if r.get(k) is not None else None
                                  for k in ("prix_unitaire", "total_ligne")], ensure_ascii=False)
                      for r in rows)

    def plan_documents(parent, lines, fk, ref):
        plans[parent] = {}
        ids = [r.get("sync_id") for r in rows_of(parent)]
        if any(not i for i in ids) or len(ids) != len(set(ids)):
            raise ValueError("Identités de documents invalides")
        if any(r.get(ref) not in ids for r in rows_of(lines)):
            raise ValueError("Ligne sans document : " + lines)
        for incoming in rows_of(parent):
            sid = incoming["sync_id"]
            local = conn.execute(f"SELECT * FROM {parent} WHERE sync_id=?", (sid,)).fetchone()
            remote_rev = incoming.get("updated_at") or 0
            decision = "keep"
            if local is None or remote_rev > (local["updated_at"] or 0):
                decision = "replace"
            elif remote_rev == (local["updated_at"] or 0):
                local_lines = [dict(r) for r in conn.execute(f"SELECT * FROM {lines} WHERE {fk}=?", (local["numero"],))]
                remote_lines = [r for r in rows_of(lines) if r.get(ref) == sid]
                if line_signature(local_lines) != line_signature(remote_lines):
                    decision = "conflict"
                    log.has_conflicts = True
                    log.add(f"{parent} {incoming['numero']} : conflit à version identique, contenu local conservé.")
            plans[parent][sid] = decision

    def merge_document_lines(parent, lines, fk, ref):
        for sid, decision in plans[parent].items():
            if decision != "replace":
                continue
            numero = local_numero_by_sync_id(parent, sid, "numero")
            if numero is None:
                raise ValueError("Document parent introuvable")
            conn.execute(f"DELETE FROM {lines} WHERE {fk}=?", (numero,))
            for incoming in rows_of(lines):
                if incoming.get(ref) != sid:
                    continue
                row = strip_refs(incoming)
                row.pop("id", None)
                row[fk] = numero
                insert_row(lines, row)
                log.inserted += 1

    with db.lock:
        try:
            db.sync_importing = True
            conn.execute("BEGIN")
            plan_documents("devis", "lignes_devis", "devis_numero", "devis_sync_id_ref")
            plan_documents("factures", "lignes_facture", "facture_numero", "facture_sync_id_ref")

            # Ordre important : les tables "parentes" d'abord, pour que la
            # résolution des références (client_sync_id_ref, etc.) trouve
            # toujours la ligne déjà fusionnée.
            merge_simple("clients", "clients", unique_field="code", numero_prefix="CL", with_year=False)
            merge_reference("fournisseurs", "fournisseurs", "nom")
            merge_simple("employes", "employes", unique_field="code", numero_prefix="EMP", with_year=False, width=2)
            merge_reference("tarifs_vitres", "tarifs_vitres", "type_vitre")

            merge_with_fk("devis", "devis", {"client_id": "clients"}, {"client_id": "id"},
                          {"client_id": "client_sync_id_ref"}, unique_field="numero", numero_prefix="DV")
            merge_document_lines("devis", "lignes_devis", "devis_numero", "devis_sync_id_ref")
            merge_with_fk("factures", "factures", {"client_id": "clients", "devis_numero": "devis"},
                          {"client_id": "id", "devis_numero": "numero"},
                          {"client_id": "client_sync_id_ref", "devis_numero": "devis_sync_id_ref"},
                          unique_field="numero", numero_prefix="FA")
            merge_document_lines("factures", "lignes_facture", "facture_numero", "facture_sync_id_ref")
            merge_with_fk("recus", "recus", {"client_id": "clients", "facture_numero": "factures"},
                          {"client_id": "id", "facture_numero": "numero"},
                          {"client_id": "client_sync_id_ref", "facture_numero": "facture_sync_id_ref"},
                          unique_field="numero", numero_prefix="RC")
            merge_with_fk("notes_client", "notes_client", {"client_id": "clients"}, {"client_id": "id"},
                          {"client_id": "client_sync_id_ref"}, unique_field="numero", numero_prefix="NT")
            merge_simple("depenses", "depenses")
            merge_simple("budget_categories", "budget_categories")
            merge_with_fk("commandes_vitres", "commandes_vitres", {"devis_numero": "devis", "facture_numero": "factures"},
                          {"devis_numero": "numero", "facture_numero": "numero"},
                          {"devis_numero": "devis_sync_id_ref", "facture_numero": "facture_sync_id_ref"})
            merge_with_fk("sourcing_commandes", "sourcing_commandes", {"fournisseur_id": "fournisseurs", "client_id": "clients"},
                          {"fournisseur_id": "id", "client_id": "id"},
                          {"fournisseur_id": "fournisseur_sync_id_ref", "client_id": "client_sync_id_ref"},
                          unique_field="numero", numero_prefix="SRC")
            merge_with_fk("paie", "paie", {"employe_id": "employes"}, {"employe_id": "id"},
                          {"employe_id": "employe_sync_id_ref"})

            # Corbeille en dernier : d'abord fusionnée comme les autres (ce qui
            # propage aussi bien une nouvelle suppression qu'une restauration —
            # voir restore_from_corbeille, qui renouvelle updated_at côté
            # corbeille pour ça), puis utilisée pour propager les suppressions
            # ("tombstones") vers les tables encore vivantes.
            merge_simple("corbeille", "corbeille")
            corbeille_rows = conn.execute("SELECT * FROM corbeille WHERE restaure = 0").fetchall()
            for c in corbeille_rows:
                origine_key = c["origine_key"]
                table = c["table_origine"]
                deleted_at = c["deleted_at"] or 0
                if not origine_key or not table or deleted_at == 0:
                    continue
                # origine_key est le sync_id de la ligne supprimée (voir move_to_corbeille).
                still = conn.execute(f"SELECT updated_at FROM {table} WHERE sync_id = ?", (origine_key,)).fetchone()
                if still is not None and (still["updated_at"] or 0) < deleted_at:
                    conn.execute(f"DELETE FROM {table} WHERE sync_id = ?", (origine_key,))
                    log.add(f"{table} : ligne supprimée sur l'autre appareil, retirée ici aussi.")

            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            db.sync_importing = False

    return log


# ---------------------------------------------------------------------------
# SERVEUR — attend une connexion de l'autre appareil sur le même Wi-Fi.
# ---------------------------------------------------------------------------


def local_address():
    """Adresse IP locale (Wi-Fi) de l'ordinateur, à afficher pour que
    l'autre appareil puisse s'y connecter — cherche une IPv4 privée
    classique (192.168.x.x / 10.x.x.x / 172.16-31.x.x)."""
    candidates = []
    try:
        hostname = socket.gethostname()
        for info in socket.getaddrinfo(hostname, None, socket.AF_INET):
            candidates.append(info[4][0])
    except socket.gaierror:
        pass
    # Méthode plus fiable : ouvre un socket UDP "factice" vers une adresse
    # publique (aucune donnée n'est réellement envoyée) pour connaître
    # l'adresse locale que le système utiliserait pour sortir sur le réseau.
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            s.connect(("8.8.8.8", 80))
            candidates.insert(0, s.getsockname()[0])
        finally:
            s.close()
    except OSError:
        pass

    def is_private(ip):
        if ip.startswith("192.168.") or ip.startswith("10."):
            return True
        if ip.startswith("127."):
            return False
        if ip.startswith("172."):
            parts = ip.split(".")
            if len(parts) >= 2:
                try:
                    second = int(parts[1])
                    return 16 <= second <= 31
                except ValueError:
                    return False
        return False

    for ip in candidates:
        if is_private(ip):
            return ip
    return candidates[0] if candidates else None


class _SyncRequestHandler(BaseHTTPRequestHandler):
    # Le DatabaseManager est injecté par SyncServer.start() via une classe
    # fille dynamique (voir plus bas) — évite d'avoir à bricoler un état
    # global partagé entre requêtes.
    db = None

    def log_message(self, format, *args):
        pass  # Pas de bruit dans la console — les erreurs restent gérées ci-dessous.

    def _send_json(self, status, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        try:
            if self.path == "/ping":
                self._send_json(200, {"app": APP_ID})
            elif self.path == "/glass/status":
                from modules.glass_ai_service import status
                self._send_json(200, status())
            elif self.path == "/export":
                self._send_json(200, export_all(self.db))
            else:
                self._send_json(404, {"error": "not found"})
        except Exception as e:
            self._send_json(500, {"error": str(e)})

    def do_POST(self):
        try:
            if self.path == "/glass/recognize":
                from modules.glass_ai_service import recognize, GlassAIError, MAX_REQUEST_BYTES
                try:
                    length = int(self.headers.get("Content-Length", 0))
                    if length <= 0 or length > MAX_REQUEST_BYTES:
                        self._send_json(413, {"code": "image_too_large", "error": "Photo trop volumineuse ou manquante."})
                        return
                    self.connection.settimeout(15)
                    body = self.rfile.read(length)
                    if len(body) != length:
                        raise ValueError("Photo incomplète")
                    result = recognize(json.loads(body.decode("utf-8")), self.headers.get("Authorization", ""))
                    self._send_json(200, result)
                except GlassAIError as exc:
                    self._send_json(exc.status, {"code": exc.code, "error": str(exc)})
                except (ValueError, OSError):
                    self._send_json(400, {"code": "invalid_image", "error": "Photo invalide ou incomplète."})
            elif self.path == "/import":
                length = int(self.headers.get("Content-Length", 0))
                body = self.rfile.read(length)
                dump = json.loads(body.decode("utf-8"))
                log = import_all(self.db, dump)
                self._send_json(200, log.as_dict())
            else:
                self._send_json(404, {"error": "not found"})
        except Exception as e:
            self._send_json(500, {"error": str(e)})


class SyncServer:
    """Serveur HTTP local (bibliothèque standard uniquement) qui attend une
    synchronisation initiée par l'autre appareil. Tourne dans un thread à
    part pour ne jamais geler l'interface CustomTkinter."""

    def __init__(self, db):
        self.db = db
        self._httpd = None
        self._thread = None

    @property
    def is_running(self):
        return self._httpd is not None

    def start(self):
        if self._httpd is not None:
            return local_address()
        try:
            handler_cls = type("BoundSyncHandler", (_SyncRequestHandler,), {"db": self.db})
            self._httpd = ThreadingHTTPServer(("0.0.0.0", SYNC_PORT), handler_cls)
        except OSError:
            self._httpd = None
            return None
        self._thread = threading.Thread(target=self._httpd.serve_forever, daemon=True)
        self._thread.start()
        return local_address()

    def stop(self):
        if self._httpd is not None:
            self._httpd.shutdown()
            self._httpd.server_close()
            self._httpd = None
            self._thread = None


# ---------------------------------------------------------------------------
# CLIENT — se connecte à l'autre appareil pour lancer une synchronisation
# complète dans les deux sens.
# ---------------------------------------------------------------------------


def can_reach(host, port=SYNC_PORT, timeout=4):
    """Vérifie qu'un appareil MK Suite répond bien à cette adresse, avant de
    lancer une vraie synchronisation."""
    try:
        with urllib.request.urlopen(f"http://{host}:{port}/ping", timeout=timeout) as resp:
            if resp.status != 200:
                return False
            body = json.loads(resp.read().decode("utf-8"))
            return body.get("app") == APP_ID
    except (urllib.error.URLError, TimeoutError, OSError, ValueError):
        return False


def sync_with(db, host, port=SYNC_PORT, timeout=30):
    """Synchronisation complète avec l'appareil à host:port : récupère ses
    données et les fusionne ici, puis envoie les nôtres pour qu'il fasse de
    même de son côté. Retourne un SyncLog (ce qui a été ajouté/mis à jour
    ici, et les éventuels avertissements)."""
    base = f"http://{host}:{port}"

    try:
        with urllib.request.urlopen(f"{base}/export", timeout=timeout) as resp:
            if resp.status != 200:
                raise RuntimeError(f"L'autre appareil n'a pas répondu correctement ({resp.status}).")
            remote_dump = json.loads(resp.read().decode("utf-8"))
    except urllib.error.URLError as e:
        raise RuntimeError(f"Impossible de joindre l'autre appareil : {e}") from e

    log = import_all(db, remote_dump)

    if log.has_conflicts:
        log.add("Envoi suspendu : vérifiez les conflits avant de resynchroniser.")
        return log
    local_dump = export_all(db)
    body = json.dumps(local_dump, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        f"{base}/import", data=body, method="POST",
        headers={"Content-Type": "application/json; charset=utf-8"},
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            result = json.loads(resp.read().decode("utf-8"))
            if result.get("hasConflicts"):
                log.has_conflicts = True
                log.lines.extend(result.get("lines", []))
            if resp.status != 200:
                log.add(f"Nos données ont bien été reçues localement, mais l'envoi vers l'autre appareil a échoué ({resp.status}) — relance la synchronisation depuis l'un ou l'autre appareil.")
    except urllib.error.URLError as e:
        log.add(f"Nos données ont bien été reçues localement, mais l'envoi vers l'autre appareil a échoué ({e}) — relance la synchronisation depuis l'un ou l'autre appareil.")

    return log
