#!/bin/bash


set -e

ISSUER_HOME="${HOME}/.issuer-node"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Función para mostrar el estado
show_status() {
    log_info "Estado de los servicios Issuer Node:"
    echo ""
    
    services=("issuer-platform" "issuer-notifications" "issuer-publisher")
    
    for service in "${services[@]}"; do
        if sudo systemctl is-active --quiet "${service}.service"; then
            echo -e "  ${service}: ${GREEN}ACTIVO${NC}"
        else
            echo -e "  ${service}: ${RED}INACTIVO${NC}"
        fi
    done
    
    echo ""
    log_info "Verificando conectividad API..."
    
    if curl -s -f http://localhost:3001/status > /dev/null 2>&1; then
        log_success "API responde en http://localhost:3001"
    else
        log_error "API no responde en http://localhost:3001"
    fi
}

# Iniciar servicios
start_services() {
    log_info "Iniciando servicios Issuer Node..."
    
    sudo systemctl start issuer-platform.service
    sudo systemctl start issuer-notifications.service
    sudo systemctl start issuer-publisher.service
    
    sleep 3
    show_status
}

# Detener servicios
stop_services() {
    log_info "Deteniendo servicios Issuer Node..."
    
    sudo systemctl stop issuer-platform.service
    sudo systemctl stop issuer-notifications.service
    sudo systemctl stop issuer-publisher.service
    
    log_success "Servicios detenidos"
}

# Reiniciar servicios
restart_services() {
    log_info "Reiniciando servicios Issuer Node..."
    
    stop_services
    sleep 2
    start_services
}

# Ver logs
show_logs() {
    local service=${1:-platform}
    log_info "Mostrando logs del servicio issuer-${service}..."
    journalctl -u "issuer-${service}.service" -f
}

# Importar clave privada
import_private_key() {
    if [ -z "$1" ]; then
        log_error "Por favor proporciona la clave privada"
        echo "Uso: $0 import-key <private_key>"
        exit 1
    fi
    
    local private_key="$1"
    
    log_info "Importando clave privada..."
    
    export $(cat "$ISSUER_HOME/.env-issuer" | xargs)
    cd "$ISSUER_HOME/IsureNode-docker/Go-issuer-node"
    
    # Crear archivo JSON para la clave si no existe
    local keys_file="$ISSUER_HOME/keys/kms_localstorage_keys.json"
    if [ ! -f "$keys_file" ]; then
        mkdir -p "$ISSUER_HOME/keys"
        echo "[]" > "$keys_file"
    fi
    
    # Aquí integrarías la lógica de importación de claves
    # Por ahora, mostramos el comando que se ejecutaría
    log_info "Para importar la clave, ejecuta:"
    echo "make private_key=$private_key import-private-key-to-kms"
    
    log_success "Proceso de importación iniciado"
}

# Crear identidad
create_identity() {
    log_info "Creando nueva identidad..."
    
    export $(cat "$ISSUER_HOME/.env-issuer" | xargs)
    
    # Hacer una petición POST a la API para crear identidad
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -u "${ISSUER_API_AUTH_USER}:${ISSUER_API_AUTH_PASSWORD}" \
        http://localhost:3001/v1/identities \
        -d '{"didMetadata":{"method":"polygonid","blockchain":"polygon","network":"amoy"}}')
    
    if [ $? -eq 0 ]; then
        log_success "Identidad creada:"
        echo "$response" | jq '.' 2>/dev/null || echo "$response"
    else
        log_error "Error creando identidad"
    fi
}

# Verificar configuración
check_config() {
    log_info "Verificando configuración..."
    
    if [ ! -f "$ISSUER_HOME/.env-issuer" ]; then
        log_error "Archivo de configuración no encontrado: $ISSUER_HOME/.env-issuer"
        exit 1
    fi
    
    log_success "Archivo de configuración encontrado"
    
    # Verificar servicios de base de datos y Redis
    if ! pg_isready -h localhost -p 5432 > /dev/null 2>&1; then
        log_error "PostgreSQL no está disponible"
    else
        log_success "PostgreSQL está disponible"
    fi
    
    if ! redis-cli ping > /dev/null 2>&1; then
        log_error "Redis no está disponible"
    else
        log_success "Redis está disponible"
    fi
}

# Mostrar ayuda
show_help() {
    echo "Issuer Node Manager - Gestión de servicios nativa"
    echo ""
    echo "Uso: $0 <comando> [opciones]"
    echo ""
    echo "Comandos disponibles:"
    echo "  status              Mostrar estado de servicios"
    echo "  start               Iniciar servicios"
    echo "  stop                Detener servicios"
    echo "  restart             Reiniciar servicios"
    echo "  logs [servicio]     Mostrar logs (platform|notifications|publisher)"
    echo "  import-key <key>    Importar clave privada"
    echo "  create-identity     Crear nueva identidad"
    echo "  check-config        Verificar configuración"
    echo "  update              Actualizar a la última versión"
    echo "  help                Mostrar esta ayuda"
    echo ""
    echo "Ejemplos:"
    echo "  $0 status"
    echo "  $0 logs platform"
    echo "  $0 import-key 0x1234567890abcdef..."
}

# Función principal
main() {
    case "${1:-}" in
        "status")
            show_status
            ;;
        "start")
            start_services
            ;;
        "stop")
            stop_services
            ;;
        "restart")
            restart_services
            ;;
        "logs")
            show_logs "${2:-platform}"
            ;;
        "import-key")
            import_private_key "$2"
            ;;
        "create-identity")
            create_identity
            ;;
        "check-config")
            check_config
            ;;
        "update")
            if [ -f "$ISSUER_HOME/update-issuer.sh" ]; then
                "$ISSUER_HOME/update-issuer.sh"
            else
                log_error "Script de actualización no encontrado"
                exit 1
            fi
            ;;
        "help"|"--help"|"-h"|"")
            show_help
            ;;
        *)
            log_error "Comando desconocido: $1"
            show_help
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi