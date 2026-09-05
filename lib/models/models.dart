/// Modèles de données MK Suite — un miroir fidèle du schéma SQLite de la
/// version ordinateur (voir database/db_manager.py côté Python), avec en
/// plus `updatedAt` (et `syncId` pour les tables qui n'ont pas de clé
/// métier naturelle) utilisés par la synchronisation Wi-Fi.
library;

class Client {
  final int id;
  final String syncId;
  final String code;
  final String nom;
  final String typeClient; // Particulier / Entreprise / Chantier
  final String telephone;
  final String adresse;
  final String nif;
  final String datePremierContact;
  final String statut; // Actif / Inactif
  final int updatedAt;

  const Client({
    required this.id, required this.syncId, required this.code, required this.nom, required this.typeClient,
    required this.telephone, required this.adresse, required this.nif,
    required this.datePremierContact, required this.statut, required this.updatedAt,
  });

  factory Client.fromMap(Map<String, dynamic> m) => Client(
        id: m['id'] as int, syncId: (m['sync_id'] ?? '') as String, code: (m['code'] ?? '') as String, nom: (m['nom'] ?? '') as String,
        typeClient: (m['type_client'] ?? 'Particulier') as String, telephone: (m['telephone'] ?? '') as String,
        adresse: (m['adresse'] ?? '') as String, nif: (m['nif'] ?? '') as String,
        datePremierContact: (m['date_premier_contact'] ?? '') as String, statut: (m['statut'] ?? 'Actif') as String,
        updatedAt: (m['updated_at'] ?? 0) as int,
      );

  Map<String, dynamic> toMap() => {
        'sync_id': syncId, 'code': code, 'nom': nom, 'type_client': typeClient, 'telephone': telephone,
        'adresse': adresse, 'nif': nif, 'date_premier_contact': datePremierContact,
        'statut': statut, 'updated_at': updatedAt,
      };

  Client copyWith({String? nom, String? typeClient, String? telephone, String? adresse, String? nif, String? statut, int? updatedAt}) => Client(
        id: id, syncId: syncId, code: code, nom: nom ?? this.nom, typeClient: typeClient ?? this.typeClient,
        telephone: telephone ?? this.telephone, adresse: adresse ?? this.adresse, nif: nif ?? this.nif,
        datePremierContact: datePremierContact, statut: statut ?? this.statut, updatedAt: updatedAt ?? this.updatedAt,
      );
}

class Fournisseur {
  final int id;
  final String syncId;
  final String nom;
  final String categorieProduits;
  final String contact;
  final String telephone;
  final String adresse;
  final int updatedAt;

  const Fournisseur({required this.id, required this.syncId, required this.nom, required this.categorieProduits, required this.contact, required this.telephone, required this.adresse, required this.updatedAt});

  factory Fournisseur.fromMap(Map<String, dynamic> m) => Fournisseur(
        id: m['id'] as int, syncId: (m['sync_id'] ?? '') as String, nom: (m['nom'] ?? '') as String, categorieProduits: (m['categorie_produits'] ?? '') as String,
        contact: (m['contact'] ?? '') as String, telephone: (m['telephone'] ?? '') as String,
        adresse: (m['adresse'] ?? '') as String, updatedAt: (m['updated_at'] ?? 0) as int,
      );

  Map<String, dynamic> toMap() => {'sync_id': syncId, 'nom': nom, 'categorie_produits': categorieProduits, 'contact': contact, 'telephone': telephone, 'adresse': adresse, 'updated_at': updatedAt};
}

class LigneDocument {
  final int id;
  final String syncId;
  final String parentNumero; // devis_numero ou facture_numero
  final double quantite;
  final String description;
  final double prixUnitaire;
  final double totalLigne;
  final int updatedAt;

  const LigneDocument({
    required this.id, required this.syncId, required this.parentNumero, required this.quantite,
    required this.description, required this.prixUnitaire, required this.totalLigne, required this.updatedAt,
  });

  factory LigneDocument.fromMap(Map<String, dynamic> m, {required String parentKeyColumn}) => LigneDocument(
        id: m['id'] as int, syncId: (m['sync_id'] ?? '') as String, parentNumero: (m[parentKeyColumn] ?? '') as String,
        quantite: ((m['quantite'] ?? 0) as num).toDouble(), description: (m['description'] ?? '') as String,
        prixUnitaire: ((m['prix_unitaire'] ?? 0) as num).toDouble(), totalLigne: ((m['total_ligne'] ?? 0) as num).toDouble(),
        updatedAt: (m['updated_at'] ?? 0) as int,
      );
}

class Devis {
  final int id;
  final String syncId;
  final String numero;
  final String dateDevis;
  final int? clientId;
  final String objet;
  final double montantHt;
  final String statut; // En attente / Accepté / Refusé
  final int validiteJours;
  final String? dateLimite;
  final String? convertiFacture;
  final bool appliquerTva;
  final int updatedAt;

  const Devis({
    required this.id, required this.syncId, required this.numero, required this.dateDevis, required this.clientId, required this.objet,
    required this.montantHt, required this.statut, required this.validiteJours, required this.dateLimite,
    required this.convertiFacture, required this.appliquerTva, required this.updatedAt,
  });

  factory Devis.fromMap(Map<String, dynamic> m) => Devis(
        id: m['id'] as int, syncId: (m['sync_id'] ?? '') as String, numero: (m['numero'] ?? '') as String, dateDevis: (m['date_devis'] ?? '') as String,
        clientId: m['client_id'] as int?, objet: (m['objet'] ?? '') as String,
        montantHt: ((m['montant_ht'] ?? 0) as num).toDouble(), statut: (m['statut'] ?? 'En attente') as String,
        validiteJours: (m['validite_jours'] ?? 30) as int, dateLimite: m['date_limite'] as String?,
        convertiFacture: m['converti_facture'] as String?, appliquerTva: ((m['appliquer_tva'] ?? 1) as int) != 0,
        updatedAt: (m['updated_at'] ?? 0) as int,
      );

  Map<String, dynamic> toMap() => {
        'sync_id': syncId, 'numero': numero, 'date_devis': dateDevis, 'client_id': clientId, 'objet': objet, 'montant_ht': montantHt,
        'statut': statut, 'validite_jours': validiteJours, 'date_limite': dateLimite, 'converti_facture': convertiFacture,
        'appliquer_tva': appliquerTva ? 1 : 0, 'updated_at': updatedAt,
      };
}

class Facture {
  final int id;
  final String syncId;
  final String numero;
  final String dateFacture;
  final String? devisNumero;
  final int? clientId;
  final String description;
  final double montantHt;
  final double reductionPct;
  final double montantHtNet;
  final double tva;
  final double montantTtc;
  final double avanceRecue;
  final double resteAPayer;
  final String statut; // Impayée / Partielle / Payée
  final String modePaiement;
  final int updatedAt;

  const Facture({
    required this.id, required this.syncId, required this.numero, required this.dateFacture, required this.devisNumero, required this.clientId,
    required this.description, required this.montantHt, required this.reductionPct, required this.montantHtNet,
    required this.tva, required this.montantTtc, required this.avanceRecue, required this.resteAPayer,
    required this.statut, required this.modePaiement, required this.updatedAt,
  });

  factory Facture.fromMap(Map<String, dynamic> m) => Facture(
        id: m['id'] as int, syncId: (m['sync_id'] ?? '') as String, numero: (m['numero'] ?? '') as String, dateFacture: (m['date_facture'] ?? '') as String,
        devisNumero: m['devis_numero'] as String?, clientId: m['client_id'] as int?, description: (m['description'] ?? '') as String,
        montantHt: ((m['montant_ht'] ?? 0) as num).toDouble(), reductionPct: ((m['reduction_pct'] ?? 0) as num).toDouble(),
        montantHtNet: ((m['montant_ht_net'] ?? 0) as num).toDouble(), tva: ((m['tva'] ?? 0) as num).toDouble(),
        montantTtc: ((m['montant_ttc'] ?? 0) as num).toDouble(), avanceRecue: ((m['avance_recue'] ?? 0) as num).toDouble(),
        resteAPayer: ((m['reste_a_payer'] ?? 0) as num).toDouble(), statut: (m['statut'] ?? 'Impayée') as String,
        modePaiement: (m['mode_paiement'] ?? '') as String, updatedAt: (m['updated_at'] ?? 0) as int,
      );

  Map<String, dynamic> toMap() => {
        'sync_id': syncId, 'numero': numero, 'date_facture': dateFacture, 'devis_numero': devisNumero, 'client_id': clientId,
        'description': description, 'montant_ht': montantHt, 'reduction_pct': reductionPct, 'montant_ht_net': montantHtNet,
        'tva': tva, 'montant_ttc': montantTtc, 'avance_recue': avanceRecue, 'reste_a_payer': resteAPayer,
        'statut': statut, 'mode_paiement': modePaiement, 'updated_at': updatedAt,
      };
}

class Recu {
  final int id;
  final String syncId;
  final String numero;
  final String dateRecu;
  final int? clientId;
  final String? factureNumero;
  final String motif;
  final double montantRecu;
  final String modePaiement;
  final String recuPar;
  final int updatedAt;

  const Recu({
    required this.id, required this.syncId, required this.numero, required this.dateRecu, required this.clientId, required this.factureNumero,
    required this.motif, required this.montantRecu, required this.modePaiement, required this.recuPar, required this.updatedAt,
  });

  factory Recu.fromMap(Map<String, dynamic> m) => Recu(
        id: m['id'] as int, syncId: (m['sync_id'] ?? '') as String, numero: (m['numero'] ?? '') as String, dateRecu: (m['date_recu'] ?? '') as String,
        clientId: m['client_id'] as int?, factureNumero: m['facture_numero'] as String?, motif: (m['motif'] ?? '') as String,
        montantRecu: ((m['montant_recu'] ?? 0) as num).toDouble(), modePaiement: (m['mode_paiement'] ?? '') as String,
        recuPar: (m['recu_par'] ?? '') as String, updatedAt: (m['updated_at'] ?? 0) as int,
      );

  Map<String, dynamic> toMap() => {
        'sync_id': syncId, 'numero': numero, 'date_recu': dateRecu, 'client_id': clientId, 'facture_numero': factureNumero,
        'motif': motif, 'montant_recu': montantRecu, 'mode_paiement': modePaiement, 'recu_par': recuPar, 'updated_at': updatedAt,
      };
}

class NoteClient {
  final int id;
  final String syncId;
  final String numero;
  final String dateNote;
  final int? clientId;
  final String objet;
  final String contenu;
  final String redigePar;
  final int updatedAt;

  const NoteClient({
    required this.id, required this.syncId, required this.numero, required this.dateNote, required this.clientId,
    required this.objet, required this.contenu, required this.redigePar, required this.updatedAt,
  });

  factory NoteClient.fromMap(Map<String, dynamic> m) => NoteClient(
        id: m['id'] as int, syncId: (m['sync_id'] ?? '') as String, numero: (m['numero'] ?? '') as String, dateNote: (m['date_note'] ?? '') as String,
        clientId: m['client_id'] as int?, objet: (m['objet'] ?? '') as String, contenu: (m['contenu'] ?? '') as String,
        redigePar: (m['redige_par'] ?? '') as String, updatedAt: (m['updated_at'] ?? 0) as int,
      );

  Map<String, dynamic> toMap() => {
        'sync_id': syncId, 'numero': numero, 'date_note': dateNote, 'client_id': clientId, 'objet': objet,
        'contenu': contenu, 'redige_par': redigePar, 'updated_at': updatedAt,
      };
}

class Depense {
  final int id;
  final String syncId;
  final String dateDepense;
  final String categorie;
  final String description;
  final String beneficiaire;
  final double montant;
  final String modePaiement;
  final String justificatif; // Oui / Non
  final int updatedAt;

  const Depense({
    required this.id, required this.syncId, required this.dateDepense, required this.categorie, required this.description,
    required this.beneficiaire, required this.montant, required this.modePaiement, required this.justificatif, required this.updatedAt,
  });

  factory Depense.fromMap(Map<String, dynamic> m) => Depense(
        id: m['id'] as int, syncId: (m['sync_id'] ?? '') as String, dateDepense: (m['date_depense'] ?? '') as String,
        categorie: (m['categorie'] ?? '') as String, description: (m['description'] ?? '') as String,
        beneficiaire: (m['beneficiaire'] ?? '') as String, montant: ((m['montant'] ?? 0) as num).toDouble(),
        modePaiement: (m['mode_paiement'] ?? 'Espèces') as String, justificatif: (m['justificatif'] ?? 'Non') as String,
        updatedAt: (m['updated_at'] ?? 0) as int,
      );

  Map<String, dynamic> toMap() => {
        'sync_id': syncId, 'date_depense': dateDepense, 'categorie': categorie, 'description': description,
        'beneficiaire': beneficiaire, 'montant': montant, 'mode_paiement': modePaiement,
        'justificatif': justificatif, 'updated_at': updatedAt,
      };
}

class BudgetCategorie {
  final int id;
  final String syncId;
  final String categorie;
  final String mois;
  final int annee;
  final double budgetPrevu;
  final int updatedAt;

  const BudgetCategorie({required this.id, required this.syncId, required this.categorie, required this.mois, required this.annee, required this.budgetPrevu, required this.updatedAt});

  factory BudgetCategorie.fromMap(Map<String, dynamic> m) => BudgetCategorie(
        id: m['id'] as int, syncId: (m['sync_id'] ?? '') as String, categorie: (m['categorie'] ?? '') as String,
        mois: (m['mois'] ?? '') as String, annee: (m['annee'] ?? 0) as int,
        budgetPrevu: ((m['budget_prevu'] ?? 0) as num).toDouble(), updatedAt: (m['updated_at'] ?? 0) as int,
      );

  Map<String, dynamic> toMap() => {'sync_id': syncId, 'categorie': categorie, 'mois': mois, 'annee': annee, 'budget_prevu': budgetPrevu, 'updated_at': updatedAt};
}

class TarifVitre {
  final int id;
  final String syncId;
  final String typeVitre;
  final double prixM2;
  final int updatedAt;

  const TarifVitre({required this.id, required this.syncId, required this.typeVitre, required this.prixM2, required this.updatedAt});

  factory TarifVitre.fromMap(Map<String, dynamic> m) => TarifVitre(
        id: m['id'] as int, syncId: (m['sync_id'] ?? '') as String, typeVitre: (m['type_vitre'] ?? '') as String,
        prixM2: ((m['prix_m2'] ?? 0) as num).toDouble(), updatedAt: (m['updated_at'] ?? 0) as int,
      );

  Map<String, dynamic> toMap() => {'sync_id': syncId, 'type_vitre': typeVitre, 'prix_m2': prixM2, 'updated_at': updatedAt};
}

class CommandeVitre {
  final int id;
  final String syncId;
  final String dateCommande;
  final String typeVitre;
  final double largeur;
  final double hauteur;
  final int quantite;
  final double surface;
  final double prixUnitaire;
  final double montant;
  final String? devisNumero;
  final String? factureNumero;
  final int updatedAt;

  const CommandeVitre({
    required this.id, required this.syncId, required this.dateCommande, required this.typeVitre, required this.largeur,
    required this.hauteur, required this.quantite, required this.surface, required this.prixUnitaire, required this.montant,
    required this.devisNumero, required this.factureNumero, required this.updatedAt,
  });

  factory CommandeVitre.fromMap(Map<String, dynamic> m) => CommandeVitre(
        id: m['id'] as int, syncId: (m['sync_id'] ?? '') as String, dateCommande: (m['date_commande'] ?? '') as String,
        typeVitre: (m['type_vitre'] ?? '') as String, largeur: ((m['largeur'] ?? 0) as num).toDouble(),
        hauteur: ((m['hauteur'] ?? 0) as num).toDouble(), quantite: (m['quantite'] ?? 0) as int,
        surface: ((m['surface'] ?? 0) as num).toDouble(), prixUnitaire: ((m['prix_unitaire'] ?? 0) as num).toDouble(),
        montant: ((m['montant'] ?? 0) as num).toDouble(), devisNumero: m['devis_numero'] as String?,
        factureNumero: m['facture_numero'] as String?, updatedAt: (m['updated_at'] ?? 0) as int,
      );

  Map<String, dynamic> toMap() => {
        'sync_id': syncId, 'date_commande': dateCommande, 'type_vitre': typeVitre, 'largeur': largeur, 'hauteur': hauteur,
        'quantite': quantite, 'surface': surface, 'prix_unitaire': prixUnitaire, 'montant': montant,
        'devis_numero': devisNumero, 'facture_numero': factureNumero, 'updated_at': updatedAt,
      };
}

class SourcingCommande {
  final int id;
  final String syncId;
  final String numero;
  final String dateCommande;
  final int? fournisseurId;
  final int? clientId;
  final String designation;
  final double quantite;
  final double prixAchatUnitaire;
  final double prixVenteUnitaire;
  final String statut; // En cours / Livré / Annulé
  final String? dateLivraisonPrevue;
  final String notes;
  final int updatedAt;

  const SourcingCommande({
    required this.id, required this.syncId, required this.numero, required this.dateCommande, required this.fournisseurId, required this.clientId,
    required this.designation, required this.quantite, required this.prixAchatUnitaire, required this.prixVenteUnitaire,
    required this.statut, required this.dateLivraisonPrevue, required this.notes, required this.updatedAt,
  });

  double get marge => (prixVenteUnitaire - prixAchatUnitaire) * quantite;
  double get totalAchat => prixAchatUnitaire * quantite;
  double get totalVente => prixVenteUnitaire * quantite;

  factory SourcingCommande.fromMap(Map<String, dynamic> m) => SourcingCommande(
        id: m['id'] as int, syncId: (m['sync_id'] ?? '') as String, numero: (m['numero'] ?? '') as String, dateCommande: (m['date_commande'] ?? '') as String,
        fournisseurId: m['fournisseur_id'] as int?, clientId: m['client_id'] as int?, designation: (m['designation'] ?? '') as String,
        quantite: ((m['quantite'] ?? 1) as num).toDouble(), prixAchatUnitaire: ((m['prix_achat_unitaire'] ?? 0) as num).toDouble(),
        prixVenteUnitaire: ((m['prix_vente_unitaire'] ?? 0) as num).toDouble(), statut: (m['statut'] ?? 'En cours') as String,
        dateLivraisonPrevue: m['date_livraison_prevue'] as String?, notes: (m['notes'] ?? '') as String,
        updatedAt: (m['updated_at'] ?? 0) as int,
      );

  Map<String, dynamic> toMap() => {
        'sync_id': syncId, 'numero': numero, 'date_commande': dateCommande, 'fournisseur_id': fournisseurId, 'client_id': clientId,
        'designation': designation, 'quantite': quantite, 'prix_achat_unitaire': prixAchatUnitaire,
        'prix_vente_unitaire': prixVenteUnitaire, 'statut': statut, 'date_livraison_prevue': dateLivraisonPrevue,
        'notes': notes, 'updated_at': updatedAt,
      };
}

class Employe {
  final int id;
  final String syncId;
  final String code;
  final String nom;
  final String poste;
  final String telephone;
  final String? dateEmbauche;
  final String typeContrat; // CDI / CDD / Journalier / Stage
  final double salaireMensuel;
  final String statut; // Actif / Inactif
  final int updatedAt;

  const Employe({
    required this.id, required this.syncId, required this.code, required this.nom, required this.poste, required this.telephone,
    required this.dateEmbauche, required this.typeContrat, required this.salaireMensuel, required this.statut, required this.updatedAt,
  });

  factory Employe.fromMap(Map<String, dynamic> m) => Employe(
        id: m['id'] as int, syncId: (m['sync_id'] ?? '') as String, code: (m['code'] ?? '') as String, nom: (m['nom'] ?? '') as String, poste: (m['poste'] ?? '') as String,
        telephone: (m['telephone'] ?? '') as String, dateEmbauche: m['date_embauche'] as String?,
        typeContrat: (m['type_contrat'] ?? 'CDI') as String, salaireMensuel: ((m['salaire_mensuel'] ?? 0) as num).toDouble(),
        statut: (m['statut'] ?? 'Actif') as String, updatedAt: (m['updated_at'] ?? 0) as int,
      );

  Map<String, dynamic> toMap() => {
        'sync_id': syncId, 'code': code, 'nom': nom, 'poste': poste, 'telephone': telephone, 'date_embauche': dateEmbauche,
        'type_contrat': typeContrat, 'salaire_mensuel': salaireMensuel, 'statut': statut, 'updated_at': updatedAt,
      };
}

class Paie {
  final int id;
  final String syncId;
  final String mois;
  final int annee;
  final int? employeId;
  final double salaireDu;
  final double avancesVersees;
  final double netAPayer;
  final String? datePaiement;
  final String modePaiement;
  final String statut; // En attente / Payé
  final int updatedAt;

  const Paie({
    required this.id, required this.syncId, required this.mois, required this.annee, required this.employeId,
    required this.salaireDu, required this.avancesVersees, required this.netAPayer, required this.datePaiement,
    required this.modePaiement, required this.statut, required this.updatedAt,
  });

  factory Paie.fromMap(Map<String, dynamic> m) => Paie(
        id: m['id'] as int, syncId: (m['sync_id'] ?? '') as String, mois: (m['mois'] ?? '') as String, annee: (m['annee'] ?? 0) as int,
        employeId: m['employe_id'] as int?, salaireDu: ((m['salaire_du'] ?? 0) as num).toDouble(),
        avancesVersees: ((m['avances_versees'] ?? 0) as num).toDouble(), netAPayer: ((m['net_a_payer'] ?? 0) as num).toDouble(),
        datePaiement: m['date_paiement'] as String?, modePaiement: (m['mode_paiement'] ?? '') as String,
        statut: (m['statut'] ?? 'En attente') as String, updatedAt: (m['updated_at'] ?? 0) as int,
      );

  Map<String, dynamic> toMap() => {
        'sync_id': syncId, 'mois': mois, 'annee': annee, 'employe_id': employeId, 'salaire_du': salaireDu,
        'avances_versees': avancesVersees, 'net_a_payer': netAPayer, 'date_paiement': datePaiement,
        'mode_paiement': modePaiement, 'statut': statut, 'updated_at': updatedAt,
      };
}

class CorbeilleItem {
  final int id;
  final String syncId;
  final String tableOrigine;
  final int? idOrigine;
  final String? origineKey;
  final String libelle;
  final String module;
  final String donneesJson;
  final String dateSuppression;
  final int deletedAt;
  final bool restaure;

  const CorbeilleItem({
    required this.id, required this.syncId, required this.tableOrigine, required this.idOrigine, required this.origineKey,
    required this.libelle, required this.module, required this.donneesJson, required this.dateSuppression,
    required this.deletedAt, required this.restaure,
  });

  factory CorbeilleItem.fromMap(Map<String, dynamic> m) => CorbeilleItem(
        id: m['id'] as int, syncId: (m['sync_id'] ?? '') as String, tableOrigine: (m['table_origine'] ?? '') as String,
        idOrigine: m['id_origine'] as int?, origineKey: m['origine_key'] as String?, libelle: (m['libelle'] ?? '') as String,
        module: (m['module'] ?? '') as String, donneesJson: (m['donnees_json'] ?? '{}') as String,
        dateSuppression: (m['date_suppression'] ?? '') as String, deletedAt: (m['deleted_at'] ?? 0) as int,
        restaure: ((m['restaure'] ?? 0) as int) != 0,
      );
}
