#!/bin/bash

read -rp "Enter your domain (e.g., panel.example.com): " domain

if [[ -z "$domain" ]]; then
  echo "Domain name cannot be empty. Exiting."
  exit 1
fi

echo "Updating packages and installing Certbot with Nginx plugin..."
sudo apt update
sudo apt install -y certbot python3-certbot-nginx

if ! command -v nginx >/dev/null 2>&1; then
  echo "Nginx is not installed. Please install Nginx before running this script."
  exit 1
fi

sudo systemctl status nginx >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo "Nginx is not running. Starting Nginx..."
  sudo systemctl start nginx
fi

echo "Obtaining and installing SSL certificate for $domain using Certbot with Nginx..."
sudo certbot --nginx -d "$domain"

echo "Reloading Nginx..."
sudo systemctl reload nginx

echo "SSL certificate setup complete for $domain."