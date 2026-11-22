# Contribuer

Merci de votre intérêt ! Le projet est en français : tickets, commentaires du code, messages du conteneur et documentation.

- **Une question, un retour d'installation** : les [Discussions](https://github.com/jegweb/diacamma-synology/discussions).
- **Un problème du conteneur ou de la documentation** : un ticket. Joignez le journal et masquez votre domaine et vos mots de passe.
- **Un problème de l'application Diacamma** (comptabilité, appels de fonds, adhésions, impressions…) : le [forum Diacamma](https://forum.diacamma.org) pour une question, les tickets de [Diacamma Syndic](https://github.com/Diacamma2/syndic/issues) ou de [Diacamma Asso](https://github.com/Diacamma2/asso/issues) pour un bogue.
- **Une faille de sécurité** : voir [SECURITY.md](SECURITY.md), jamais en ticket public.

## Avant de modifier

Lisez la partie « Architecture » de [CLAUDE.md](CLAUDE.md). Elle explique les choix qui ne se devinent pas, en particulier :

- les **contraintes de Container Manager** : pas de section `logging`, port publié en valeur fixe, pas de `pids_limit`, `service_started` ;
- les **protections contre les particularités de Lucterios** : `collectstatic` avec ses exclusions et `clean-static`, un seul worker gunicorn, remplacement de `admin`/`admin`.

Ne retirez pas une protection sans comprendre pourquoi elle existe. Si un comportement de l'utilisateur change, mettez à jour le README dans la même modification, ainsi que [HORS-SYNOLOGY.md](HORS-SYNOLOGY.md) (installation sur d'autres hôtes Docker) si une commande, un port ou un réglage y figure.

**Deux applications, une image.** L'image contient Diacamma Syndic et Diacamma Asso ; `DIACAMMA_APPLI`, fixé dans le compose, choisit l'application. Les fichiers du dépôt (`docker-compose.yml`, `docker-compose.sqlite.yml`, `.env.example`) sont ceux de Syndic. Ceux d'Asso n'existent que dans son kit : `scripts/kit.sh asso <dossier>` les produit par substitutions (noms, `DIACAMMA_APPLI`, port 8101), et échoue s'il reste une référence à Syndic. Si vous ajoutez au compose un texte propre à Syndic, complétez les substitutions.

## Tester

Il faut Docker sur un ordinateur (amd64 ou Mac Apple Silicon).

```sh
docker build -t diacamma:local .
scripts/smoke-test.sh diacamma:local                   # Syndic, base PostgreSQL
scripts/smoke-test.sh --sqlite diacamma:local          # Syndic, base SQLite
scripts/smoke-test.sh --asso diacamma:local            # Asso, base PostgreSQL (--asso --sqlite : SQLite)
scripts/smoke-test.sh --depuis ghcr.io/jegweb/diacamma:latest diacamma:local            # mise à jour
scripts/smoke-test.sh --sqlite --depuis ghcr.io/jegweb/diacamma:latest diacamma:local   # mise à jour, SQLite
scripts/smoke-test.sh --asso --depuis ghcr.io/jegweb/diacamma:latest diacamma:local            # mise à jour d'Asso
docker run --rm -v "$PWD:/mnt:ro" koalaman/shellcheck:stable docker/bin/diacamma scripts/*.sh
```

Les mises à jour partent de la dernière version publiée, `ghcr.io/jegweb/diacamma:latest`, qui contient Syndic et Asso depuis 2.7.10-4. L'ancien nom `ghcr.io/jegweb/diacamma-syndic` n'est plus alimenté : il garde ses versions (jusqu'à 2.7.10-4) pour les anciens kits et le retour en arrière. Ne le supprimez pas.

`smoke-test.sh` lance le projet dans un dossier temporaire et vérifie plusieurs points :

- la connexion, et le refus de `admin`/`admin` ;
- `/static/settings.py` et `/static/db.sqlite3` en 404, un hôte inconnu en 400 ;
- le journal d'accès, qui contient les requêtes mais pas la sonde de santé ;
- la sauvegarde puis la restauration ;
- les réseaux : l'application sur le réseau `bridge` de Docker, la base et le service de sauvegarde sans réseau, aucun réseau créé par le projet ;
- en PostgreSQL, la création du mot de passe de la base dans `secrets/`, et la connexion par le socket (`settings.py`) ;
- avec `--sqlite`, le refus du compose PostgreSQL sur une instance SQLite, puis celui du kit de l'autre application, sans modification de la base.

Les fichiers du projet de test viennent de `scripts/kit.sh`, comme ceux d'un utilisateur : `--asso` teste donc aussi le kit Asso produit.
Avec `--depuis`, il installe d'abord l'ancienne image avec le kit de sa version (fichiers de l'étiquette Git `v<version>`, qui doit être présente localement), puis passe au nouveau kit et à la nouvelle image, comme un utilisateur qui met à jour. Si les versions des paquets diffèrent, il vérifie la détection de la mise à jour, l'instantané SQLite et les migrations. Sinon, il vérifie qu'aucune migration n'est lancée.

L'intégration continue lance ces contrôles sur chaque pull request, mise à jour comprise. La construction de l'image vérifie aussi la cohérence du verrou avec `pip check`.

**Docker de Container Manager.** Le NAS embarque un Docker plus ancien (24, avec Compose 2.19 ou 2.20). Pour une modification du compose ou du Dockerfile, testez aussi avec un moteur isolé, depuis un dossier qui contient le compose et un `.env` :

```sh
docker run -d --privileged --name dind24 -e DOCKER_TLS_CERTDIR= -v "$PWD:/project" docker:24.0.2-dind
docker exec -w /project dind24 docker compose pull
docker exec -w /project dind24 docker compose up -d
```

Si vous le pouvez, testez enfin sur un vrai NAS : Container Manager a ses propres comportements (voir CLAUDE.md). **Ne reliez jamais deux conteneurs par le réseau** et ne faites pas créer de réseau au projet : le pare-feu de DSM peut bloquer les plages que Docker attribue (voir CLAUDE.md, « Contraintes propres à Synology »).

## Publier une version (mainteneurs)

Les versions s'écrivent `X.Y.Z-N` (voir [CHANGELOG.md](CHANGELOG.md)).

1. **Nouvelle version de Diacamma** : lancez `scripts/update-lock.sh`, vérifiez les versions affichées (`diacamma-syndic` et `diacamma-asso` doivent avoir le même `X.Y.Z`, ce que la publication vérifie) et mettez à jour la ligne « Versions incluses » du README. La révision repart à `-1`.
   Comparez ensuite le nouveau verrou à l'ancien (`git diff requirements.lock`). Repérez chaque **dépendance indirecte qui change de version majeure** sans que l'amont l'exige : regardez sur PyPI ses `Requires-Dist` et la date de sortie de la nouvelle majeure. Si cette majeure est sortie **après** la version amont de Diacamma, l'amont n'a pas pu la tester. Plafonnez-la alors dans la section « Plafonds prudents » de `requirements.in`, en indiquant la date et qui la tire, puis relancez `update-lock.sh`. Retirez les plafonds de la version précédente que l'amont a depuis rattrapés.
   **Révision** (correctif du conteneur, ou correctifs de sécurité Debian et Python) : gardez `requirements.lock` et incrémentez `N`.
2. Remplacez le tag de l'image dans `docker-compose.yml` **et** `docker-compose.sqlite.yml`, ainsi que dans l'exemple de `docker build` du README.
3. Ajoutez l'entrée `## [X.Y.Z-N]` au CHANGELOG.
4. Testez (voir plus haut), commitez, puis poussez une pré-version : `git tag vX.Y.Z-N-rc1 && git push origin vX.Y.Z-N-rc1`.
5. Le workflow « Publication » vérifie la cohérence de l'étiquette, des compose, du verrou et du CHANGELOG. Il construit et teste l'image sur amd64 et arm64 (Syndic et Asso), la publie sur ghcr.io et crée une Release marquée comme pré-version, avec un kit par application. Testez les deux kits sur un NAS, côte à côte grâce à leurs ports différents, et de préférence avec le pare-feu de DSM activé : connexion par le portail Web Station, courriel de test, sauvegarde.
6. Publiez la version définitive : `git tag vX.Y.Z-N && git push origin vX.Y.Z-N`. Les tags d'image `X.Y.Z-N`, `X.Y.Z` et `latest` sont publiés, sous `ghcr.io/jegweb/diacamma`. La Release est aussi annoncée par une discussion dans la catégorie « Annonces ». Si vous renommez cette catégorie, mettez à jour la variable `ANNONCES` de `release.yml` ; sinon la Release est créée sans annonce, avec un avertissement.

**Correctifs de sécurité.** Chaque lundi, le workflow « Failles de sécurité » (`scan.yml`) analyse l'image publiée (`latest`) avec Trivy. Il échoue s'il trouve une faille HIGH ou CRITICAL déjà corrigée en amont, et GitHub vous envoie alors un courriel. Publiez dans ce cas une révision `-N+1` :

- **faille dans un paquet Debian** : il suffit de reconstruire, puisque la construction lance `apt-get upgrade` ;
- **faille dans un paquet Python** : mettez à jour sa seule ligne dans `requirements.lock`, sans relancer `update-lock.sh`, qui ferait évoluer tout le reste ; la construction vérifie la cohérence avec `pip check`.

L'intégration continue reconstruit aussi l'image sans cache le 1er de chaque mois. GitHub suspend les tâches planifiées d'un dépôt public sans activité depuis 60 jours : relancez-les depuis l'onglet Actions si besoin.

Les runners arm64 (`ubuntu-24.04-arm`) ne sont gratuits que pour les dépôts publics.

**Nouveau paquet sur ghcr.io.** Un paquet d'image créé par le workflow prend la visibilité du dépôt : `ghcr.io/jegweb/diacamma` est ainsi devenu public dès la pré-version 2.7.10-4-rc1. Vérifiez-le quand même après le premier envoi d'un nouveau nom, car Container Manager ne télécharge que des paquets publics. Au besoin : page du paquet → **Package settings** → **Change visibility**.
