"""
MK Suite - Import des données depuis le classeur Excel GESTIONNAIE_DE_FICHIER.xlsx
Lit toutes les feuilles (Clients, Devis, Factures, Dépenses, Personnel, Paie,
Fournisseurs, Reçus, Notes, Calcul Vitres) et les insère dans la base SQLite.

Usage : python import_excel_data.py chemin/vers/GESTIONNAIE_DE_FICHIER.xlsx
"""
import sys
import os
import openpyxl
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from database.db_manager import DatabaseManager


def s(val):
    """Nettoie une valeur de cellule -> string ou None"""
    if val is None:
        return None
    return str(val).strip()


def d(val):
    """Nettoie une date -> string ISO ou None"""
    if val is None:
        return None
    if isinstance(val, datetime):
        return val.strftime("%Y-%m-%d")
    return str(val)


def num(val, default=0):
    try:
        return float(val)
    except (TypeError, ValueError):
        return default


def import_all(xlsx_path):
    print(f"Ouverture de {xlsx_path}...")
    wb = openpyxl.load_workbook(xlsx_path, data_only=True)
    db = DatabaseManager()
    cur = db.conn.cursor()

    # Nettoyage complet avant import (on repart propre pour éviter les doublons)
    for t in ["clients", "fournisseurs", "devis", "lignes_devis", "factures",
              "lignes_facture", "depenses", "employes", "paie", "recus",
              "notes_client", "commandes_vitres"]:
        cur.execute(f"DELETE FROM {t}")
    db.conn.commit()
    print("Anciennes données locales effacées, import en cours...\n")

    # ============ CLIENTS ============
    ws = wb["Clients"]
    client_code_to_id = {}
    client_name_to_id = {}
    count = 0
    for row in ws.iter_rows(min_row=4, values_only=True):
        code = s(row[0])
        if not code or not code.startswith("CL"):
            continue
        nom = s(row[1]) or "Client sans nom"
        type_client = s(row[2]) or "Particulier"
        telephone = s(row[3])
        adresse = s(row[4])
        date_contact = d(row[5])
        statut = s(row[11]) or "Actif"
        cid = db.execute(
            "INSERT INTO clients (code, nom, type_client, telephone, adresse, "
            "date_premier_contact, statut) VALUES (?,?,?,?,?,?,?)",
            (code, nom, type_client, telephone, adresse, date_contact, statut))
        client_code_to_id[code] = cid
        client_name_to_id[nom.lower()] = cid
        count += 1
    print(f"✓ Clients importés : {count}")

    def resolve_client(value):
        """Retrouve l'ID client à partir d'un code (CL-xxx) ou d'un nom"""
        if not value:
            return None
        v = value.strip()
        if v.upper().replace(" ", "") in [k.replace(" ", "") for k in client_code_to_id]:
            for k, cid in client_code_to_id.items():
                if k.replace(" ", "") == v.upper().replace(" ", ""):
                    return cid
        return client_name_to_id.get(v.lower())

    # ============ FOURNISSEURS ============
    ws = wb["Fournisseurs"]
    count = 0
    for row in ws.iter_rows(min_row=4, values_only=True):
        nom = s(row[0])
        if not nom:
            continue
        db.execute(
            "INSERT OR IGNORE INTO fournisseurs (nom, categorie_produits, contact, telephone, adresse) "
            "VALUES (?,?,?,?,?)",
            (nom, s(row[1]), s(row[2]), s(row[3]), s(row[4])))
        count += 1
    print(f"✓ Fournisseurs importés : {count}")

    # ============ DEVIS ============
    ws = wb["Devis"]
    count = 0
    for row in ws.iter_rows(min_row=4, values_only=True):
        numero = s(row[0])
        if not numero or not numero.startswith("DV"):
            continue
        client_id = resolve_client(s(row[2]))
        db.execute(
            "INSERT INTO devis (numero, date_devis, client_id, objet, montant_ht, statut, "
            "validite_jours, date_limite, converti_facture) VALUES (?,?,?,?,?,?,?,?,?)",
            (numero, d(row[1]), client_id, s(row[3]), num(row[4]), s(row[5]) or "En attente",
             int(num(row[6], 30)), d(row[7]), s(row[8])))
        count += 1
    print(f"✓ Devis importés : {count}")

    # ============ LIGNES DEVIS ============
    ws = wb["Lignes Devis"]
    count = 0
    for row in ws.iter_rows(min_row=4, values_only=True):
        devis_num = s(row[0])
        if not devis_num:
            continue
        db.execute(
            "INSERT INTO lignes_devis (devis_numero, quantite, description, prix_unitaire, total_ligne) "
            "VALUES (?,?,?,?,?)",
            (devis_num, num(row[1], 1), s(row[2]), num(row[3]), num(row[4])))
        count += 1
    print(f"✓ Lignes de devis importées : {count}")

    # ============ FACTURES ============
    ws = wb["Factures"]
    count = 0
    for row in ws.iter_rows(min_row=4, values_only=True):
        numero = s(row[0])
        if not numero or not numero.startswith("FA"):
            continue
        client_id = resolve_client(s(row[3]))
        db.execute(
            "INSERT INTO factures (numero, date_facture, devis_numero, client_id, description, "
            "montant_ht, reduction_pct, montant_ht_net, tva, montant_ttc, avance_recue, "
            "reste_a_payer, statut, mode_paiement) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (numero, d(row[1]), s(row[2]), client_id, s(row[4]), num(row[5]), num(row[6]),
             num(row[7]), num(row[8]), num(row[9]), num(row[10]), num(row[11]),
             s(row[12]) or "Impayée", s(row[13])))
        count += 1
    print(f"✓ Factures importées : {count}")

    # ============ LIGNES FACTURE ============
    ws = wb["Lignes Facture"]
    count = 0
    for row in ws.iter_rows(min_row=4, values_only=True):
        fact_num = s(row[0])
        if not fact_num:
            continue
        db.execute(
            "INSERT INTO lignes_facture (facture_numero, quantite, description, prix_unitaire, total_ligne) "
            "VALUES (?,?,?,?,?)",
            (fact_num, num(row[1], 1), s(row[2]), num(row[3]), num(row[4])))
        count += 1
    print(f"✓ Lignes de facture importées : {count}")

    # ============ DÉPENSES ============
    ws = wb["Dépenses"]
    count = 0
    for row in ws.iter_rows(min_row=3, values_only=True):
        date_dep = row[0]
        categorie = s(row[1])
        if date_dep is None and not categorie:
            continue
        montant = num(row[4])
        if montant == 0 and not categorie:
            continue
        db.execute(
            "INSERT INTO depenses (date_depense, categorie, description, beneficiaire, montant, "
            "mode_paiement, justificatif) VALUES (?,?,?,?,?,?,?)",
            (d(date_dep), categorie, s(row[2]), s(row[3]), montant, s(row[5]) or "Espèces",
             s(row[6]) or "Non"))
        count += 1
    print(f"✓ Dépenses importées : {count}")

    # ============ PERSONNEL ============
    ws = wb["Personnel"]
    count = 0
    for row in ws.iter_rows(min_row=4, values_only=True):
        code = s(row[0])
        if not code or not code.startswith("EMP"):
            continue
        db.execute(
            "INSERT INTO employes (code, nom, poste, telephone, date_embauche, type_contrat, "
            "salaire_mensuel, statut) VALUES (?,?,?,?,?,?,?,?)",
            (code, s(row[1]) or "—", s(row[2]), s(row[3]), d(row[4]), s(row[5]) or "CDI",
             num(row[6]), s(row[7]) or "Actif"))
        count += 1
    print(f"✓ Employés importés : {count}")

    emp_code_to_id = {r["code"]: r["id"] for r in db.fetchall("SELECT id, code FROM employes")}
    emp_name_to_id = {r["nom"].lower(): r["id"] for r in db.fetchall("SELECT id, nom FROM employes")}

    # ============ PAIE ============
    ws = wb["Paie"]
    count = 0
    for row in ws.iter_rows(min_row=4, values_only=True):
        mois = s(row[0])
        emp_ref = s(row[2])
        if not mois or not emp_ref:
            continue
        employe_id = emp_code_to_id.get(emp_ref) or emp_name_to_id.get(emp_ref.lower())
        db.execute(
            "INSERT INTO paie (mois, annee, employe_id, salaire_du, avances_versees, net_a_payer, "
            "date_paiement, mode_paiement, statut) VALUES (?,?,?,?,?,?,?,?,?)",
            (mois, int(num(row[1], datetime.now().year)), employe_id, num(row[3]), num(row[4]),
             num(row[5]), d(row[6]), s(row[7]), s(row[8]) or "En attente"))
        count += 1
    print(f"✓ Paies importées : {count}")

    # ============ REÇUS ============
    ws = wb["Reçus"]
    count = 0
    for row in ws.iter_rows(min_row=4, values_only=True):
        numero = s(row[0])
        if not numero or not numero.startswith("RC"):
            continue
        client_id = resolve_client(s(row[2]))
        db.execute(
            "INSERT INTO recus (numero, date_recu, client_id, facture_numero, motif, montant_recu, "
            "mode_paiement, recu_par) VALUES (?,?,?,?,?,?,?,?)",
            (numero, d(row[1]), client_id, s(row[3]), s(row[4]), num(row[5]), s(row[6]), s(row[7])))
        count += 1
    print(f"✓ Reçus importés : {count}")

    # ============ NOTES CLIENT ============
    ws = wb["Notes"]
    count = 0
    for row in ws.iter_rows(min_row=4, values_only=True):
        numero = s(row[0])
        client_ref = s(row[2])
        if not client_ref:
            continue
        client_id = resolve_client(client_ref)
        db.execute(
            "INSERT INTO notes_client (numero, date_note, client_id, objet, contenu, redige_par) "
            "VALUES (?,?,?,?,?,?)",
            (numero, d(row[1]), client_id, s(row[3]), s(row[4]), s(row[5])))
        count += 1
    print(f"✓ Notes clients importées : {count}")

    # ============ CALCUL VITRES (tarifs + détail commandes) ============
    ws = wb["Calcul Vitres"]
    count = 0
    in_detail = False
    for row in ws.iter_rows(min_row=1, values_only=True):
        if row[0] == "Type de vitre" and row[1] == "Largeur (m)":
            in_detail = True
            continue
        if not in_detail:
            continue
        type_vitre = s(row[0])
        if not type_vitre:
            continue
        db.execute(
            "INSERT INTO commandes_vitres (type_vitre, largeur, hauteur, quantite, surface, "
            "prix_unitaire, montant) VALUES (?,?,?,?,?,?,?)",
            (type_vitre, num(row[1]), num(row[2]), int(num(row[3], 1)), num(row[4]), num(row[5]),
             num(row[6])))
        count += 1
    print(f"✓ Commandes de vitres importées : {count}")

    db.close()
    print("\n🎉 Import terminé avec succès ! Toutes tes données sont maintenant dans MK Suite.")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage : python import_excel_data.py chemin/vers/GESTIONNAIE_DE_FICHIER.xlsx")
        sys.exit(1)
    import_all(sys.argv[1])
