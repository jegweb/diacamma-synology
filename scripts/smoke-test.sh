#!/usr/bin/env bash
# Test de fumée : lance le projet Compose dans un dossier jetable, puis vérifie
# la connexion, les protections (admin/admin, /static/, hôte inconnu) et les
# commandes de sauvegarde et de restauration. Code de retour non nul en cas d'échec.
#
# Usage : scripts/smoke-test.sh [--asso] [--sqlite] [--depuis <ancienne image>] [image]
#   image : image à tester (défaut : celle du compose).
#   --asso : kit Diacamma Asso (produit par scripts/kit.sh) au lieu de Syndic.
#   --sqlite : variante SQLite (docker-compose.sqlite.yml) au lieu de PostgreSQL.
#     Vérifie aussi qu'un compose PostgreSQL est refusé sur une instance SQLite,
#     et que le kit de l'autre application est refusé sur ces données.
#   --depuis : installe d'abord l'ancienne image avec le kit de sa version (pris
#     dans l'étiquette Git v<version>, version lue dans l'image), puis passe au
#     nouveau kit et à la nouvelle image, comme un utilisateur qui met à jour.
#     Vérifie la détection de la mise à jour, les migrations et l'instantané
#     SQLite (si les versions des paquets diffèrent).
#   Exemples :
#     docker build -t diacamma:local . && scripts/smoke-test.sh diacamma:local
#     scripts/smoke-test.sh --asso diacamma:local
#     scripts/smoke-test.sh --depuis ghcr.io/jegweb/diacamma:latest diacamma:local
# Variable : SMOKE_TIMEOUT, délai maximal d'attente de l'état « healthy » (600 s).
set -euo pipefail
cd "$(dirname "$0")/.."

log() { printf '[test] %s\n' "$*"; }
fail() { printf '[test] ÉCHEC : %s\n' "$*" >&2; exit 1; }

ENGINE=postgresql
COMPOSE_SRC=docker-compose.yml
APPLI=syndic
FROM_IMAGE=""
while (( $# > 0 )); do
  case "$1" in
    --asso) APPLI=asso; shift ;;
    --sqlite) ENGINE=sqlite; COMPOSE_SRC=docker-compose.sqlite.yml; shift ;;
    --depuis) FROM_IMAGE="${2:-}"; [[ -n "$FROM_IMAGE" ]] || fail "--depuis demande une image."; shift 2 ;;
    -*) fail "option inconnue : $1" ;;
    *) break ;;
  esac
done
IMAGE="${1:-$(sed -nE 's/^ *image: *([^ ]*\/diacamma:[^ ]*).*/\1/p' "$COMPOSE_SRC" | head -n 1)}"
TIMEOUT="${SMOKE_TIMEOUT:-600}"
HOST="$APPLI.example.test"
PASSWORD=MotDePasseDeTest-2026
# Ports publiés par les kits : 8100 pour Syndic, 8101 pour Asso.
if [[ "$APPLI" == asso ]]; then URL=http://127.0.0.1:8101; else URL=http://127.0.0.1:8100; fi
APP="diacamma-$APPLI"
# L'autre application : son kit doit être refusé sur ces données (--sqlite).
if [[ "$APPLI" == asso ]]; then OTHER=syndic; else OTHER=asso; fi

for name in "$APP" "$APP-sauvegarde" "$APP-db" "diacamma-$OTHER" "diacamma-$OTHER-sauvegarde"; do
  if docker ps -a --format '{{.Names}}' | grep -x "$name" >/dev/null; then
    fail "un conteneur « $name » existe déjà sur cette machine : supprimez-le avant le test."
  fi
done

T="$(mktemp -d "${TMPDIR:-/tmp}/diacamma-test.XXXXXX")"
compose() { docker compose --project-directory "$T" -f "$T/docker-compose.yml" -p diacamma-test "$@"; }
cleanup() {
  local status=$?
  if (( status != 0 )); then
    log "Journal des conteneurs :"
    compose logs --no-color --tail 150 >&2 || true
  fi
  compose down -v --remove-orphans >/dev/null 2>&1 || true
  # Restes que le dernier compose ne déclare pas : réseaux des kits d'avant
  # 2.7.10-4 (--depuis), volume du socket après un passage en SQLite.
  docker network rm diacamma-test_backend diacamma-test_default >/dev/null 2>&1 || true
  docker volume rm diacamma-test_db-socket >/dev/null 2>&1 || true
  rm -rf "$T"
  exit "$status"
}
trap cleanup EXIT

mkdir -p "$T/data" "$T/backups"
# Les fichiers viennent du kit de l'application, comme pour un utilisateur.
scripts/kit.sh "$APPLI" "$T/kit" >/dev/null
cp "$T/kit/$COMPOSE_SRC" "$T/docker-compose.yml"
# Remplace l'image des services Diacamma (pas celle de PostgreSQL).
set_image() {
  sed -i.orig -E "s|^( *image: *)[^ ]*diacamma[^ ]*|\1$1|" "$T/docker-compose.yml"
  rm -f "$T/docker-compose.yml.orig"
}
pull_if_needed() {
  docker image inspect "$1" >/dev/null 2>&1 || docker pull -q "$1" >/dev/null
}
# Les images d'avant 2.7.10-4 n'ont qu'un identifiant, celui de Syndic.
build_id() {
  pull_if_needed "$1"
  docker run --rm --entrypoint sh "$1" -c \
    "cat /opt/diacamma/build-id/$APPLI 2>/dev/null || cat /opt/diacamma/diacamma-build-id"
}
if [[ -n "$FROM_IMAGE" && "$APPLI" == asso ]]; then
  pull_if_needed "$FROM_IMAGE"
  docker run --rm --entrypoint test "$FROM_IMAGE" -e /opt/diacamma/build-id/asso \
    || fail "$FROM_IMAGE ne contient pas Diacamma Asso : pas de mise à jour à tester."
fi
# Compose du kit de l'ancienne version, pris dans son étiquette Git : une
# ancienne image ne sait pas lire le compose actuel (depuis 2.7.10-4, la base
# est jointe par son socket et n'a plus de réseau).
old_kit() {
  local version src
  pull_if_needed "$FROM_IMAGE"
  version="$(docker image inspect -f '{{index .Config.Labels "org.opencontainers.image.version"}}' "$FROM_IMAGE")"
  git rev-parse -q --verify "refs/tags/v$version" >/dev/null \
    || fail "étiquette Git v$version absente (version de $FROM_IMAGE) : lancez git fetch --tags."
  mkdir -p "$T/ancien"
  git archive "v$version" | tar -x -C "$T/ancien"
  if [[ -f "$T/ancien/scripts/kit.sh" ]]; then
    bash "$T/ancien/scripts/kit.sh" "$APPLI" "$T/ancien-kit" >/dev/null
    src="$T/ancien-kit/$COMPOSE_SRC"
  else
    # Avant 2.7.10-4 : Syndic seul, compose à la racine du dépôt.
    src="$T/ancien/$COMPOSE_SRC"
  fi
  [[ -f "$src" ]] || fail "le kit v$version ne contient pas $COMPOSE_SRC."
  cp "$src" "$T/docker-compose.yml"
  log "Ancienne version : kit v$version."
}
{
  echo "DIACAMMA_ALLOWED_HOSTS=$HOST"
  echo "DIACAMMA_ADMIN_PASSWORD=$PASSWORD"
  # Sous Linux, les dossiers appartiennent à l'utilisateur courant (UID 1026
  # absent) ; sous macOS, le partage de fichiers de Docker gère les droits.
  if [[ "$(uname -s)" == Linux ]]; then
    echo "PUID=$(id -u)"
    echo "PGID=$(id -g)"
  fi
} > "$T/.env"
# Dossiers vides, comme créés avec File Station : le mot de passe de la base
# est généré au premier démarrage.
if [[ "$ENGINE" == postgresql ]]; then
  mkdir -p "$T/postgresql" "$T/secrets"
fi

wait_healthy() {
  local waited=0 status
  while (( waited < TIMEOUT )); do
    status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}} {{.RestartCount}}' "$APP")"
    case "$status" in
      "healthy "*) log "« $APP » est healthy après ${waited} s."; return 0 ;;
      unhealthy*) fail "« $APP » est unhealthy." ;;
      *" 0") ;;
      *) fail "« $APP » a redémarré (erreur au démarrage)." ;;
    esac
    sleep 5
    waited=$(( waited + 5 ))
  done
  fail "« $APP » n'est pas healthy après ${TIMEOUT} s."
}

# Les images publiées jusqu'à 2.7.10-2 n'attendent pas PostgreSQL : pour
# elles, on démarre la base d'abord (comme l'ancien compose, en « healthy »).
start_db_first() {
  local waited=0
  compose up -d --quiet-pull db
  until [[ "$(docker inspect -f '{{.State.Health.Status}}' "$APP-db")" == healthy ]]; do
    (( waited < 180 )) || fail "« $APP-db » n'est pas healthy après 180 s."
    sleep 3
    waited=$(( waited + 3 ))
  done
}

http_code() { curl -s -o /dev/null -w '%{http_code}' -H "Host: ${2:-$HOST}" "$URL$1"; }
login() {
  curl -s -H "Host: $HOST" -X POST --data "login=$1&password=$2" "$URL/CORE/authentification"
}
# Les grep lisent toute leur entrée (pas de -q) : avec pipefail, un grep -q
# qui s'arrête tôt ferait échouer la commande en amont (SIGPIPE).
# Réessaie pendant 2 minutes : juste après un redémarrage, l'état « healthy »
# peut encore être celui d'avant et gunicorn pas encore prêt.
check_login() {
  local tries=0
  until login admin "$PASSWORD" | grep -E '"data" *: *"OK"' >/dev/null; do
    (( ++tries < 40 )) || fail "connexion admin avec le mot de passe fourni refusée."
    sleep 3
  done
  log "OK : connexion admin."
}

log "Dossier de test : $T (kit $APPLI, $COMPOSE_SRC, image $IMAGE${FROM_IMAGE:+, depuis $FROM_IMAGE})"
if [[ -n "$FROM_IMAGE" ]]; then
  old_kit
  set_image "$FROM_IMAGE"
  [[ "$ENGINE" == sqlite ]] || start_db_first
  compose up -d --quiet-pull
  wait_healthy
  check_login
  log "OK : installation de l'ancienne version ; passage au nouveau kit et à $IMAGE."
  old_id="$(build_id "$FROM_IMAGE")"
  new_id="$(build_id "$IMAGE")"
  cp "$T/kit/$COMPOSE_SRC" "$T/docker-compose.yml"
  set_image "$IMAGE"
  compose up -d --quiet-pull
  wait_healthy
  if [[ "$old_id" != "$new_id" ]]; then
    docker logs "$APP" 2>&1 | grep -F "Mise à jour détectée : $old_id -> $new_id" >/dev/null \
      || fail "la mise à jour $old_id -> $new_id n'a pas été détectée."
    if [[ "$ENGINE" == sqlite ]]; then
      find "$T/backups/avant-mise-a-jour" -name "${APPLI}_*.tar.gz" 2>/dev/null | grep . >/dev/null \
        || fail "aucun instantané dans backups/avant-mise-a-jour/."
      log "OK : instantané SQLite pris avant la mise à jour."
    else
      docker logs "$APP" 2>&1 | grep -F "pas d'instantané automatique" >/dev/null \
        || fail "l'absence d'instantané PostgreSQL n'est pas signalée."
    fi
    log "OK : mise à jour détectée et migrations appliquées ($old_id -> $new_id)."
  else
    ! docker logs "$APP" 2>&1 | grep -F "Mise à jour détectée" >/dev/null || fail "mise à jour détectée alors que les paquets sont identiques."
    log "OK : paquets identiques, aucune migration (révision de l'image)."
  fi
else
  set_image "$IMAGE"
  compose up -d --quiet-pull
  wait_healthy
fi
[[ "$(docker inspect -f '{{.State.Running}}' "$APP-sauvegarde")" == true ]] || fail "le service de sauvegarde ne tourne pas."
log "OK : service de sauvegarde lancé."

# Réseaux : l'application sur le réseau « bridge » de Docker, le reste sans
# réseau, et aucun réseau créé par le projet (pare-feu de DSM, plages épuisées).
check_network() {
  local mode
  mode="$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$1")"
  [[ "$mode" == "$2" ]] || fail "« $1 » est sur le réseau « $mode » au lieu de « $2 »."
}
check_network "$APP" bridge
check_network "$APP-sauvegarde" none
if [[ "$ENGINE" == postgresql ]]; then
  check_network "$APP-db" none
  docker exec "$APP" grep -F '"HOST": "/var/run/postgresql",' "/data/$APPLI/settings.py" >/dev/null \
    || fail "settings.py ne désigne pas le socket de la base (/var/run/postgresql)."
  # Sonde pg_isready, par le socket : c'est l'état affiché par Container Manager.
  waited=0
  until [[ "$(docker inspect -f '{{.State.Health.Status}}' "$APP-db")" == healthy ]]; do
    (( waited < 60 )) || fail "« $APP-db » n'est pas healthy (sonde pg_isready par le socket)."
    sleep 3
    waited=$(( waited + 3 ))
  done
fi
if [[ -z "$FROM_IMAGE" && -n "$(docker network ls -q --filter label=com.docker.compose.project=diacamma-test)" ]]; then
  fail "le projet a créé un réseau Docker."
fi
log "OK : application sur le réseau bridge, base et sauvegarde sans réseau."
[[ "$ENGINE" == sqlite ]] || log "OK : « $APP-db » healthy (pg_isready par le socket)."

if [[ "$ENGINE" == postgresql ]]; then
  [[ "$(wc -c < "$T/secrets/db_password.txt" | tr -d ' ')" == 32 ]] \
    || fail "secrets/db_password.txt n'a pas été généré (32 caractères attendus)."
  log "OK : mot de passe de la base généré dans secrets/."
  ! docker logs "$APP" 2>&1 | grep -F "$(cat "$T/secrets/db_password.txt")" >/dev/null \
    || fail "le mot de passe de la base apparaît dans le journal."
  log "OK : mot de passe de la base absent du journal."
fi

check_login
login admin admin | grep BADAUTH >/dev/null || fail "admin/admin n'est pas refusé."
log "OK : admin/admin refusé."
for path in /static/settings.py /static/db.sqlite3; do
  code="$(http_code "$path")"
  [[ "$code" == 404 ]] || fail "$path répond $code au lieu de 404."
  log "OK : $path → 404."
done
code="$(http_code / inconnu.example.test)"
[[ "$code" == 400 ]] || fail "un hôte inconnu reçoit $code au lieu de 400."
log "OK : hôte inconnu → 400."

# Journal d'accès : les requêtes ordinaires y figurent, mais pas la sonde de
# santé, dont une réponse au moins a rendu le conteneur healthy.
docker logs "$APP" 2>&1 | grep -F '"GET /static/settings.py HTTP/1.1" 404' >/dev/null \
  || fail "les requêtes ne figurent pas dans le journal d'accès."
! docker logs "$APP" 2>&1 | grep -E 'diacamma-healthcheck|Python-urllib' >/dev/null \
  || fail "la sonde de santé apparaît dans le journal d'accès."
log "OK : journal d'accès sans la sonde de santé."

docker exec "$APP" diacamma version
# Dans le conteneur de sauvegarde, sans réseau, comme la sauvegarde de la nuit.
docker exec "$APP-sauvegarde" diacamma backup
archive="$(find "$T/backups" -maxdepth 1 -name "manuel_${APPLI}_*.lbk" -exec basename {} \; | head -n 1)"
[[ -n "$archive" ]] || fail "aucune archive manuelle créée dans backups/."
log "OK : archive $archive créée."
docker exec "$APP" diacamma restore "$archive" 2>&1 | tee "$T/restauration.log"
if [[ "$ENGINE" == postgresql ]]; then
  ! grep -F "$(cat "$T/secrets/db_password.txt")" "$T/restauration.log" >/dev/null \
    || fail "le mot de passe de la base apparaît dans la sortie de la restauration."
fi
docker restart "$APP" >/dev/null
check_login
log "OK : restauration puis redémarrage."

# Attend le message de refus $2 dans le journal du conteneur $1.
wait_refusal() {
  local tries=0
  until docker logs "$1" 2>&1 | grep -F "$2" >/dev/null; do
    (( ++tries < 30 )) || return 1
    sleep 3
  done
}
# Utilisateur SQLite qui prend par erreur le compose PostgreSQL du kit (sans
# créer postgresql/ ni secrets/) : refus explicite, base intacte.
if [[ "$ENGINE" == sqlite ]]; then
  compose down >/dev/null 2>&1
  database="$T/data/$APPLI/db.sqlite3"
  before="$(cksum < "$database")"
  cp "$T/kit/docker-compose.yml" "$T/docker-compose.yml"
  set_image "$IMAGE"
  compose up -d --quiet-pull
  wait_refusal "$APP" "prenez docker-compose.sqlite.yml" \
    || fail "le compose PostgreSQL n'est pas refusé sur une instance SQLite."
  compose down >/dev/null 2>&1
  [[ "$(cksum < "$database")" == "$before" ]] || fail "la base SQLite a été modifiée par le compose PostgreSQL."
  log "OK : compose PostgreSQL refusé sur une instance SQLite, base intacte."

  # Kit de l'autre application posé sur ces données : refus, base intacte.
  scripts/kit.sh "$OTHER" "$T/autre-kit" >/dev/null
  cp "$T/autre-kit/docker-compose.sqlite.yml" "$T/docker-compose.yml"
  set_image "$IMAGE"
  compose up -d --quiet-pull
  wait_refusal "diacamma-$OTHER" "mais ce kit est celui de" \
    || fail "le kit $OTHER n'est pas refusé sur les données de $APPLI."
  compose down >/dev/null 2>&1
  [[ "$(cksum < "$database")" == "$before" ]] || fail "la base SQLite a été modifiée par le kit $OTHER."
  [[ ! -e "$T/data/$OTHER" ]] || fail "le kit $OTHER a créé une instance dans les données de $APPLI."
  log "OK : kit $OTHER refusé sur les données de $APPLI, base intacte."
fi

log "Tous les contrôles sont passés."
