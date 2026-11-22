"""Journal d'accès de gunicorn, sans les requêtes de la sonde de santé.

La sonde (healthcheck.py) interroge l'application toutes les 30 secondes :
sans ce filtre, elle remplit l'onglet Journal de Container Manager. On ne
retire que ses réponses réussies, venues de l'intérieur du conteneur, sur sa
seule adresse ; un échec de la sonde reste dans le journal, comme une requête
venue de l'extérieur avec le même agent.

Ce module ne doit importer ni Django ni l'application : gunicorn le charge
dans son processus maître, avant de lancer le worker.
"""
from gunicorn.glogging import Logger

# Identiques à ceux de healthcheck.py.
AGENT_SONDE = 'diacamma-healthcheck'
CHEMIN_SONDE = '/web/index.html'


class JournalSansSonde(Logger):
    def access(self, resp, req, environ, request_time):
        if (environ.get('HTTP_USER_AGENT') == AGENT_SONDE
                and environ.get('PATH_INFO') == CHEMIN_SONDE
                and environ.get('REMOTE_ADDR') == '127.0.0.1'
                and getattr(resp, 'status_code', None) == 200):
            return
        super().access(resp, req, environ, request_time)
