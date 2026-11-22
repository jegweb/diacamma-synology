# Journal des modifications

Les versions s'écrivent `X.Y.Z-N` : `X.Y.Z` est la version de Diacamma incluse (Diacamma Syndic et, depuis 2.7.10-4, Diacamma Asso, qui sortent ensemble), `N` la révision de l'empaquetage. Une révision peut corriger le conteneur ou simplement reconstruire l'image avec les correctifs de sécurité de Debian et de Python.

Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).

## [Non publié]

### Modifié

- La sonde de santé n'apparaît plus dans le journal du conteneur. Toutes les 30 secondes, une ligne `"GET /web/index.html HTTP/1.1" 200 … "Python-urllib/3.13"` remplissait l'onglet Journal de Container Manager. Les autres requêtes y restent, comme les échecs de la sonde.

## [2.7.10-5] - 2026-11-21

Révision de l'empaquetage. Les versions de Diacamma Syndic, Diacamma Asso et Lucterios sont les mêmes que dans 2.7.10-4 : la mise à jour ne lance aucune migration. L'image est reconstruite avec les derniers correctifs de sécurité de Debian et de Python.

### Ajouté

- `HORS-SYNOLOGY.md` : installation sur un autre hôte Docker (serveur Linux, VPS, autre NAS), avec `docker compose`, un proxy inverse Caddy ou nginx et ses propres `PUID`/`PGID`. Le README y renvoie.

### Modifié

- L'ancien nom de l'image, `ghcr.io/jegweb/diacamma-syndic`, ne reçoit plus les nouvelles versions : il garde celles publiées jusqu'à 2.7.10-4, pour les anciens kits et le retour en arrière. Un `docker-compose.yml` qui porte encore ce nom ne se met donc pas à jour en changeant seulement le numéro de version (« manifest unknown ») : prenez celui du kit. Les outils qui surveillent ce nom (Watchtower…) ne verront plus de nouvelle version : faites-leur suivre `ghcr.io/jegweb/diacamma`.
- Les messages d'erreur sur les droits des dossiers, ceux de Diacamma comme celui de la base, ne supposent plus un NAS Synology : les consignes propres à DSM et File Station y sont signalées comme telles, et la correction pour SELinux est indiquée.

## [2.7.10-4] - 2026-11-20

Diacamma Asso rejoint le projet. Diacamma Syndic et Lucterios restent en version 2.7.10 : pour les installations existantes, la mise à jour ne lance aucune migration.

**Installations Diacamma Syndic existantes** : la mise à jour se fait comme d'habitude avec le kit `diacamma-syndic`, en prenant bien son `docker-compose.yml` (la base n'a plus de réseau, voir ci-dessous). L'image change de nom ; l'ancienne peut être supprimée ensuite, ainsi que les réseaux `diacamma-syndic_default` et `diacamma-syndic_backend` s'ils figurent encore dans Container Manager → Réseau (il les supprime normalement de lui-même). Pour revenir ensuite à une version antérieure en PostgreSQL, une ligne de `settings.py` est à rétablir (README, « Installations d'avant la version 2.7.10-4 »).

### Ajouté

- **Diacamma Asso 2.7.10** (gestion d'association : adhérents, cotisations, événements, facturation). Il a son propre kit, `diacamma-asso-<version>.zip`, avec les mêmes garanties que Syndic : PostgreSQL ou SQLite, sauvegardes, durcissement. Son port publié est 8101, pour qu'il puisse fonctionner sur le même NAS que Diacamma Syndic (8100). Le README explique les différences dans la section « Syndic ou Asso ? ».
- Un kit posé sur les données de l'autre application (Asso sur Syndic, ou l'inverse) est refusé au démarrage, avec un message explicite et sans toucher aux données.
- Plusieurs copropriétés ou associations sur un même NAS : procédure dans le README (« Plusieurs copropriétés ou associations »).

### Modifié

- L'image s'appelle désormais `ghcr.io/jegweb/diacamma` : elle contient les deux applications, et le kit choisit laquelle utiliser (`DIACAMMA_APPLI`). Les mêmes versions restent publiées sous l'ancien nom, `ghcr.io/jegweb/diacamma-syndic`.
- Le dépôt s'appelle désormais `jegweb/diacamma-synology`. Les anciens liens sont redirigés par GitHub.
- **La base PostgreSQL n'a plus aucun réseau** : Diacamma la joint par son socket, partagé en mémoire entre les conteneurs du projet. Le service de sauvegarde n'a plus de réseau non plus, et Diacamma utilise le réseau « bridge » par défaut de Docker : le projet ne crée plus de réseau. Au premier démarrage, `settings.py` est mis à jour (`Adresse de la base mise à jour dans settings.py`).

### Corrigé

- Diacamma pouvait attendre sa base sans fin (« la base PostgreSQL (db:5432) ne répond pas ») quand le pare-feu de DSM est activé. Chaque projet créait ses propres réseaux Docker, et sur un NAS qui en compte déjà beaucoup, ils pouvaient recevoir une plage d'adresses (`192.168.x`) que le pare-feu bloque. Constaté pendant l'essai de la 2.7.10-4-rc1.

## [2.7.10-3] - 2026-11-20

PostgreSQL devient la base recommandée. Les versions de Diacamma et Lucterios sont les mêmes que dans 2.7.10-2 : la mise à jour ne lance aucune migration.

**Installations SQLite existantes** (projet sans dossier `postgresql`, soit toutes celles faites avec le `docker-compose.yml` des versions précédentes) : pour la mise à jour, prenez `docker-compose.sqlite.yml` et renommez-le en `docker-compose.yml`. Si vous gardez par erreur le `docker-compose.yml` du kit, le conteneur refuse de démarrer sans toucher aux données, et son journal indique le bon fichier. Pour passer à PostgreSQL, suivez la section « Changer de base de données » du README.

### Modifié

- `docker-compose.yml` utilise désormais PostgreSQL. SQLite passe dans `docker-compose.sqlite.yml`, qui convient quand une seule personne saisit à la fois. Avec SQLite, deux enregistrements simultanés, ou un enregistrement pendant une opération longue, peuvent échouer avec « database is locked ». Le README explique le choix, y compris pourquoi MariaDB n'est pas proposé.
- `docker-compose.postgresql.yml` est remplacé par `docker-compose.yml`. Les installations PostgreSQL existantes gardent leur fichier `secrets/db_password.txt`.
- Diacamma n'attend plus l'état « healthy » de la base pour démarrer : il l'attend lui-même, avec des messages explicites. Si la base ne démarre pas, le projet reste créé dans Container Manager et les journaux restent lisibles.

### Ajouté

- Le mot de passe de la base PostgreSQL est créé automatiquement au premier démarrage, dans `secrets/db_password.txt`. Il n'y a plus de fichier à créer à la main.
- Message explicite quand le compose ne correspond pas au moteur de l'instance (SQLite ou PostgreSQL), avec le fichier à prendre.

### Sécurité

- Le mot de passe de la base PostgreSQL n'apparaît plus dans le journal du conteneur, ni dans la sortie des commandes `diacamma`. Lucterios l'affichait à chaque démarrage.

## [2.7.10-2] - 2026-11-19

Révision de sécurité. Les versions de Diacamma et Lucterios sont les mêmes que dans 2.7.10-1 : la mise à jour ne lance aucune migration.

### Sécurité

- Les correctifs de sécurité Debian sont appliqués pendant la construction (`apt-get upgrade`), dont celui de zlib (CVE-2026-85091).
- pip est retiré de l'image. Il ne servait pas à l'exécution et embarquait des versions vulnérables de urllib3 (CVE-2026-97687, CVE-2026-97689), msgpack (CVE-2026-114613, GHSA-6v7p-g79w-8964) et setuptools (CVE-2025-47273). Conséquence : `diacamma admin check` et `diacamma admin update` ne fonctionnent plus, car les mises à jour passent par une nouvelle image.

### Ajouté

- Analyse hebdomadaire des failles de l'image publiée, avec Trivy.
- Modèle de pull request.

## [2.7.10-1] - 2026-11-19

**Faites une sauvegarde avant la mise à jour.** Au premier démarrage, le conteneur détecte la nouvelle version. Il prend alors un instantané de la base SQLite dans `backups/avant-mise-a-jour/`. Cette version ne modifie pas la structure de la base : elle n'apporte aucune nouvelle migration. Suivez l'opération dans le journal.

### Modifié

- Diacamma Syndic 2.7.10 et Lucterios 2.7.10, versions publiées par l'équipe Diacamma le 30 octobre 2026. Les nouveautés fonctionnelles sont présentées sur [diacamma.org](https://www.diacamma.org).
- Dépendances mises à jour. Les nouvelles versions de Lucterios et Diacamma exigent notamment Pillow 13, ReportLab 5, pandas 3 et factur-x 7. Django passe en 5.2.19.

### Ajouté

- Plafonds prudents sur les dépendances indirectes dont une version majeure est sortie après Diacamma 2.7.10, et que l'amont n'a donc pas pu tester : python-dateutil < 4, pypdf < 7, stripe < 17 (paiement en ligne) et gunicorn < 27.
- Contrôle de cohérence des dépendances (`pip check`) pendant la construction de l'image.
- Test de mise à jour depuis la dernière version publiée, lancé par l'intégration continue et à chaque publication : détection de la mise à jour, instantané et migrations.

## [2.7.9-1] - 2026-11-19

Première version publique.

### Ajouté

- Image publiée sur `ghcr.io/jegweb/diacamma-syndic` pour Intel/AMD (amd64) et ARM 64 bits (arm64). Il n'y a plus d'image à construire sur le NAS.
- Kit d'installation joint à chaque Release : `docker-compose.yml`, `docker-compose.postgresql.yml` et `.env.example`.
- Diacamma Syndic 2.7.9 et Lucterios 2.7.9, sur Python 3.13 (Debian 13 « trixie »).
- Projet Compose pour Container Manager, avec une base SQLite (recommandée) ou PostgreSQL.
- Sauvegarde automatique quotidienne en archives `.lbk` et instantané SQLite avant chaque mise à jour.
- Commandes d'administration : `diacamma backup`, `restore`, `reset-admin-password` et `version`.
- Sécurité : le compte `admin`/`admin` est remplacé au démarrage, le mode débogage est désactivé, les noms d'hôte sont contrôlés et les conteneurs tournent sans root, en lecture seule.
- `diacamma version` et le journal de démarrage affichent la version de l'image.
