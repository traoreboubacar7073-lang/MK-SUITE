"""Company financial/contact details are local configuration, never source data."""
import json
import os
from pathlib import Path

FIELDS = ('nom', 'activite', 'adresse', 'telephones', 'email',
          'immatriculation', 'num_fiscal', 'compte_bancaire')

def profile_path():
    return Path.home() / 'MK_Suite_Data' / 'profil_entreprise.json'

def load_profile():
    result = dict.fromkeys(FIELDS, '')
    result['nom'] = 'MK ENTREPRISE'
    try:
        data = json.loads(profile_path().read_text(encoding='utf-8'))
        if isinstance(data, dict):
            result.update({k: v for k, v in data.items() if k in FIELDS and isinstance(v, str)})
    except (OSError, ValueError):
        pass
    return result

def import_profile(source):
    data = json.loads(Path(source).read_text(encoding='utf-8'))
    if not isinstance(data, dict) or any(not isinstance(v, str) for v in data.values()):
        raise ValueError('Profil invalide : les champs doivent contenir du texte.')
    if not data.get('nom'):
        raise ValueError('Le nom de l’entreprise est obligatoire.')
    clean = {k: data.get(k, '') for k in FIELDS}
    path = profile_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(clean, ensure_ascii=False, indent=2), encoding='utf-8')
    os.replace(temporary, path)
    return clean
