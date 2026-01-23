#!/usr/bin/env bash
set -e

echo "🚀 Company SDK bootstrap starting..."

# Check WSL
if ! grep -qi microsoft /proc/version; then
  echo "❌ This script must be run inside WSL"
  exit 1
fi

# Azure CLI
if ! command -v az >/dev/null; then
  echo "Installing Azure CLI..."
  curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
fi

# Azure login
echo "🔐 Azure authentication required"
az login

# Azure DevOps extension
az extension add --name azure-devops || true

# VS Code extensions
code --install-extension vscjava.vscode-java-pack --force
code --install-extension redhat.vscode-xml --force
code --install-extension vscode.json-language-features --force
code --install-extension richie5um2.vscode-json-schemas --force
code --install-extension ms-azure-devops.azure-pipelines --force
code --install-extension ms-vscode.azure-account --force
code --install-extension redhat.vscode-yaml --force

# Maven
sudo apt update
sudo apt install -y maven
az artifacts login --tool maven

echo "✅ SDK installation completed successfully"
