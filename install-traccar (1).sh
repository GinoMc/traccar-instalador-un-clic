#!/bin/bash
#
# OpenLatam - Instalador de un clic para Traccar (Plataforma GPS)
# Uso: bash install-traccar.sh
#
set -e

# ---------- Colores ----------
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

step() { echo -e "\n${BLUE}▶ $1${NC}"; }
ok()   { echo -e "${GREEN}✔ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
err()  { echo -e "${RED}✘ $1${NC}"; }

echo -e "${GREEN}"
echo "======================================================"
echo "   OpenLatam - Instala tu plataforma GPS en un clic"
echo "======================================================"
echo -e "${NC}"

# ---------- Validaciones ----------
if [ "$EUID" -ne 0 ]; then
  err "Este script debe correrse como root. Prueba: sudo bash install-traccar.sh"
  exit 1
fi

if ! grep -qi ubuntu /etc/os-release 2>/dev/null; then
  warn "No se detectó Ubuntu. El script está probado en Ubuntu 22/24, puede fallar en otras distros."
fi

echo ""
echo -e "${YELLOW}Escribe la clave de tu base de datos y guárdala en un lugar seguro.${NC}"
read -rp "> " DB_PASS
while [ -z "$DB_PASS" ]; do
  warn "La clave no puede estar vacía."
  read -rp "> " DB_PASS
done

# ---------- 1. Actualizar paquetes ----------
step "Paso 1/6 — Actualizando paquetes e instalando MySQL..."
export DEBIAN_FRONTEND=noninteractive
apt update -y >/dev/null
apt -y install unzip mysql-server >/dev/null
ok "Paquetes instalados"

# ---------- 2. Configurar MySQL ----------
step "Paso 2/6 — Configurando MySQL y creando base de datos..."
systemctl enable mysql >/dev/null 2>&1 || true
systemctl start mysql >/dev/null 2>&1 || true

mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${DB_PASS}'; FLUSH PRIVILEGES;"
mysql -uroot -p"${DB_PASS}" -e "CREATE DATABASE IF NOT EXISTS traccar;"
ok "Base de datos 'traccar' creada"

# ---------- 3. Descargar Traccar ----------
step "Paso 3/6 — Descargando la última versión de Traccar..."
cd /root
rm -f traccar-linux-*.zip
wget -q https://www.traccar.org/download/traccar-linux-64-latest.zip -O traccar-linux-64-latest.zip
ok "Descarga completada"

# ---------- 4. Instalar Traccar ----------
step "Paso 4/6 — Instalando Traccar..."
unzip -oq traccar-linux-64-latest.zip
chmod +x traccar.run
./traccar.run >/dev/null
ok "Traccar instalado en /opt/traccar"

# ---------- 5. Configurar traccar.xml ----------
step "Paso 5/6 — Conectando Traccar con la base de datos..."
cat > /opt/traccar/conf/traccar.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE properties SYSTEM 'http://java.sun.com/dtd/properties.dtd'>
<properties>
    <entry key='database.driver'>com.mysql.cj.jdbc.Driver</entry>
    <entry key='database.url'>jdbc:mysql://localhost/traccar?zeroDateTimeBehavior=round&amp;serverTimezone=UTC&amp;allowPublicKeyRetrieval=true&amp;useSSL=false&amp;allowMultiQueries=true&amp;autoReconnect=true&amp;useUnicode=yes&amp;characterEncoding=UTF-8&amp;sessionVariables=sql_mode=''</entry>
    <entry key='database.user'>root</entry>
    <entry key='database.password'>${DB_PASS}</entry>
</properties>
EOF
ok "Configuración aplicada"

# ---------- 6. Iniciar servicio ----------
step "Paso 6/6 — Iniciando el servicio de Traccar..."
systemctl enable traccar >/dev/null 2>&1 || true
service traccar restart
sleep 5

if systemctl is-active --quiet traccar; then
  ok "Traccar está corriendo"
else
  err "Traccar no arrancó correctamente. Revisa: journalctl -u traccar -n 50"
  exit 1
fi

# ---------- Resumen final ----------
PUBLIC_IP=$(curl -s -4 ifconfig.me || hostname -I | awk '{print $1}')

echo -e "\n${GREEN}======================================================"
echo "   ✅ INSTALACIÓN COMPLETADA"
echo -e "======================================================${NC}"
echo ""
echo "Estos datos son importantes, guárdalos:"
echo -e "URL de ingreso:        ${BLUE}http://${PUBLIC_IP}:8082${NC}"
echo -e "Contraseña base de datos: ${YELLOW}${DB_PASS}${NC}"
echo ""
echo "Entra a la URL y crea tu cuenta de administrador (esa cuenta la defines tú al entrar, no viene preconfigurada)."
echo -e "${GREEN}======================================================${NC}\n"
