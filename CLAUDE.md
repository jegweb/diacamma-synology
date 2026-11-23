# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Objectif du projet

Image Docker et projets Compose pour déployer **Diacamma Syndic** (gestion de copropriété) et **Diacamma Asso** (gestion d'association), deux applications du framework Python/Django **Lucterios**, dans **Synology Container Manager** (DSM 7.2+, NAS amd64 ou arm64). Une seule image contient les deux ; chaque kit fixe l'application avec `DIACAMMA_APPLI`. Priorités : déploiement simple, sécurisé, sans perte de fonctionnalités de l'application. `README.md` est le guide utilisateur (en français) : le tenir à jour à chaque changement de comportement. `HORS-SYNOLOGY.md` donne les consignes pour les autres hôtes Docker (`docker compose`, proxy inverse, `PUID`/`PGID`) : le tenir à jour lui aussi.

L'utilisateur travaille en français : réponses, commentaires, messages du conteneur et documentation en français.

## Commandes

```sh
docker build -t diacamma:local .                            # construire l'image (arch locale)
docker build --platform linux/amd64 -t diacamma:amd64-test .   # vérifier l'autre architecture
scripts/smoke-test.sh diacamma:local                        # test de fumée Syndic, PostgreSQL (--sqlite pour l'autre variante)
scripts/smoke-test.sh --asso diacamma:local                 # même test avec le kit Asso
scripts/smoke-test.sh --depuis ghcr.io/jegweb/diacamma:latest diacamma:local   # test de mise à jour
scripts/kit.sh asso <dossier> [image:tag]                   # fichiers du kit Asso (dérivés de ceux de Syndic)
scripts/update-lock.sh                                      # régénérer requirements.lock depuis requirements.in
scripts/build-image.sh amd64                                # image exportée en dist/*.tar pour import dans Container Manager
docker run --rm -v "$PWD:/mnt:ro" koalaman/shellcheck:stable docker/bin/diacamma scripts/*.sh   # lint shell
```

Il n'y a pas de suite de tests unitaires. `scripts/smoke-test.sh [--asso] [--sqlite] [--depuis <image>] <image>` lance le projet dans un dossier jetable, en dehors du dépôt pour ne pas y créer `data/` et `backups/`. Il prend les fichiers produits par `scripts/kit.sh`, remplace la ligne `image:` du compose par l'image locale indiquée, puis vérifie :

- la connexion avec le mot de passe fourni, et le refus de `admin`/`admin` ;
- `/static/settings.py` et `/static/db.sqlite3` en 404, un hôte inconnu en 400 ;
- le journal d'accès : les requêtes y figurent, la sonde de santé non ;
- `backup`, puis `restore` suivi d'un redémarrage ;
- les réseaux : `diacamma-<appli>` en `bridge`, `-db` et `-sauvegarde` en `none`, aucun réseau créé par le projet ; la sauvegarde manuelle est lancée dans `-sauvegarde` ;
- en PostgreSQL, le mot de passe généré dans `secrets/` et `"HOST": "/var/run/postgresql"` dans `settings.py` ; avec `--sqlite`, le refus du compose PostgreSQL sur une instance SQLite, puis celui du kit de l'autre application, base intacte.

La CI (`.github/workflows/ci.yml`) le lance sur chaque push et chaque pull request, et chaque mois sans cache, en six variantes (dont `asso` et `mise-a-jour-asso`). Pour un essai manuel, la connexion se teste ainsi :

```sh
curl -s -H 'Host: syndic.example.test' -X POST --data 'login=admin&password=MotDePasseDeTest-2026' \
  http://127.0.0.1:8100/CORE/authentification    # "data": "OK" si la connexion réussit, "BADAUTH" sinon (Asso : asso.example.test, port 8101)
```

Container Manager embarque un Docker plus ancien que celui du Mac (Docker 24, Compose 2.19 ou 2.20). Pour tester un changement du compose ou du Dockerfile dans ces conditions, utiliser un moteur isolé, avec dans `$T` un compose et un `.env` :

```sh
docker run -d --privileged --name dind24 -e DOCKER_TLS_CERTDIR= -v "$T:/project" docker:24.0.2-dind
docker exec -w /project dind24 docker compose pull     # ne doit pas échouer : l'image doit exister sur ghcr.io
docker exec -w /project dind24 docker compose up -d
```

### Publication

L'image est publiée sur `ghcr.io/jegweb/diacamma` (dépôt `jegweb/diacamma-synology`). L'ancien nom `ghcr.io/jegweb/diacamma-syndic` (jusqu'à 2.7.10-3, puis alias pour 2.7.10-4) **n'est plus alimenté** : il garde ses versions, `latest` = 2.7.10-4. Ne pas le supprimer : les kits d'avant 2.7.10-4 le téléchargent à chaque « Créer », et le retour en arrière vers 2.7.10-3 en dépend. Versions `X.Y.Z-N` : version de Diacamma (Syndic et Asso sortent ensemble, même `X.Y.Z`), puis révision de l'empaquetage. La procédure complète est dans `CONTRIBUTING.md`.

- Le tag d'image est écrit en dur dans **les deux** compose (ceux de Syndic ; le kit Asso en est dérivé).
- **Plafonds prudents** (`requirements.in`) : une dépendance indirecte que l'amont ne limite pas, et dont une version majeure est sortie après la version amont de Diacamma, est plafonnée sous cette majeure. Les règles complètes sont dans CONTRIBUTING, étape 1. Le Dockerfile lance `pip check` : seule l'absence de PyQt6 est tolérée.
- Test de mise à jour : `smoke-test.sh [--sqlite] --depuis <image publiée>`. L'ancienne image tourne d'abord avec **le kit de sa version** : version lue dans le libellé `org.opencontainers.image.version`, fichiers extraits de l'étiquette Git `v<version>` (son `scripts/kit.sh` s'il existe). D'où `fetch-depth: 0` dans les workflows. La CI (variantes `mise-a-jour`, `mise-a-jour-sqlite` et `mise-a-jour-asso`) et la publication le lancent depuis `diacamma:latest`, qui contient Syndic et Asso depuis 2.7.10-4.
- `scan.yml` : analyse Trivy hebdomadaire de `:latest`, avec une version de Trivy épinglée à la main. Seuil : HIGH/CRITICAL, failles corrigées seulement. La réponse attendue à un échec est une révision `-N+1` (procédure dans CONTRIBUTING). Seule exception : une faille sans effet sur l'image (composant absent ou jamais exécuté), écartée dans `.trivyignore.yaml` avec justification et `expired_at`. Exemple : krb5 en novembre 2026, failles du KDC et de kadmind, alors que l'image n'a que les bibliothèques clientes (tirées par libcurl-gnutls, via poppler).
- Une étiquette Git `vX.Y.Z-N` (ou `-rcM`) lance `.github/workflows/release.yml`. Il vérifie la cohérence (étiquette, compose, `diacamma-syndic` et `diacamma-asso` à `X.Y.Z` dans `requirements.lock`, entrée `## [X.Y.Z-N]` du CHANGELOG), puis construit et teste sur des runners natifs amd64 et arm64.
- Il pousse l'image testée sous `X.Y.Z-N-<arch>`, assemble le manifeste multi-architecture (`X.Y.Z-N`, puis `X.Y.Z` et `latest` hors pré-version), et crée la Release avec deux kits `.zip` produits par `scripts/kit.sh` (`diacamma-syndic-…` et `diacamma-asso-…`, chacun avec deux compose et `.env.example`).
- Un nouveau paquet GHCR créé par le workflow prend la visibilité du dépôt (public : constaté pour `diacamma` à la rc1 de 2.7.10-4). Le vérifier après le premier envoi d'un nouveau nom.
- Images sans attestation (`provenance`/`sbom` désactivés), pour le Docker 24 de Container Manager.
- Une version définitive est annoncée par une discussion dans la catégorie `ANNONCES` (« Annonces »), seulement si cette catégorie existe. Le formulaire `.github/DISCUSSION_TEMPLATE/questions-et-aide.yml` doit porter le nom (slug) de la catégorie « Questions et aide ».
- `ARG VERSION` donne `DIACAMMA_IMAGE_VERSION`, affiché par `diacamma version`. Elle n'entre pas dans les identifiants de build (`/opt/diacamma/build-id/<appli>`) : une révision sans changement de paquets ne déclenche pas de migration.

## Architecture

- `Dockerfile` : construction en deux étapes sur `python:3.13-slim-trixie`. Elle écrit un identifiant de build par application, `/opt/diacamma/build-id/{syndic,asso}` (versions de `diacamma-<appli>`, `diacamma-financial`, `lucterios`, `lucterios-contacts`, `lucterios-documents`). Celui de Syndic garde le format de l'ancien `diacamma-build-id` : ne pas changer cette liste, sinon chaque installation existante verrait une fausse mise à jour. Trixie est obligatoire : les roues aarch64 exigent glibc ≥ 2.39. Le verrou est installé avec `pip install --no-deps -r requirements.lock`. **PyQt6 est volontairement exclu** du verrou : c'est une dépendance déclarée de `lucterios`, mais elle ne sert qu'à l'interface de bureau. Exécution sous l'UID:GID 1026:100, avec `tini` comme PID 1. L'étape finale lance `apt-get upgrade` et **retire pip**, du venv comme du Python système. pip ne sert qu'à `lucterios_admin check/update`, et ses bibliothèques embarquées étaient signalées par Trivy. L'interface n'appelle `lucterios_admin` que pour `archive` et `restore`.
- `docker/bin/diacamma` : point d'entrée et outil d'administration (`serve`, `backup`, `backup-daemon`, `restore`, `reset-admin-password`, `version`, `manage`, `admin`). Il pilote `python -m lucterios.install.lucterios_admin … -i /data`. `DIACAMMA_APPLI` (`syndic` par défaut, pour les compose d'avant 2.7.10-4, ou `asso`) fixe le paquet de l'application, ses modules, le nom de l'instance (`DIACAMMA_INSTANCE`, par défaut celui de l'application) et l'identifiant de build. `check_appli` refuse de démarrer, avant tout contact avec la base, si `settings.py` désigne une autre application (`fill_appli_settings("diacamma.…")`) ou si `/data` contient un autre `manage_*.py`. Sinon un kit Asso posé sur des données Syndic en PostgreSQL créerait son instance dans la base de Syndic.
- `docker/lib/diacamma_docker.py` : fonctions Python appelées par le script (`extra-settings`, `secure-admin`, `clean-static`, `snapshot-sqlite`). `diacamma_wsgi.py` enveloppe l'application Lucterios avec WhiteNoise. `healthcheck.py` est la sonde de santé (toutes les 30 s), avec l'agent `diacamma-healthcheck`. `diacamma_gunicorn.py` (`--logger-class`) retire du journal d'accès ses réponses 200, depuis `127.0.0.1`, sur `/web/index.html` ; agent et chemin sont écrits dans les deux fichiers. Ce module est chargé par le processus maître de gunicorn : il ne doit importer ni Django ni l'application (ce serait un `--preload`).
- `docker-compose.yml` (PostgreSQL, recommandé depuis 2.7.10-3) et `docker-compose.sqlite.yml` : ceux de Syndic, avec `DIACAMMA_APPLI: syndic` en valeur fixe. Deux services avec la même image, téléchargée depuis ghcr.io, plus `db` (`postgres:17`) pour PostgreSQL. **Réseaux** : `diacamma` en `network_mode: bridge` (réseau par défaut de Docker, pour le port publié et les courriels), `db` et `sauvegarde` en `network_mode: none`. Le projet ne crée aucun réseau. La base est jointe par son socket Unix, dans le volume `db-socket` (tmpfs, `mode=1777`), monté en `/var/run/postgresql` (en lecture seule côté Diacamma) ; `DIACAMMA_DB_HOST=/var/run/postgresql`. Par le socket, l'image `postgres` accepte la connexion sans mot de passe (`trust` de son `initdb`) : l'isolement repose sur ce volume, propre au projet.
- `scripts/kit.sh <syndic|asso> <dossier> [image:tag]` : fichiers d'un kit. Ceux d'Asso ne sont pas versionnés : ils sont dérivés par substitutions (`diacamma-asso`, `DIACAMMA_APPLI: asso`, `data/asso/`, `asso.mondomaine.fr`, port **8101** pour cohabiter avec Syndic sur un même NAS). Le script échoue s'il reste `syndic`, `Diacamma Syndic` ou `8100` dans le kit Asso : un texte propre à Syndic ajouté au compose doit avoir sa substitution (« Syndic ou Asso » avec une majuscule est permis). `diacamma` sert l'application ; `sauvegarde` lance `backup-daemon`. Jusqu'à 2.7.10-2, `docker-compose.yml` était la variante SQLite : les installations sans dossier `postgresql/` sont en SQLite. Le refus de démarrer sur un moteur différent (`update_instance`) protège celles qui prennent le mauvais fichier. Durcissement : `read_only`, `cap_drop: ALL`, `no-new-privileges`, port publié sur `127.0.0.1`. Toute la configuration passe par `.env` (voir `.env.example`).

### Contraintes propres à Synology (constatées sur un NAS Synology, noyau 4.4)

- **Pas de section `logging`** dans le compose. Container Manager n'affiche que les journaux écrits par le pilote par défaut de Synology (un `log.db` par conteneur). Avec `json-file`, l'onglet Journal reste vide.
- **Port publié en valeur fixe** (`"127.0.0.1:8100:8000"`), sans variable. L'assistant « portail Web via Web Station » de Container Manager lit le compose lui-même et ne propose aucun service si la ligne `ports` contient `${…}`. Web Station accepte en revanche un port publié sur `127.0.0.1`.
- **Pas de `pids_limit`** : le noyau ne gère pas cette limite (avertissement « PIDs limit discarded »).
- **Jamais de liaison réseau entre conteneurs, ni de réseau créé par projet.** Le pare-feu de DSM, s'il est activé, bloque le trafic des plages Docker qu'il n'autorise pas. Sur un NAS qui a déjà beaucoup de réseaux, Docker passe des `172.x` aux `192.168.x` : avec la rc1 de 2.7.10-4, la base est devenue injoignable (« db:5432 … timeout expired »). On ne peut pas exiger des utilisateurs qu'ils modifient leur pare-feu. De plus, une fois, dans `docker:24.0.2-dind` (Compose 2.19.1), un conteneur déclaré sur deux réseaux n'a été branché que sur un seul (jamais vu sur un NAS, cause inconnue). D'où le socket et le réseau `bridge` (voir plus haut). Sur `bridge`, pas de DNS interne de Docker : le conteneur reçoit le `resolv.conf` du NAS, remplacé par des DNS publics s'il ne contient que `127.0.0.1`.
- **Retour en arrière** : une version d'avant 2.7.10-4 ne sait pas joindre le socket. Après la mise à jour, `settings.py` contient `"HOST": "/var/run/postgresql"`, et l'ancienne image redémarre en boucle (testé). Le README donne la commande `sed` qui rétablit `"HOST": "db"`. Une révision qui change encore l'adresse de la base doit prévoir ce cas.
- **Vocabulaire de l'interface française** : l'action « Build » d'un projet s'appelle **« Créer »**. Pour qu'un changement du compose ou de `.env` soit pris en compte, la documentation demande **Arrêter → Nettoyer → Créer**. « Démarrer » relance les conteneurs existants sans relire le compose. « Nettoyer » supprime les conteneurs, mais ni les images ni les dossiers de données. Au passage à 2.7.10-4, Container Manager a aussi supprimé de lui-même les réseaux que le compose ne déclarait plus, ce que ne fait pas `docker compose down`.
- **Container Manager lance `docker compose pull` avant `up`.** L'image du compose doit donc exister sur ghcr.io, dans un paquet public. Pour une image importée ou construite sur le NAS, l'utilisateur décommente `pull_policy: never` dans l'ancre `x-diacamma` ; sinon le pull échoue ou remplace l'image. Ne pas remettre de section `build:` : le kit ne contient pas le Dockerfile.
- **Dépendances en `service_started`, jamais `service_healthy`** : `sauvegarde` envers `diacamma`, `diacamma` envers `db`. Container Manager affiche tout échec de `compose up` comme « Build project failed », sans garder de conteneur dont on puisse lire le journal. Les erreurs de démarrage doivent laisser le conteneur visible, en redémarrage, avec un message `[diacamma] ERREUR` explicite. Diacamma attend donc PostgreSQL lui-même (`wait-postgresql`, 300 s au plus), après la vérification du moteur.
- **File Station ne crée pas de fichier texte.** Le mot de passe PostgreSQL est généré par l'`entrypoint` de `db` dans `secrets/db_password.txt` (dossier monté en lecture seule dans Diacamma), seulement si la base n'existe pas encore. Les `$` du script sont doublés (`$$`) dans le compose.

### Séquence `serve`

1. Valider la configuration.
2. Créer l'instance (`lucterios_admin add`) ou la mettre à jour (`lucterios_admin modif`, qui réécrit `settings.py` puis applique les migrations). En PostgreSQL, si `settings.py` ne contient pas `"HOST": "$DIACAMMA_DB_HOST",` (installations d'avant 2.7.10-4, en `host=db`), `modif` reçoit aussi `-d` pour réécrire la base. Avant les deux, `wait-postgresql` attend la base. Par le socket, elle se connecte d'abord à la base `postgres` : un `listen_addresses` vide désigne le serveur temporaire de la première initialisation de l'image `postgres`, qu'il faut ignorer.
3. Remplacer le mot de passe `admin`/`admin` s'il est encore actif.
4. Lancer `collectstatic`, seulement si la version a changé.
5. Nettoyer `static/`.
6. Écrire le marqueur `/data/.diacamma-build-id`.
7. Lancer gunicorn.

Une mise à jour est détectée quand ce marqueur **existe** et diffère de `/opt/diacamma/diacamma-build-id`, généré à la construction à partir des versions des paquets. Le conteneur prend alors un instantané SQLite dans `backups/avant-mise-a-jour/`. Sans marqueur (démarrages précédents ratés, données importées), il n'y a pas d'instantané. L'instantané ouvre la base en lecture-écriture : un démarrage interrompu en pleine migration laisse un journal SQLite « chaud », qu'une ouverture `mode=ro` ne peut pas annuler (« attempt to write a readonly database »). Le service de sauvegarde attend que le marqueur corresponde à l'image avant d'archiver.

### Particularités de Lucterios qui guident la conception

- **Mot de passe de la base dans les sorties** : `lucterios_admin` (`add`, `modif`, `restore`…) affiche la chaîne de connexion, mot de passe compris. La fonction `lucterios_admin()` du script le masque (`sed -u`). Le `last_backup.log` des archives lancées depuis l'interface, écrit par Lucterios lui-même, le contient encore.
- **Restauration depuis l'interface** : programmée 10 s plus tard dans le planificateur, elle dure parfois plusieurs minutes. Un redémarrage pendant ce temps laisse une base vide (le `loaddata` est annulé). La documentation de migration passe donc par `diacamma restore`, qui attend la fin.
- **Réglages** : `lucterios_admin -e '<json>'` écrit chaque clé dans `settings.py` sous la forme `CLE = valeur`. Les chaînes de premier niveau sont écrites entre guillemets **sans échappement**, d'où la validation dans `extra_settings()`. `modif` conserve `SECRET_KEY` et la base, et fusionne les nouvelles clés avec les anciennes.
- **`DEBUG` vaut `True` par défaut** dans Lucterios. On le force à `False`. Django ne sert alors plus `/static/` (WhiteNoise prend le relais), tandis que `/web/` reste servi par une vue Lucterios.
- **Fuite de fichiers par `collectstatic`** : `STATICFILES_DIRS` contient le répertoire de l'instance. `collectstatic` y copierait `settings.py`, `db.sqlite3` et `usr/` (les documents). Pour l'éviter, on passe des options `-i` et on lance `clean-static` à chaque démarrage. Ne pas retirer ces protections.
- **Planificateur dans le processus web** : APScheduler s'exécute dans le processus gunicorn et gère l'envoi des courriels par lots, les archives lancées depuis l'interface et les rapports de clôture. Il faut donc **un seul worker** (`--workers 1`, les threads sont permis), sans `--preload` ni `--max-requests`. Les archives de l'interface relancent `sys.executable -m lucterios.install.lucterios_admin` et lisent `DJANGO_SETTINGS_MODULE` dans l'environnement.
- **Adresse du site** : les liens des courriels (documents partagés, paiement, statistiques d'ouverture) partent de `LUCTERIOS_ROOT_URL`. Vide, Lucterios la déduit du `Referer` de la première requête qui en a besoin et la garde en mémoire jusqu'au redémarrage. Les envois par lots repris au démarrage partent alors avec des liens incomplets. `extra_settings()` la fixe donc à `https://<premier nom non IP de DIACAMMA_ALLOWED_HOSTS>`, et la laisse vide en HTTP, où le port compte. La clé est toujours écrite, même vide, car `modif` conserve les anciennes clés.
- **Langue** : `set_locale_lang('fr')` repasse silencieusement en anglais si la locale `fr_FR.UTF-8` n'est pas générée dans l'image.
- **Compte par défaut** : la migration CORE 0001 crée `admin`/`admin`. `secure-admin` le remplace à chaque démarrage et après chaque restauration.
- **Données** : toutes les données de l'instance sont dans `/data/<instance>/` (`settings.py`, `db.sqlite3`, `usr/` pour les documents, `static/`, `tmp/`, `django_cache/`). `BACKUP_DIRECTORY=/backups` active la gestion des archives `.lbk` dans l'interface.
- **Modules requis** : `lucterios-standard` doit être installé, car `lucterios_admin` l'importe dans `setup_from_none`. Modules de l'instance, repris du paquet YunoHost et identiques à `diacamma.<appli>.link()` :
  - Syndic (`diacamma.syndic`) : `lucterios.contacts,lucterios.documents,lucterios.mailing,diacamma.accounting,diacamma.payoff,diacamma.condominium` ;
  - Asso (`diacamma.asso`) : `lucterios.contacts,lucterios.documents,lucterios.mailing,diacamma.accounting,diacamma.payoff,diacamma.invoice,diacamma.member,diacamma.event`.
- **Deux applications** : `diacamma-asso` n'apporte que `diacamma.asso`, `diacamma.member` et `diacamma.event` (`diacamma.invoice` est dans `diacamma-financial`). Les deux paquets sortent le même jour avec le même `X.Y.Z` et les mêmes dépendances. Une instance a une seule application ; une archive `.lbk` se restaure dans la même application.

### Référence amont

Le paquet YunoHost (`https://git.yunohost.org/YunoHost-Apps/diacamma_ynh`), maintenu par l'auteur de Diacamma, sert de référence pour les conventions de déploiement. Il installe `diacamma-asso` et `diacamma-syndic` dans le même venv et choisit l'application à l'installation (`lct_appli`), comme `DIACAMMA_APPLI` ici. Il utilise gunicorn avec 1 worker, `--timeout 600`, un `collectstatic` suivi d'un nettoyage, et `lucterios_admin check/update/refreshall` pour les mises à jour. Les sources des paquets sont publiées sur PyPI sous forme de roues.
