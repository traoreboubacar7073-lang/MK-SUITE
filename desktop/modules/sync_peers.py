"""
MK Suite - Adresses de synchronisation enregistrées
Mémorise les adresses IP déjà utilisées pour la synchronisation Wi-Fi, pour
ne plus jamais avoir à les retaper — pendant, côté ordinateur, de
`lib/services/sync_peers_service.dart` côté téléphone.

Stocké dans un petit fichier JSON à côté de la base de données (et non DANS
la base elle-même) : c'est une préférence locale à CET ordinateur, qui n'a
aucune raison de se propager à l'autre appareil lors d'une synchronisation
— contrairement à toutes les autres tables, qui elles sont synchronisées.
"""
import json
import os
from pathlib import Path
from datetime import datetime

MAX_PEERS = 6


def _fichier_peers():
    dossier = Path.home() / "MK_Suite_Data"
    try:
        dossier.mkdir(exist_ok=True)
    except OSError:
        pass  # Non bloquant, comme le reste de ce fichier — au pire, rien n'est mémorisé.
    return dossier / "sync_peers.json"


def charger_peers():
    """Liste des adresses enregistrées, la plus récemment utilisée en
    premier — chaque entrée : {"ip": "...", "derniere_utilisation": "..."}."""
    chemin = _fichier_peers()
    if not chemin.exists():
        return []
    try:
        with open(chemin, "r", encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, list):
            return []
        return [p for p in data if isinstance(p, dict) and p.get("ip")]
    except (json.JSONDecodeError, OSError):
        return []


def enregistrer_peer(ip):
    """Ajoute (ou fait remonter en tête si déjà présente) une adresse IP
    utilisée avec succès — appelée après une vérification ou une
    synchronisation réussie, jamais après un échec."""
    ip = (ip or "").strip()
    if not ip:
        return
    peers = [p for p in charger_peers() if p.get("ip") != ip]
    peers.insert(0, {"ip": ip, "derniere_utilisation": datetime.now().isoformat()})
    peers = peers[:MAX_PEERS]
    try:
        with open(_fichier_peers(), "w", encoding="utf-8") as f:
            json.dump(peers, f, ensure_ascii=False, indent=2)
    except OSError:
        pass  # Non bloquant : au pire, l'adresse ne sera pas mémorisée cette fois-ci.


def supprimer_peer(ip):
    peers = [p for p in charger_peers() if p.get("ip") != ip]
    try:
        with open(_fichier_peers(), "w", encoding="utf-8") as f:
            json.dump(peers, f, ensure_ascii=False, indent=2)
    except OSError:
        pass
