#!/bin/bash

# Verificar si el usuario es root
if [ "$(id -u)" -ne 0 ]; then
    echo "Este script debe ejecutarse como root. Por favor, usa sudo."
    exit 1
fi

# Actualizar el sistema
echo "Actualizando el sistema..."
apt-get update && apt-get upgrade -y

# Instalar dependencias básicas
echo "Instalando dependencias básicas..."
apt-get install -y curl wget git unzip gnupg2 software-properties-common apt-transport-https ca-certificates

# Instalar Docker
echo "Instalando Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io
    systemctl enable --now docker
    usermod -aG docker $SUDO_USER
    echo "Docker instalado correctamente."
else
    echo "Docker ya está instalado."
fi

# Instalar Docker Compose
echo "Instalando Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
    LATEST_COMPOSE=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
    curl -L "https://github.com/docker/compose/releases/download/${LATEST_COMPOSE}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
    echo "Docker Compose instalado correctamente."
else
    echo "Docker Compose ya está instalado."
fi

# Instalar Node.js y npm (para Next.js, TypeScript y Tailwind)
echo "Instalando Node.js y npm..."
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
    apt-get install -y nodejs
    echo "Node.js instalado correctamente."
else
    echo "Node.js ya está instalado."
fi

# Instalar PHP y dependencias para Laravel
echo "Instalando PHP y dependencias..."
apt-get install -y php php-cli php-fpm php-json php-pdo php-mysql php-zip php-gd php-mbstring php-curl php-xml php-bcmath php-intl

# Instalar Composer
echo "Instalando Composer..."
if ! command -v composer &> /dev/null; then
    EXPECTED_CHECKSUM="$(php -r 'copy("https://composer.github.io/installer.sig", "php://stdout");')"
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
    ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

    if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
        >&2 echo 'ERROR: Checksum del instalador de Composer no válida'
        rm composer-setup.php
        exit 1
    fi

    php composer-setup.php --install-dir=/usr/local/bin --filename=composer
    rm composer-setup.php
    echo "Composer instalado correctamente."
else
    echo "Composer ya está instalado."
fi

# Crear archivo docker-compose.yml para el entorno
echo "Creando archivo docker-compose.yml..."
cat <<EOF > docker-compose.yml
version: '3.8'

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: laravel_app
    restart: unless-stopped
    ports:
      - "8080:80"
    volumes:
      - ./:/var/www/html
    networks:
      - laravel_network
    depends_on:
      - db

  db:
    image: postgres:13
    container_name: postgres_db
    restart: unless-stopped
    environment:
      POSTGRES_DB: laravel
      POSTGRES_USER: laravel
      POSTGRES_PASSWORD: secret
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - laravel_network
    ports:
      - "5432:5432"

  nextjs:
    build:
      context: ./next-app
      dockerfile: Dockerfile
    container_name: next_app
    restart: unless-stopped
    ports:
      - "3000:3000"
    volumes:
      - ./next-app:/app
      - /app/node_modules
    networks:
      - laravel_network
    depends_on:
      - app

volumes:
  postgres_data:
    driver: local

networks:
  laravel_network:
    driver: bridge
EOF

# Crear Dockerfile para Laravel
echo "Creando Dockerfile para Laravel..."
cat <<EOF > Dockerfile
FROM php:8.1-apache

RUN apt-get update && apt-get install -y \
    libpq-dev \
    libzip-dev \
    zip \
    unzip \
    && docker-php-ext-install pdo pdo_pgsql zip

RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

RUN a2enmod rewrite

WORKDIR /var/www/html

COPY . .

RUN chown -R www-data:www-data /var/www/html/storage
RUN chown -R www-data:www-data /var/www/html/bootstrap/cache

EXPOSE 80
EOF

# Crear Dockerfile para Next.js
mkdir -p next-app
echo "Creando Dockerfile para Next.js..."
cat <<EOF > next-app/Dockerfile
FROM node:16-alpine

WORKDIR /app

COPY package*.json ./

RUN npm install

COPY . .

EXPOSE 3000

CMD ["npm", "run", "dev"]
EOF

# Crear estructura básica para Next.js con TypeScript y Tailwind
echo "Configurando proyecto Next.js con TypeScript y Tailwind..."
npx create-next-app@latest next-app --typescript --eslint
cd next-app && npm install -D tailwindcss postcss autoprefixer
npx tailwindcss init -p

# Configurar tailwind.config.js
cat <<EOF > tailwind.config.js
module.exports = {
  content: [
    "./pages/**/*.{js,ts,jsx,tsx}",
    "./components/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {},
  },
  plugins: [],
}
EOF

# Reemplazar styles/globals.css con configuración de Tailwind
cat <<EOF > styles/globals.css
@tailwind base;
@tailwind components;
@tailwind utilities;
EOF

cd ..

# Instalar Laravel
echo "Instalando Laravel..."
composer create-project --prefer-dist laravel/laravel laravel-app
mv laravel-app/* .
mv laravel-app/.* .
rmdir laravel-app

# Configurar .env para Laravel con PostgreSQL
sed -i 's/DB_CONNECTION=mysql/DB_CONNECTION=pgsql/' .env
sed -i 's/DB_HOST=127.0.0.1/DB_HOST=db/' .env
sed -i 's/DB_PORT=3306/DB_PORT=5432/' .env
sed -i 's/DB_DATABASE=laravel/DB_DATABASE=laravel/' .env
sed -i 's/DB_USERNAME=root/DB_USERNAME=laravel/' .env
sed -i 's/DB_PASSWORD=/DB_PASSWORD=secret/' .env

# Dar permisos
chmod -R 775 storage bootstrap/cache
chown -R $SUDO_USER:www-data storage bootstrap/cache

echo "¡Configuración completada!"
echo "Para iniciar el entorno, ejecuta:"
echo "docker-compose up -d"
echo ""
echo "Laravel estará disponible en: http://localhost:8080"
echo "Next.js estará disponible en: http://localhost:3000"
echo "PostgreSQL estará disponible en: localhost:5432"
