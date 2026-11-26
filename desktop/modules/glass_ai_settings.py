"""Local configuration dialog; never copies the provider API key to the phone."""
import customtkinter as ctk
from tkinter import messagebox
from modules.glass_ai_service import load_config, save_config, DEFAULT_MODEL, GlassAIError
from modules.sync_service import local_address, SYNC_PORT
from ui.theme import font, primary_button, secondary_button


def open_scanner_settings(parent):
    dialog = ctk.CTkToplevel(parent)
    dialog.title('Scanner IA — dimensions manuscrites')
    dialog.geometry('660x590')
    dialog.transient(parent.winfo_toplevel())
    config = load_config()
    ctk.CTkLabel(dialog, text='Lecture IA des feuilles de vitres', font=font(17, 'bold')).pack(pady=16)
    ctk.CTkLabel(dialog, text='La zone de photo sera envoyée à OpenAI uniquement à votre demande.\n'
        'Internet et un compte API actif sont nécessaires ; des frais peuvent s’appliquer.\n'
        'La clé est protégée par votre compte Windows et reste sur cet ordinateur.',
        wraplength=610, justify='left').pack(padx=20, pady=8)
    ctk.CTkLabel(dialog, text='Clé API OpenAI (ne pas envoyer dans une conversation)').pack(anchor='w', padx=20)
    key_entry = ctk.CTkEntry(dialog, show='*', width=600, placeholder_text='Déjà enregistrée : laisser vide pour la conserver' if config.get('api_key') else 'Saisir votre clé API')
    key_entry.pack(padx=20, pady=(4, 12))
    ctk.CTkLabel(dialog, text='Modèle de vision').pack(anchor='w', padx=20)
    model_entry = ctk.CTkEntry(dialog, width=600)
    model_entry.insert(0, config.get('model', DEFAULT_MODEL))
    model_entry.pack(padx=20, pady=(4, 12))
    ip = local_address() or 'ADRESSE_WIFI_DU_PC'
    ctk.CTkLabel(dialog, text=f'Adresse à saisir sur le téléphone : {ip}:{SYNC_PORT}', font=font(12, 'bold')).pack(pady=8)
    ctk.CTkLabel(dialog, text='Code de connexion à copier sur le téléphone (différent de la clé API)').pack(padx=20)
    token_entry = ctk.CTkEntry(dialog, width=600)
    token_entry.insert(0, config.get('token', 'Enregistrez la configuration pour obtenir le code'))
    token_entry.configure(state='readonly')
    token_entry.pack(padx=20, pady=6)
    status = ctk.CTkLabel(dialog, text='', wraplength=600)
    status.pack(pady=8)

    def save():
        try:
            # Keep the previous key if the field was intentionally left empty.
            current = load_config()
            result = save_config(key_entry.get() or current.get('api_key', ''), model_entry.get())
            key_entry.delete(0, 'end')
            token_entry.configure(state='normal')
            token_entry.delete(0, 'end')
            token_entry.insert(0, result['token'])
            token_entry.configure(state='readonly')
            status.configure(text='Configuration enregistrée. La première lecture vérifiera l’accès au modèle.\n'
                             'Fermez cette fenêtre puis cliquez sur « Démarrer le serveur ».')
        except GlassAIError as exc:
            messagebox.showerror('Scanner IA', str(exc), parent=dialog)

    def copy_code():
        token = load_config().get('token')
        if token:
            dialog.clipboard_clear()
            dialog.clipboard_append(token)
            status.configure(text='Code de connexion copié. Il donne accès au scanner : gardez-le privé.')

    primary_button(dialog, 'Enregistrer la configuration', command=save).pack(pady=6)
    secondary_button(dialog, 'Copier le code de connexion', command=copy_code).pack(pady=6)
    secondary_button(dialog, 'Fermer', command=dialog.destroy).pack(pady=6)
