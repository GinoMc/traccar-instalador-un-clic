#!/usr/bin/env bash
#
# Instalador de Traccar con Docker y MySQL
# Uso (como root, en un VPS con Ubuntu o Debian):
#   curl -fsSL https://raw.githubusercontent.com/GinoMc/traccar-instalador-un-clic/main/instalar-docker.sh | bash
#
# El script no hace preguntas. Instala Docker si falta, genera una contraseña
# segura para la base de datos y levanta la última versión de Traccar.
#
# Úsalo solo en un VPS limpio, nunca en un servidor que ya esté en producción.

set -euo pipefail

# Todo va dentro de main para que nada se ejecute si la descarga se corta.
main() {
  local DIR="/opt/traccar"
  local COMPOSE="$DIR/compose.yaml"
  local COMPOSE_URL="https://raw.githubusercontent.com/traccar/traccar/master/docker/compose/traccar-mysql.yaml"
  local ESPERA_MAXIMA=300

  info()  { printf '\n==> %s\n' "$1"; }
  error() { printf '\nERROR: %s\n' "$1" >&2; exit 1; }

  # --- Comprobaciones: se detiene antes de tocar nada ---
  [ "$(id -u)" -eq 0 ] || error "Ejecuta el script como root."

  [ ! -e "$COMPOSE" ] || error "Ya existe una instalación en $DIR. No se cambió nada."

  # Si Docker publicara estos puertos, podría quitarle tráfico a lo que ya corre.
  command -v ss >/dev/null 2>&1 || error "No se encontró el comando ss para revisar los puertos."
  local OCUPADOS
  OCUPADOS="$(ss -H -ltun \
    | awk '{print $5}' | sed 's/.*://' \
    | awk '$1 == 8082 || ($1 >= 5000 && $1 <= 5500)' \
    | sort -un | tr '\n' ' ')"
  [ -z "$OCUPADOS" ] || error "Puertos ya en uso: $OCUPADOS. Este script es solo para un VPS limpio."

  # --- Docker ---
  if command -v docker >/dev/null 2>&1; then
    info "Docker ya está instalado"
    # Reiniciar Docker o cambiar su configuración afectaría a esos contenedores.
    [ -z "$(docker ps -q)" ] || error "Este servidor ya tiene contenedores activos. El script es solo para un VPS limpio."
  else
    info "Instalando Docker"
    curl -fsSL https://get.docker.com | sh
  fi
  docker compose version >/dev/null 2>&1 || error "Falta Docker Compose."

  # Evita que Docker cree un proceso por cada puerto publicado.
  # No se toca un daemon.json existente porque puede tener otros ajustes.
  if [ ! -e /etc/docker/daemon.json ]; then
    mkdir -p /etc/docker
    echo '{"userland-proxy": false}' > /etc/docker/daemon.json
    systemctl restart docker
  elif ! grep -q '"userland-proxy"' /etc/docker/daemon.json; then
    info "Aviso: /etc/docker/daemon.json ya existe; no se modificó"
  fi

  # --- Configuración de Traccar ---
  info "Preparando Traccar en $DIR"
  mkdir -p "$DIR/data" "$DIR/logs"
  curl -fsSL -o "$COMPOSE" "$COMPOSE_URL"

  local PASS
  PASS="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"

  sed -i \
    -e "s/MYSQL_PASSWORD: traccar/MYSQL_PASSWORD: $PASS/" \
    -e "s/DATABASE_PASSWORD: traccar/DATABASE_PASSWORD: $PASS/" \
    "$COMPOSE"

  # El archivo oficial solo publica TCP; algunos GPS envían por UDP.
  sed -i 's|^\( *\)- "5000-5500:5000-5500"$|&\n\1- "5000-5500:5000-5500/udp"|' "$COMPOSE"

  # Si el archivo oficial cambia de formato, es mejor parar que instalar mal.
  if ! grep -q "MYSQL_PASSWORD: $PASS" "$COMPOSE" \
    || ! grep -q "DATABASE_PASSWORD: $PASS" "$COMPOSE" \
    || ! grep -q '5000-5500/udp' "$COMPOSE"; then
    rm -f "$COMPOSE"
    error "El archivo oficial de Traccar cambió. No se levantó nada."
  fi

  # La contraseña queda aquí: solo root debe poder leerla.
  chmod 600 "$COMPOSE"

  if ! (cd "$DIR" && docker compose config -q); then
    rm -f "$COMPOSE"
    error "El archivo compose.yaml no es válido."
  fi

  # --- Arranque ---
  info "Descargando y encendiendo Traccar (la primera vez tarda unos minutos)"
  (cd "$DIR" && docker compose up -d) || error "No se pudo encender Traccar. Revisa: cd $DIR && docker compose logs"

  info "Esperando a que Traccar responda"
  local segundos=0
  until curl -fsS -o /dev/null http://localhost:8082/ 2>/dev/null; do
    if [ "$segundos" -ge "$ESPERA_MAXIMA" ]; then
      error "Traccar no respondió a tiempo. Revisa: cd $DIR && docker compose logs traccar"
    fi
    sleep 5
    segundos=$((segundos + 5))
  done

  local IP
  IP="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
  [ -n "$IP" ] || IP="$(hostname -I | awk '{print $1}')"

  cat <<EOF

=====================================================
  Traccar está listo

  Entra a:  http://$IP:8082

  Crea tu usuario ahora: el primero que se registra
  queda como administrador.

  Si no carga, abre los puertos 8082 y 5000-5500
  en el firewall de tu proveedor de VPS.

  Actualizar:  cd $DIR && docker compose pull && docker compose up -d
  Ver logs:    cd $DIR && docker compose logs -f traccar
=====================================================
EOF
}

main "$@"
