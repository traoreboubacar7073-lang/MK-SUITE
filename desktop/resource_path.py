"""
MK Suite - Résolution des chemins de ressources
Fonctionne à la fois en mode script normal (python main.py) et une fois
empaqueté en .exe avec PyInstaller (les fichiers sont alors extraits dans
un dossier temporaire pointé par sys._MEIPASS).
"""
import sys
import os


def get_base_path():
    if hasattr(sys, "_MEIPASS"):
        return sys._MEIPASS
    return os.path.dirname(os.path.abspath(__file__))


def resource_path(*parts):
    target = os.path.join(get_base_path(), *parts)
    if not os.path.exists(target) and parts == ("assets", "logo.png"):
        return os.path.join(os.path.dirname(get_base_path()), "assets", "images", "logo.png")
    return target
