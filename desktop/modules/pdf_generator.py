"""
MK Suite - Génération de documents PDF
Reproduit exactement la mise en page des modèles Excel : Devis, Facture, Reçu, Note.
En-tête MK Entreprise (logo, coordonnées, N° fiscal, compte bancaire).
"""
import os
import sys
import subprocess
from datetime import datetime
from xml.sax.saxutils import escape as _xml_escape
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_LEFT, TA_RIGHT, TA_CENTER
from reportlab.platypus import (SimpleDocTemplate, Table, TableStyle, Paragraph,
                                  Spacer, Image, HRFlowable)
from resource_path import resource_path


def _esc(text):
    """Échappe un texte saisi par l'utilisateur avant de l'insérer dans le
    HTML minimal compris par les Paragraph de reportlab (sinon un '&' ou un
    '<' dans une description/adresse casse l'affichage, voire la génération
    du PDF)."""
    return _xml_escape(str(text)) if text else ""

def open_file(path):
    """Ouvre un fichier (PDF) avec l'application par défaut du système."""
    try:
        if sys.platform.startswith("win"):
            os.startfile(path)
        elif sys.platform == "darwin":
            subprocess.run(["open", path])
        else:
            subprocess.run(["xdg-open", path])
    except Exception:
        pass


def print_file(path):
    """Envoie directement le fichier (PDF) à l'imprimante par défaut, sans avoir
    besoin de l'ouvrir manuellement au préalable."""
    try:
        if sys.platform.startswith("win"):
            os.startfile(path, "print")
        elif sys.platform == "darwin":
            subprocess.run(["lp", path])
        else:
            subprocess.run(["lp", path])
        return True
    except Exception:
        # Si l'impression directe échoue (pas d'imprimante configurée, etc.),
        # on ouvre au moins le fichier pour que l'utilisateur imprime manuellement.
        open_file(path)
        return False


# ===== Coordonnées de l'entreprise, reprises exactement du modèle Excel =====
from modules.company_profile import load_profile
ENTREPRISE = load_profile()


GOLD = colors.HexColor("#B8952E")
DARK = colors.HexColor("#0B1220")
GREY = colors.HexColor("#5A6478")
LOGO_PATH = resource_path("assets", "logo.png")

NUM_TO_WORDS_UNITS = ["", "un", "deux", "trois", "quatre", "cinq", "six", "sept", "huit", "neuf"]
NUM_TO_WORDS_TEENS = ["dix", "onze", "douze", "treize", "quatorze", "quinze", "seize",
                       "dix-sept", "dix-huit", "dix-neuf"]
NUM_TO_WORDS_TENS = ["", "", "vingt", "trente", "quarante", "cinquante", "soixante",
                     "soixante-dix", "quatre-vingt", "quatre-vingt-dix"]


def _three_digits_to_words(n):
    if n == 0:
        return ""
    hundreds, rest = divmod(n, 100)
    parts = []
    if hundreds:
        parts.append(("cent" if hundreds == 1 else NUM_TO_WORDS_UNITS[hundreds] + " cent"))
    if rest:
        if rest < 10:
            parts.append(NUM_TO_WORDS_UNITS[rest])
        elif rest < 20:
            parts.append(NUM_TO_WORDS_TEENS[rest - 10])
        else:
            tens, units = divmod(rest, 10)
            word = NUM_TO_WORDS_TENS[tens]
            if tens in (7, 9):
                word = NUM_TO_WORDS_TENS[tens - 1] + "-" + NUM_TO_WORDS_TEENS[units]
            elif units:
                word += "-" + NUM_TO_WORDS_UNITS[units]
            parts.append(word)
    return " ".join(parts)


def number_to_french_words(n):
    """Convertit un montant en toutes lettres (français), ex: 2300000 -> DEUX MILLION TROIS CENT MILLE"""
    n = int(round(n))
    if n == 0:
        return "ZÉRO"
    millions, reste = divmod(n, 1_000_000)
    milliers, unites = divmod(reste, 1000)
    parts = []
    if millions:
        parts.append((_three_digits_to_words(millions) + " million" + ("s" if millions > 1 else "")))
    if milliers:
        if milliers == 1:
            parts.append("mille")
        else:
            parts.append(_three_digits_to_words(milliers) + " mille")
    if unites:
        parts.append(_three_digits_to_words(unites))
    return " ".join(parts).upper()


def _header(elements, doc_type, numero, date_str):
    """En-tête commun à tous les documents : logo + coordonnées + type/numéro/date"""
    styles_name = ParagraphStyle("EntNom", fontName="Helvetica-Bold", fontSize=15,
                                  textColor=DARK, spaceAfter=2)
    styles_small = ParagraphStyle("EntSmall", fontName="Helvetica", fontSize=7.5,
                                   textColor=GREY, leading=10)
    styles_doctype = ParagraphStyle("DocType", fontName="Helvetica-Bold", fontSize=20,
                                     textColor=GOLD, alignment=TA_RIGHT)
    styles_docnum = ParagraphStyle("DocNum", fontName="Helvetica", fontSize=10,
                                    textColor=DARK, alignment=TA_RIGHT)

    logo_cell = ""
    if os.path.exists(LOGO_PATH):
        logo_cell = Image(LOGO_PATH, width=16 * mm, height=16 * mm)

    info_html = (
        f"<b>{ENTREPRISE['nom']}</b><br/>"
        f"{ENTREPRISE['activite']}<br/>"
        f"{ENTREPRISE['adresse']}<br/>"
        f"Tél : {ENTREPRISE['telephones']} &nbsp;|&nbsp; Email : {ENTREPRISE['email']}<br/>"
        f"Certificat d'immatriculation : {ENTREPRISE['immatriculation']} &nbsp;|&nbsp; "
        f"N° Fiscale : {ENTREPRISE['num_fiscal']}"
    )
    info_para = Paragraph(info_html, styles_small)

    right_html = f"<b>{doc_type}</b><br/><br/>N° : {numero}<br/>Date : {date_str}"
    right_para = Paragraph(
        f"<font color='#B8952E' size='18'><b>{doc_type}</b></font><br/><br/>"
        f"<font size='10'>N° : {numero}<br/>Date : {date_str}</font>",
        ParagraphStyle("Right", alignment=TA_RIGHT, leading=14))

    header_table = Table([[logo_cell, info_para, right_para]],
                          colWidths=[20 * mm, 105 * mm, 55 * mm])
    header_table.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (0, 0), 0),
        ("LEFTPADDING", (1, 0), (1, 0), 8),
    ]))
    elements.append(header_table)
    elements.append(Spacer(1, 6))
    elements.append(HRFlowable(width="100%", thickness=1.2, color=GOLD))
    elements.append(Spacer(1, 10))


def _client_block(elements, title, client_nom, client_tel, extra_label=None, extra_value=None,
                   client_nif=None):
    style_label = ParagraphStyle("Label", fontName="Helvetica-Bold", fontSize=9.5, textColor=DARK,
                                  leading=12)
    style_val = ParagraphStyle("Val", fontName="Helvetica", fontSize=9.5, textColor=DARK, leading=12)
    elements.append(Paragraph(f"<b>{title}</b>", ParagraphStyle(
        "Section", fontName="Helvetica-Bold", fontSize=10, textColor=GOLD, spaceAfter=4)))
    # Chaque valeur passe par un Paragraph (au lieu d'une simple chaîne) pour
    # qu'un texte long (adresse, NIF...) revienne automatiquement à la ligne
    # DANS sa propre colonne au lieu de déborder par-dessus la colonne voisine.
    rows = [
        [Paragraph("Nom du client :", style_label), Paragraph(_esc(client_nom) or "—", style_val)],
        [Paragraph("Téléphone :", style_label), Paragraph(_esc(client_tel) or "—", style_val)],
    ]
    if extra_label:
        rows.append([Paragraph(_esc(extra_label), style_label), Paragraph(_esc(extra_value) or "—", style_val)])
    if client_nif:
        rows.append([Paragraph("NIF :", style_label), Paragraph(_esc(client_nif), style_val)])
    t = Table(rows, colWidths=[38 * mm, 120 * mm])
    t.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
        ("TOPPADDING", (0, 0), (-1, -1), 3),
    ]))
    elements.append(t)
    elements.append(Spacer(1, 12))


def _footer_note(elements, text):
    elements.append(Spacer(1, 16))
    elements.append(HRFlowable(width="100%", thickness=0.6, color=colors.HexColor("#CCCCCC")))
    elements.append(Spacer(1, 6))
    elements.append(Paragraph(text, ParagraphStyle(
        "Footer", fontName="Helvetica-Oblique", fontSize=8, textColor=GREY)))


def _lines_table(elements, lignes, with_unit_price=True):
    """lignes: liste de dicts {quantite, description, prix_unitaire, total_ligne}"""
    header = ["Qté", "Description", "Prix Unit. (FCFA)", "Total (FCFA)"] if with_unit_price \
        else ["Qté", "Description", "Total (FCFA)"]
    # La description est mise dans un Paragraph (pas une simple chaîne) :
    # reportlab ne revient alors à la ligne QUE dans la largeur de sa propre
    # colonne, au lieu de laisser le texte déborder par-dessus la colonne
    # "Prix Unitaire" quand la phrase est longue.
    style_desc = ParagraphStyle("LigneDesc", fontName="Helvetica", fontSize=9,
                                 textColor=DARK, leading=11)
    data = [header]
    for l in lignes:
        desc = Paragraph(_esc(l["description"]) or "—", style_desc)
        if with_unit_price:
            data.append([str(int(l["quantite"])), desc,
                         f"{l['prix_unitaire']:,.0f}".replace(",", " "),
                         f"{l['total_ligne']:,.0f}".replace(",", " ")])
        else:
            data.append([str(int(l["quantite"])), desc,
                         f"{l['total_ligne']:,.0f}".replace(",", " ")])

    col_widths = [15 * mm, 90 * mm, 30 * mm, 30 * mm] if with_unit_price else [15 * mm, 110 * mm, 30 * mm]
    t = Table(data, colWidths=col_widths, repeatRows=1)
    style = [
        ("BACKGROUND", (0, 0), (-1, 0), DARK),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTNAME", (0, 1), (-1, -1), "Helvetica"),
        ("FONTSIZE", (0, 0), (-1, -1), 9),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("ALIGN", (0, 0), (0, -1), "CENTER"),
        ("ALIGN", (-1, 0), (-1, -1), "RIGHT"),
        ("ALIGN", (-2, 0), (-2, -1), "RIGHT") if with_unit_price else ("ALIGN", (0, 0), (0, 0), "CENTER"),
        ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#DDDDDD")),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F5F5F5")]),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
    ]
    t.setStyle(TableStyle(style))
    elements.append(t)
    elements.append(Spacer(1, 10))


def generate_vitres_pdf(output_path, lignes, total_surface, total_montant):
    """lignes : liste de dicts {type_vitre, largeur, hauteur, quantite, surface, montant}"""
    doc = SimpleDocTemplate(output_path, pagesize=A4,
                             topMargin=15 * mm, bottomMargin=15 * mm,
                             leftMargin=18 * mm, rightMargin=18 * mm)
    elements = []
    _header(elements, "CALCUL VITRES", f"CV-{datetime.now().strftime('%Y%m%d-%H%M')}",
            datetime.now().strftime("%d/%m/%Y"))

    # "Type de vitre" est un texte libre saisi par l'utilisateur : on le
    # met dans un Paragraph pour qu'il revienne à la ligne dans sa colonne
    # au lieu de déborder sur "Largeur (m)" quand le texte est long.
    style_type = ParagraphStyle("TypeVitre", fontName="Helvetica", fontSize=9, textColor=DARK, leading=11)
    data = [["Type de vitre", "Largeur (m)", "Hauteur (m)", "Qté", "Surface (m²)", "Montant (FCFA)"]]
    for l in lignes:
        data.append([
            Paragraph(_esc((l.get("repere", "") + " · " if l.get("repere") else "") + l["type_vitre"]) or "—", style_type),
            f"{l['largeur']:.2f}", f"{l['hauteur']:.2f}", str(int(l["quantite"])),
            f"{l['surface']:.3f}", f"{l['montant']:,.0f}".replace(",", " "),
        ])
    col_widths = [45 * mm, 25 * mm, 25 * mm, 15 * mm, 25 * mm, 30 * mm]
    t = Table(data, colWidths=col_widths, repeatRows=1)
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), DARK),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTNAME", (0, 1), (-1, -1), "Helvetica"),
        ("FONTSIZE", (0, 0), (-1, -1), 9),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("ALIGN", (1, 0), (-1, -1), "CENTER"),
        ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#DDDDDD")),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F5F5F5")]),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
    ]))
    elements.append(t)
    elements.append(Spacer(1, 14))

    totals_data = [
        ["Surface totale", f"{total_surface:.3f} m²"],
        ["Montant total", f"{total_montant:,.0f} FCFA".replace(",", " ")],
    ]
    tt = Table(totals_data, colWidths=[140 * mm, 40 * mm])
    tt.setStyle(TableStyle([
        ("FONTNAME", (0, 0), (-1, -1), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 11),
        ("ALIGN", (1, 0), (1, -1), "RIGHT"),
        ("LINEABOVE", (0, 0), (-1, 0), 1, GOLD),
        ("TOPPADDING", (0, 0), (-1, -1), 6),
        ("TEXTCOLOR", (0, -1), (-1, -1), GOLD),
        ("FONTSIZE", (0, -1), (-1, -1), 13),
    ]))
    elements.append(tt)

    _footer_note(elements, "Document généré automatiquement par MK Suite — Calcul Vitres.")
    doc.build(elements)
    return output_path


def generate_devis_pdf(output_path, devis_row, client_row, lignes):
    doc = SimpleDocTemplate(output_path, pagesize=A4,
                             topMargin=15 * mm, bottomMargin=15 * mm,
                             leftMargin=18 * mm, rightMargin=18 * mm)
    elements = []
    date_str = devis_row["date_devis"][:10] if devis_row["date_devis"] else ""
    _header(elements, "DEVIS", devis_row["numero"], date_str)
    _client_block(elements, "DOIT À :", client_row["nom"] if client_row else "—",
                  client_row["telephone"] if client_row else "—",
                  "Adresse / Chantier :", client_row["adresse"] if client_row else "—",
                  client_nif=client_row["nif"] if client_row else None)
    if devis_row["objet"]:
        elements.append(Paragraph(f"<b>Objet :</b> {_esc(devis_row['objet'])}",
                                   ParagraphStyle("Objet", fontSize=9.5, spaceAfter=10)))
    _lines_table(elements, lignes, with_unit_price=True)

    total_ht = sum(l["total_ligne"] for l in lignes) or devis_row["montant_ht"]
    total_table = Table([["Montant HT (FCFA)", f"{total_ht:,.0f}".replace(",", " ")]],
                         colWidths=[135 * mm, 30 * mm])
    total_table.setStyle(TableStyle([
        ("FONTNAME", (0, 0), (-1, -1), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 11),
        ("ALIGN", (1, 0), (1, 0), "RIGHT"),
        ("LINEABOVE", (0, 0), (-1, 0), 1, GOLD),
        ("TOPPADDING", (0, 0), (-1, -1), 8),
    ]))
    elements.append(total_table)
    elements.append(Spacer(1, 6))
    elements.append(Paragraph(
        f"Validité de l'offre : {devis_row['validite_jours']} jours "
        f"(jusqu'au {devis_row['date_limite'][:10] if devis_row['date_limite'] else '—'})",
        ParagraphStyle("Validite", fontSize=9, textColor=GREY)))

    _footer_note(elements, "Ce devis est valable pour la durée indiquée ci-dessus. "
                            "Pour toute question, contactez-nous aux coordonnées en en-tête.")
    doc.build(elements)
    return output_path


def generate_facture_pdf(output_path, facture_row, client_row, lignes):
    doc = SimpleDocTemplate(output_path, pagesize=A4,
                             topMargin=15 * mm, bottomMargin=15 * mm,
                             leftMargin=18 * mm, rightMargin=18 * mm)
    elements = []
    date_str = facture_row["date_facture"][:10] if facture_row["date_facture"] else ""
    _header(elements, "FACTURE", facture_row["numero"], date_str)
    _client_block(elements, "DOIT À :", client_row["nom"] if client_row else "—",
                  client_row["telephone"] if client_row else "—",
                  "Adresse / Chantier :", client_row["adresse"] if client_row else "—",
                  client_nif=client_row["nif"] if client_row else None)
    if facture_row["description"]:
        elements.append(Paragraph(f"<b>Objet :</b> {_esc(facture_row['description'])}",
                                   ParagraphStyle("Objet", fontSize=9.5, spaceAfter=10)))
    _lines_table(elements, lignes, with_unit_price=True)

    def money(v):
        return f"{v:,.0f}".replace(",", " ")

    rows = [["Montant HT", money(facture_row["montant_ht"])]]
    if facture_row["reduction_pct"]:
        rows.append([f"Réduction ({facture_row['reduction_pct']:.0f}%)",
                     f"-{money(facture_row['montant_ht'] - facture_row['montant_ht_net'])}"])
    if facture_row["tva"]:
        rows.append(["TVA (18%)", money(facture_row["tva"])])
    else:
        rows.append(["TVA", "Non applicable"])
    rows.append(["Montant TTC", money(facture_row["montant_ttc"])])
    rows.append(["Avance reçue", money(facture_row["avance_recue"])])
    rows.append(["Reste à payer", money(facture_row["reste_a_payer"])])

    totals_table = Table(rows, colWidths=[135 * mm, 30 * mm])
    ts = [
        ("FONTNAME", (0, 0), (-1, -1), "Helvetica"),
        ("FONTSIZE", (0, 0), (-1, -1), 10),
        ("ALIGN", (1, 0), (1, -1), "RIGHT"),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("LINEABOVE", (0, 0), (-1, 0), 1, GOLD),
        ("FONTNAME", (0, -3), (-1, -3), "Helvetica-Bold"),
        ("FONTSIZE", (0, -3), (-1, -3), 12),
        ("LINEABOVE", (0, -3), (-1, -3), 0.8, colors.HexColor("#CCCCCC")),
        ("TEXTCOLOR", (0, -1), (-1, -1),
         colors.HexColor("#E5484D") if facture_row["reste_a_payer"] > 0 else colors.HexColor("#3DD68C")),
        ("FONTNAME", (0, -1), (-1, -1), "Helvetica-Bold"),
    ]
    totals_table.setStyle(TableStyle(ts))
    elements.append(totals_table)
    elements.append(Spacer(1, 6))
    if facture_row["mode_paiement"]:
        elements.append(Paragraph(f"Mode de paiement : {_esc(facture_row['mode_paiement'])} — "
                                   f"Statut : <b>{_esc(facture_row['statut'])}</b>",
                                   ParagraphStyle("Mode", fontSize=9, textColor=GREY)))

    _footer_note(elements,
                 f"Compte Bancaire : {ENTREPRISE['compte_bancaire']} — "
                 f"Merci de votre confiance.")
    doc.build(elements)
    return output_path


def generate_recu_pdf(output_path, recu_row, client_row):
    doc = SimpleDocTemplate(output_path, pagesize=A4,
                             topMargin=15 * mm, bottomMargin=15 * mm,
                             leftMargin=18 * mm, rightMargin=18 * mm)
    elements = []
    date_str = recu_row["date_recu"][:10] if recu_row["date_recu"] else ""
    _header(elements, "REÇU", recu_row["numero"], date_str)
    _client_block(elements, "REÇU DE :", client_row["nom"] if client_row else "—",
                  client_row["telephone"] if client_row else "—",
                  "Reçu pour :", recu_row["motif"])
    if recu_row["facture_numero"]:
        elements.append(Paragraph(f"<b>N° Facture liée :</b> {_esc(recu_row['facture_numero'])}",
                                   ParagraphStyle("FactLiee", fontSize=9.5, spaceAfter=10)))

    montant_table = Table([["MONTANT REÇU", f"{recu_row['montant_recu']:,.0f} FCFA".replace(",", " ")]],
                           colWidths=[80 * mm, 85 * mm])
    montant_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#141C2E")),
        ("TEXTCOLOR", (0, 0), (-1, -1), colors.HexColor("#D4AF37")),
        ("FONTNAME", (0, 0), (-1, -1), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 14),
        ("ALIGN", (1, 0), (1, 0), "RIGHT"),
        ("TOPPADDING", (0, 0), (-1, -1), 12),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 12),
        ("LEFTPADDING", (0, 0), (0, 0), 10),
        ("RIGHTPADDING", (1, 0), (1, 0), 10),
    ]))
    elements.append(montant_table)
    elements.append(Spacer(1, 10))

    en_lettres = number_to_french_words(recu_row["montant_recu"])
    elements.append(Paragraph(
        f"Arrêté le présent reçu à la somme de : <b>{en_lettres} FRANCS CFA</b>",
        ParagraphStyle("Lettres", fontSize=9.5, spaceAfter=10)))
    elements.append(Paragraph(f"Mode de paiement : <b>{_esc(recu_row['mode_paiement']) or '—'}</b>",
                               ParagraphStyle("Mode", fontSize=9.5, spaceAfter=4)))
    if recu_row["recu_par"]:
        elements.append(Paragraph(f"Reçu par : {_esc(recu_row['recu_par'])}",
                                   ParagraphStyle("RecuPar", fontSize=9.5)))

    _footer_note(elements, "Ce reçu confirme la bonne réception du paiement indiqué ci-dessus. "
                            "Pour toute question, contactez-nous aux numéros indiqués en en-tête.")
    doc.build(elements)
    return output_path


def generate_note_pdf(output_path, note_row, client_row):
    doc = SimpleDocTemplate(output_path, pagesize=A4,
                             topMargin=15 * mm, bottomMargin=15 * mm,
                             leftMargin=18 * mm, rightMargin=18 * mm)
    elements = []
    date_str = note_row["date_note"][:10] if note_row["date_note"] else ""
    _header(elements, "NOTE", note_row["numero"] or "—", date_str)
    _client_block(elements, "DESTINATAIRE :", client_row["nom"] if client_row else "—",
                  client_row["telephone"] if client_row else "—")
    if note_row["objet"]:
        elements.append(Paragraph(f"<b>Objet :</b> {_esc(note_row['objet'])}",
                                   ParagraphStyle("Objet", fontSize=9.5, spaceAfter=10)))
    elements.append(Paragraph("<b>NOTE :</b>", ParagraphStyle(
        "Section", fontName="Helvetica-Bold", fontSize=10, textColor=GOLD, spaceAfter=6)))
    elements.append(Paragraph(_esc(note_row["contenu"]), ParagraphStyle(
        "Contenu", fontSize=10, leading=15)))

    if note_row["redige_par"]:
        _footer_note(elements, f"Rédigé par : {_esc(note_row['redige_par'])}")
    doc.build(elements)
    return output_path
