#!/usr/bin/bash


set -e
# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables de configuración
ISSUER_HOME="${HOME}/.issuer-node"

REPO_URL="https://github.com/0xronaldo/Go-issuer-node.git"


BRANCH="main"
GO_MIN_VERSION="1.22"
POSTGRES_VERSION="16"

# Funciones de utilidad
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}


# Verificar dependencias del sistema
check_dependencies() {
    log_info "Verificando dependencias del sistema..."
    
    # Verificar Go
    if ! command -v go &> /dev/null; then
        log_error "Go no está instalado. Por favor instala Go $GO_MIN_VERSION o superior"
        exit 1
    fi
    
    local go_version=$(go version | grep -oE 'go[0-9]+\.[0-9]+' | cut -d'o' -f2)
    if ! printf '%s\n' "$GO_MIN_VERSION" "$go_version" | sort -V -C; then
        log_error "Go version $go_version encontrada. Se requiere $GO_MIN_VERSION o superior"
        exit 1
    fi
    
    # Verificar PostgreSQL
    if ! command -v psql &> /dev/null; then
        log_warning "PostgreSQL no encontrado. Instalando..."
        install_postgresql
    fi
    
    # Verificar Redis
    if ! command -v redis-server &> /dev/null; then
        log_warning "Redis no encontrado. Instalando..."
        install_redis
    fi
    
    # Verificar Git
    if ! command -v git &> /dev/null; then
        log_error "Git no está instalado"
        exit 1
    fi
    
    log_success "Dependencias verificadas correctamente"
}

# Instalar PostgreSQL
install_postgresql() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v apt-get &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y postgresql postgresql-contrib
        elif command -v yum &> /dev/null; then
            sudo yum install -y postgresql-server postgresql-contrib
            sudo postgresql-setup initdb
        fi
        sudo systemctl enable postgresql
        sudo systemctl start postgresql
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &> /dev/null; then
            brew install postgresql
            brew services start postgresql
        fi
    fi
}

# Instalar Redis
install_redis() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v apt-get &> /dev/null; then
            sudo apt-get install -y redis-server
        elif command -v yum &> /dev/null; then
            sudo yum install -y redis
        fi
        sudo systemctl enable redis
        sudo systemctl start redis
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &> /dev/null; then
            brew install redis
            brew services start redis
        fi
    fi
}


# Configurar directorio de trabajo

setup_directory() {
    log_info "Configurando directorio de trabajo en $ISSUER_HOME"
    
    if [ ! -d "$ISSUER_HOME" ]; then
        mkdir -p "$ISSUER_HOME"
    fi
    
    cd "$ISSUER_HOME"
    
    # Clonar repositorio si no existe
    if [ ! -d "IsureNode-docker" ]; then
        log_info "Clonando repositorio..."
        git clone "$REPO_URL" IsureNode-docker
    fi
    
    cd IsureNode-docker/Go-issuer-node
    git checkout "$BRANCH"
    
    log_success "Directorio configurado correctamente"
}

# Configurar base de datos
setup_database() {
    log_info "Configurando base de datos PostgreSQL..."
    
    # Crear usuario y base de datos
    sudo -u postgres psql -c "CREATE USER issuer WITH PASSWORD 'issuerpass';" 2>/dev/null || true
    sudo -u postgres psql -c "CREATE DATABASE issuerdb OWNER issuer;" 2>/dev/null || true
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE issuerdb TO issuer;" 2>/dev/null || true
    
    log_success "Base de datos configurada"
}

# Generar configuración
generate_config() {
    log_info "Generando archivo de configuración..."
    
    cat > "$ISSUER_HOME/.env-issuer" << EOF
# Configuración del Issuer Node
ISSUER_SERVER_URL=http://localhost:3001
ISSUER_SERVER_PORT=3001
ISSUER_DATABASE_URL=postgres://issuer:issuerpass@localhost:5432/issuerdb?sslmode=disable
ISSUER_REDIS_URL=redis://@localhost:6379/1

# Autenticación API
ISSUER_API_AUTH_USER=admin
ISSUER_API_AUTH_PASSWORD=admin123

# KMS Configuration (Local Storage)
ISSUER_KMS_BJJ_PROVIDER=localstorage
ISSUER_KMS_ETH_PROVIDER=localstorage
ISSUER_KMS_SOL_PROVIDER=localstorage
ISSUER_KMS_PROVIDER_LOCAL_STORAGE_FILE_PATH=$ISSUER_HOME/keys

# Cache
ISSUER_CACHE_PROVIDER=redis
ISSUER_CACHE_URL=redis://@localhost:6379/1

# Circuit Path
ISSUER_CIRCUIT_PATH=$ISSUER_HOME/IsureNode-docker/Go-issuer-node/pkg/credentials/circuits

# Logs
ISSUER_LOG_LEVEL=0
ISSUER_LOG_MODE=1

# IPFS
ISSUER_IPFS_GATEWAY_URL=https://cloudflare-ipfs.com

# Resolver
ISSUER_RESOLVER_PATH=$ISSUER_HOME/resolvers_settings.yaml

# Schema Cache
ISSUER_SCHEMA_CACHE=true
EOF

    # Crear directorio de claves si no existe
    mkdir -p "$ISSUER_HOME/keys"
    
    log_success "Configuración generada en $ISSUER_HOME/.env-issuer"
}

# Generar configuración de resolvers
generate_resolver_config() {
    log_info "Generando configuración de resolvers..."
    
    cat > "$ISSUER_HOME/resolvers_settings.yaml" << EOF
polygon:
  amoy:
    networkURL: https://rpc-amoy.polygon.technology/
    chainID: 80002
    defaultGasLimit: 600000
    maxGasPrice: 1000000
    confirmationTimeout: 600s
    confirmationBlockCount: 5
    receiptTimeout: 600s
    minGasPrice: 0
    rpcResponseTimeout: 5s
    waitReceiptCycleTime: 30s
    waitBlockCycleTime: 30s
    contractAddress: "0x1a4cC30f2aA0377b0c3bc9848766D90cb4404124"
    multicallAddress: "0xca11bde05977b3631167028862be2a173976ca11"
  
  main:
    networkURL: https://polygon-rpc.com/
    chainID: 137
    defaultGasLimit: 600000
    maxGasPrice: 500000000000
    confirmationTimeout: 600s
    confirmationBlockCount: 50
    receiptTimeout: 600s
    minGasPrice: 30000000000
    rpcResponseTimeout: 5s
    waitReceiptCycleTime: 30s
    waitBlockCycleTime: 30s
    contractAddress: "0x624ce98D2d27b20b8f8d521723Df8fC4db71D79D"
    multicallAddress: "0xca11bde05977b3631167028862be2a173976ca11"

ethereum:
  main:
    networkURL: https://mainnet.infura.io/v3/YOUR_INFURA_KEY
    chainID: 1
    defaultGasLimit: 600000
    maxGasPrice: 50000000000
    confirmationTimeout: 600s
    confirmationBlockCount: 12
    receiptTimeout: 600s
    minGasPrice: 1000000000
    rpcResponseTimeout: 5s
    waitReceiptCycleTime: 30s
    waitBlockCycleTime: 30s
    contractAddress: "0x624ce98D2d27b20b8f8d521723Df8fC4db71D79D"
    multicallAddress: "0xca11bde05977b3631167028862be2a173976ca11"
EOF

    log_success "Configuración de resolvers generada"
}

# Compilar binarios
build_binaries() {
    log_info "Compilando binarios del issuer node..."
    
    cd "$ISSUER_HOME/IsureNode-docker/Go-issuer-node"
    
    # Descargar dependencias
    go mod download
    
    # Compilar todos los comandos
    go build -ldflags "-X main.build=$(git rev-parse --short HEAD)" -o "$ISSUER_HOME/bin/platform" ./cmd/platform/main.go
    go build -ldflags "-X main.build=$(git rev-parse --short HEAD)" -o "$ISSUER_HOME/bin/migrate" ./cmd/migrate/main.go
    go build -ldflags "-X main.build=$(git rev-parse --short HEAD)" -o "$ISSUER_HOME/bin/notifications" ./cmd/notifications/main.go
    go build -ldflags "-X main.build=$(git rev-parse --short HEAD)" -o "$ISSUER_HOME/bin/pending_publisher" ./cmd/pending_publisher/main.go
    
    # Hacer ejecutables
    chmod +x "$ISSUER_HOME/bin/"*
    
    log_success "Binarios compilados en $ISSUER_HOME/bin/"
}

# Ejecutar migraciones
run_migrations() {
    log_info "Ejecutando migraciones de base de datos..."
    
    export $(cat "$ISSUER_HOME/.env-issuer" | xargs)
    cd "$ISSUER_HOME/IsureNode-docker/Go-issuer-node"
    
    "$ISSUER_HOME/bin/migrate"
    
    log_success "Migraciones ejecutadas correctamente"
}

# Crear servicios systemd
create_systemd_services() {
    log_info "Creando servicios systemd..."
    
    # Servicio principal
    sudo tee /etc/systemd/system/issuer-platform.service > /dev/null << EOF
[Unit]
Description=Issuer Node Platform API
After=network.target postgresql.service redis.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$ISSUER_HOME/IsureNode-docker/Go-issuer-node
EnvironmentFile=$ISSUER_HOME/.env-issuer
ExecStart=$ISSUER_HOME/bin/platform
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # Servicio de notificaciones
    sudo tee /etc/systemd/system/issuer-notifications.service > /dev/null << EOF
[Unit]
Description=Issuer Node Notifications
After=network.target postgresql.service redis.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$ISSUER_HOME/IsureNode-docker/Go-issuer-node
EnvironmentFile=$ISSUER_HOME/.env-issuer
ExecStart=$ISSUER_HOME/bin/notifications
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # Servicio de publisher
    sudo tee /etc/systemd/system/issuer-publisher.service > /dev/null << EOF
[Unit]
Description=Issuer Node Pending Publisher
After=network.target postgresql.service redis.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$ISSUER_HOME/IsureNode-docker/Go-issuer-node
EnvironmentFile=$ISSUER_HOME/.env-issuer
ExecStart=$ISSUER_HOME/bin/pending_publisher
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # Recargar systemd
    sudo systemctl daemon-reload
    
    log_success "Servicios systemd creados"
}

# Instalación principal
main() {
    log_info "Iniciando instalación del Issuer Node en modo nativo"
    
    check_dependencies
    setup_directory
    setup_database
    generate_config
    generate_resolver_config
    build_binaries
    run_migrations
    create_systemd_services
    
    log_success "¡Instalación completada!"
    log_info "Usa los siguientes comandos para gestionar el servicio:"
    echo "  sudo systemctl enable --now issuer-platform"
    echo "  sudo systemctl enable --now issuer-notifications" 
    echo "  sudo systemctl enable --now issuer-publisher"
    echo ""
    log_info "Para ver logs: journalctl -u issuer-platform -f"
    log_info "API disponible en: http://localhost:3001"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi