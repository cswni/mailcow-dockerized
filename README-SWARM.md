# mailcow-dockerized Docker Swarm Configuration

This repository provides a Docker Swarm compatible configuration for mailcow-dockerized that integrates with external MySQL, Redis services, and Traefik reverse proxy.

## Prerequisites

Before deploying mailcow in Docker Swarm mode, ensure you have:

1. **Docker Swarm initialized** on your cluster
2. **External MySQL/MariaDB service** running and accessible
3. **External Redis service** running and accessible  
4. **Traefik reverse proxy** configured in your swarm
5. **Traefik network** (`traefik-public`) created and available

## Quick Start

### 1. Prepare Configuration

Copy the example configuration and customize it:

```bash
cp mailcow-swarm.conf.example mailcow-swarm.conf
```

Edit `mailcow-swarm.conf` with your specific settings:

```bash
# Required: Set your mailcow hostname
MAILCOW_HOSTNAME=mail.example.com

# Required: Configure external MySQL connection
EXTERNAL_MYSQL_HOST=mysql-service-name
EXTERNAL_MYSQL_PORT=3306
DBNAME=mailcow
DBUSER=mailcow
DBPASS=your-secure-database-password
DBROOT=your-secure-root-password

# Required: Configure external Redis connection
EXTERNAL_REDIS_HOST=redis-service-name
EXTERNAL_REDIS_PORT=6379
REDISPASS=your-secure-redis-password

# Required: Set timezone
TZ=Europe/Berlin
```

### 2. Prepare Directory Structure and Data

Create the required directories and initialize the configuration:

```bash
# Create required directories
mkdir -p data/assets/ssl
mkdir -p data/assets/ssl-example
mkdir -p data/conf/{dovecot,postfix,nginx,rspamd,sogo,phpfpm,clamav,unbound}
mkdir -p data/web
mkdir -p data/hooks/{dovecot,postfix,rspamd,sogo,phpfpm,unbound}

# Generate basic SSL certificates (if not using Traefik SSL)
openssl req -x509 -newkey rsa:4096 -keyout data/assets/ssl-example/key.pem \
  -out data/assets/ssl-example/cert.pem -days 365 \
  -subj "/C=DE/ST=NRW/L=Willich/O=mailcow/OU=mailcow/CN=${MAILCOW_HOSTNAME}" \
  -sha256 -nodes
  
cp data/assets/ssl-example/*.pem data/assets/ssl/

# Create symlink for environment file
ln -sf mailcow-swarm.conf .env
```

### 3. External Services Setup

#### MySQL/MariaDB Setup

Your external MySQL service should have the mailcow database and user configured:

```sql
CREATE DATABASE mailcow;
CREATE USER 'mailcow'@'%' IDENTIFIED BY 'your-secure-database-password';
GRANT ALL PRIVILEGES ON mailcow.* TO 'mailcow'@'%';
FLUSH PRIVILEGES;
```

#### Redis Setup

Your external Redis service should be configured with authentication:

```
# In redis.conf
requirepass your-secure-redis-password
```

#### Traefik Network

Ensure the `traefik-public` network exists:

```bash
docker network create --driver=overlay traefik-public
```

### 4. Deploy the Stack

Deploy mailcow to your Docker Swarm:

```bash
docker stack deploy -c mailcow-swarm.yml mailcow
```

### 5. Verify Deployment

Check the status of your deployment:

```bash
# Check stack services
docker stack services mailcow

# Check service logs
docker service logs mailcow_nginx-mailcow
docker service logs mailcow_postfix-mailcow
```

## Configuration Details

### Service Architecture

The swarm configuration includes these services:

- **nginx-mailcow**: Web interface and reverse proxy (with Traefik integration)
- **postfix-mailcow**: SMTP server
- **dovecot-mailcow**: IMAP/POP3 server
- **rspamd-mailcow**: Spam filtering
- **sogo-mailcow**: Webmail interface
- **php-fpm-mailcow**: PHP backend
- **clamd-mailcow**: Antivirus scanning
- **unbound-mailcow**: DNS resolver
- **watchdog-mailcow**: Health monitoring
- **acme-mailcow**: SSL certificate management (disabled when using Traefik)
- **dockerapi-mailcow**: Docker API interface
- **olefy-mailcow**: Office document scanner
- **postfix-tlspol-mailcow**: TLS policy enforcement
- **memcached-mailcow**: Caching
- **netfilter-mailcow**: Network filtering
- **ofelia-mailcow**: Cron job scheduler

### External Dependencies

- **MySQL/MariaDB**: Removed from stack, uses external service
- **Redis**: Removed from stack, uses external service
- **Traefik**: Handles SSL termination and reverse proxy

### Network Configuration

The configuration creates an encrypted overlay network for inter-service communication:

```yaml
networks:
  mailcow-network:
    driver: overlay
    attachable: true
    driver_opts:
      encrypted: "true"
```

### Traefik Integration

Nginx service includes Traefik labels for automatic SSL and routing:

```yaml
labels:
  - traefik.enable=true
  - traefik.http.routers.mailcow-https.rule=Host(`${MAILCOW_HOSTNAME}`)
  - traefik.http.routers.mailcow-https.entrypoints=websecure
  - traefik.http.routers.mailcow-https.tls=true
  - traefik.http.routers.mailcow-https.tls.certresolver=letsencrypt
```

## Port Mapping

The following ports are exposed on swarm nodes:

- **25**: SMTP
- **465**: SMTPS  
- **587**: Submission
- **143**: IMAP
- **993**: IMAPS
- **110**: POP3
- **995**: POP3S
- **4190**: Sieve
- **19991**: Doveadm (localhost only)

HTTP/HTTPS traffic is handled by Traefik.

## Data Persistence

All persistent data is stored in Docker volumes:

- **vmail-vol-1**: Email storage
- **vmail-index-vol-1**: Email indexes
- **rspamd-vol-1**: Rspamd data
- **postfix-vol-1**: Postfix queue
- **crypt-vol-1**: Encryption keys
- **sogo-web-vol-1**: SOGo web assets
- **sogo-userdata-backup-vol-1**: SOGo backups
- **clamd-db-vol-1**: ClamAV database

## Troubleshooting

### Common Issues

1. **Services not connecting to external MySQL/Redis**
   - Verify external service hostnames resolve in swarm
   - Check firewall rules
   - Verify credentials

2. **Traefik not routing traffic**
   - Ensure `traefik-public` network exists
   - Verify Traefik labels are correct
   - Check Traefik configuration

3. **SSL/TLS issues**
   - If using Traefik SSL, ensure `SKIP_LETS_ENCRYPT=y`
   - Verify certificate configuration

### Viewing Logs

```bash
# View logs for specific service
docker service logs -f mailcow_<service-name>

# View all services in stack
docker stack services mailcow
```

### Scaling Services

```bash
# Scale a service (if stateless)
docker service scale mailcow_<service-name>=2
```

## Migration from Standalone

To migrate from a standalone mailcow installation:

1. **Backup your data**:
   ```bash
   docker-compose exec mysql-mailcow mysqldump -u root -p mailcow > mailcow_backup.sql
   ```

2. **Export volumes**:
   ```bash
   docker run --rm -v mailcow_vmail-vol-1:/source -v $(pwd):/backup alpine tar czf /backup/vmail.tar.gz -C /source .
   ```

3. **Import to external services**:
   - Import database to external MySQL
   - Restore volume data to swarm volumes

4. **Deploy swarm configuration**

## Security Considerations

- Use strong passwords for database and Redis connections
- Ensure external services are properly secured
- Use encrypted overlay networks
- Regular security updates for all components
- Monitor logs for suspicious activity

## Support

For issues specific to the swarm configuration, please check:

1. This README
2. The original mailcow documentation
3. Docker Swarm documentation
4. Traefik documentation

Remember that this is a community configuration and may require adjustments for your specific environment.