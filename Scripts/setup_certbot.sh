#!/bin/bash

read -p "Enter your domain (e.g., panel.example.com): " domain

echo "Updating packages and installing Certbot..."
sudo apt update && sudo apt install -y certbot python3-certbot-nginx

echo "Obtaining SSL certificate for $domain using Certbot with Nginx..."
sudo certbot certonly --nginx -d "$domain"

echo "SSL certificate request complete for $domain."