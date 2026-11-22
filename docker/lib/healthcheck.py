"""Sonde de santé : le client web Lucterios répond-il via Django ?"""
import sys
import urllib.request

# Agent et adresse propres à la sonde : diacamma_gunicorn.py retire ses
# réponses réussies du journal d'accès.
AGENT_SONDE = 'diacamma-healthcheck'
CHEMIN_SONDE = '/web/index.html'

try:
    requete = urllib.request.Request('http://127.0.0.1:8000' + CHEMIN_SONDE,
                                     headers={'User-Agent': AGENT_SONDE})
    with urllib.request.urlopen(requete, timeout=8) as response:
        sys.exit(0 if response.status == 200 else 1)
except Exception:
    sys.exit(1)
