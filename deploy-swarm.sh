#!/bin/bash

# mailcow-dockerized Docker Swarm Deployment Script
# This script helps deploy mailcow in Docker Swarm mode with external MySQL and Redis

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running in swarm mode
check_swarm_mode() {
    print_info "Checking Docker Swarm mode..."
    if ! docker node ls >/dev/null 2>&1; then
        print_error "Docker Swarm is not initialized or you're not a manager node."
        print_info "Initialize swarm with: docker swarm init"
        exit 1
    fi
    print_success "Docker Swarm mode confirmed"
}

# Check if configuration exists
check_config() {
    print_info "Checking configuration..."
    if [[ ! -f "mailcow-swarm.conf" ]]; then
        print_warning "mailcow-swarm.conf not found. Creating from example..."
        if [[ -f "mailcow-swarm.conf.example" ]]; then
            cp mailcow-swarm.conf.example mailcow-swarm.conf
            print_warning "Please edit mailcow-swarm.conf with your settings before continuing"
            print_info "Required settings:"
            print_info "  - MAILCOW_HOSTNAME"
            print_info "  - EXTERNAL_MYSQL_HOST"
            print_info "  - EXTERNAL_REDIS_HOST" 
            print_info "  - Database credentials"
            print_info "  - Redis password"
            read -p "Press Enter when you have configured mailcow-swarm.conf..."
        else
            print_error "mailcow-swarm.conf.example not found!"
            exit 1
        fi
    fi
    print_success "Configuration file found"
}

# Create environment symlink
create_env_link() {
    print_info "Creating environment symlink..."
    if [[ -L ".env" ]]; then
        rm .env
    fi
    ln -sf mailcow-swarm.conf .env
    print_success "Environment symlink created"
}

# Check external networks
check_networks() {
    print_info "Checking required networks..."
    
    # Check if traefik-public network exists
    if ! docker network ls | grep -q "traefik-public"; then
        print_warning "traefik-public network not found. Creating..."
        docker network create --driver=overlay traefik-public
        print_success "traefik-public network created"
    else
        print_success "traefik-public network exists"
    fi
}

# Create required directories
create_directories() {
    print_info "Creating required directories..."
    
    directories=(
        "data/assets/ssl"
        "data/assets/ssl-example"
        "data/conf/dovecot"
        "data/conf/postfix"
        "data/conf/nginx"
        "data/conf/rspamd/override.d"
        "data/conf/rspamd/local.d"
        "data/conf/rspamd/custom"
        "data/conf/rspamd/plugins.d"
        "data/conf/rspamd/lua"
        "data/conf/sogo"
        "data/conf/phpfpm/php-fpm.d"
        "data/conf/phpfpm/php-conf.d"
        "data/conf/phpfpm/sogo-sso"
        "data/conf/phpfpm/crons"
        "data/conf/clamav"
        "data/conf/unbound"
        "data/web"
        "data/hooks/dovecot"
        "data/hooks/postfix"
        "data/hooks/rspamd"
        "data/hooks/sogo"
        "data/hooks/phpfpm"
        "data/hooks/unbound"
        "data/conf/dovecot/auth"
        "data/conf/dovecot/global_sieve_before"
        "data/conf/dovecot/global_sieve_after"
        "data/conf/rspamd/dynmaps"
        "data/conf/rspamd/meta_exporter"
        "data/web/.well-known/acme-challenge"
    )
    
    for dir in "${directories[@]}"; do
        mkdir -p "$dir"
    done
    
    print_success "Required directories created"
}

# Generate basic SSL certificates
generate_ssl() {
    print_info "Generating basic SSL certificates..."
    
    # Source the config to get MAILCOW_HOSTNAME
    source mailcow-swarm.conf
    
    if [[ ! -f "data/assets/ssl-example/cert.pem" ]]; then
        openssl req -x509 -newkey rsa:4096 \
            -keyout data/assets/ssl-example/key.pem \
            -out data/assets/ssl-example/cert.pem \
            -days 365 \
            -subj "/C=DE/ST=NRW/L=Willich/O=mailcow/OU=mailcow/CN=${MAILCOW_HOSTNAME}" \
            -sha256 -nodes
        print_success "SSL certificates generated"
    else
        print_info "SSL certificates already exist"
    fi
    
    # Copy to ssl directory if needed
    cp -n data/assets/ssl-example/*.pem data/assets/ssl/ || true
}

# Create basic configuration files
create_basic_configs() {
    print_info "Creating basic configuration files..."
    
    # Create rspamd override file if it doesn't exist
    if [[ ! -f "data/conf/rspamd/override.d/worker-controller-password.inc" ]]; then
        echo '# Placeholder' > data/conf/rspamd/override.d/worker-controller-password.inc
    fi
    
    print_success "Basic configuration files created"
}

# Validate external services connectivity
validate_external_services() {
    print_info "Validating external services connectivity..."
    
    # Source the config
    source mailcow-swarm.conf
    
    # Test MySQL connectivity
    print_info "Testing MySQL connectivity to ${EXTERNAL_MYSQL_HOST}:${EXTERNAL_MYSQL_PORT}..."
    if command -v mysql >/dev/null 2>&1; then
        if mysql -h "${EXTERNAL_MYSQL_HOST}" -P "${EXTERNAL_MYSQL_PORT}" -u "${DBUSER}" -p"${DBPASS}" -e "SELECT 1;" >/dev/null 2>&1; then
            print_success "MySQL connection successful"
        else
            print_warning "Could not connect to MySQL. Please verify credentials and network connectivity."
        fi
    else
        print_warning "MySQL client not found. Skipping connectivity test."
    fi
    
    # Test Redis connectivity
    print_info "Testing Redis connectivity to ${EXTERNAL_REDIS_HOST}:${EXTERNAL_REDIS_PORT}..."
    if command -v redis-cli >/dev/null 2>&1; then
        if redis-cli -h "${EXTERNAL_REDIS_HOST}" -p "${EXTERNAL_REDIS_PORT}" -a "${REDISPASS}" ping >/dev/null 2>&1; then
            print_success "Redis connection successful"
        else
            print_warning "Could not connect to Redis. Please verify password and network connectivity."
        fi
    else
        print_warning "Redis CLI not found. Skipping connectivity test."
    fi
}

# Deploy the stack
deploy_stack() {
    print_info "Deploying mailcow stack..."
    
    # Validate the compose file first
    if docker-compose -f mailcow-swarm.yml config >/dev/null 2>&1; then
        print_success "Docker Compose file is valid"
    else
        print_error "Docker Compose file validation failed"
        return 1
    fi
    
    # Deploy the stack
    docker stack deploy -c mailcow-swarm.yml mailcow
    print_success "mailcow stack deployed"
}

# Check deployment status
check_deployment() {
    print_info "Checking deployment status..."
    
    sleep 5
    
    echo ""
    print_info "Stack services:"
    docker stack services mailcow
    
    echo ""
    print_info "To monitor logs, use:"
    print_info "  docker service logs -f mailcow_<service-name>"
    
    echo ""
    print_info "To check service status:"
    print_info "  docker stack services mailcow"
}

# Main deployment function
main() {
    echo "=========================================="  
    print_info "mailcow-dockerized Docker Swarm Deployment"
    echo "=========================================="
    
    check_swarm_mode
    check_config
    create_env_link
    check_networks
    create_directories
    create_basic_configs
    generate_ssl
    validate_external_services
    
    echo ""
    print_warning "Ready to deploy. This will:"
    print_warning "  - Deploy mailcow services to Docker Swarm"
    print_warning "  - Use external MySQL and Redis services"
    print_warning "  - Configure Traefik integration"
    echo ""
    
    read -p "Continue with deployment? (y/N): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        deploy_stack
        check_deployment
        
        echo ""
        print_success "Deployment completed!"
        print_info "Access mailcow at: https://$(source mailcow-swarm.conf && echo $MAILCOW_HOSTNAME)"
        print_info "Default admin credentials: admin / moohoo"
        print_warning "Don't forget to change the default password!"
    else
        print_info "Deployment cancelled"
    fi
}

# Run script
main "$@"