#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Company SDK bootstrap starting..."

# -------------------------
# Checks
# -------------------------
if ! grep -qi microsoft /proc/version; then
  echo "❌ This script must be run inside WSL"
  exit 1
fi

if ! command -v code >/dev/null; then
  echo "❌ VS Code is required. Open a folder using 'WSL: Open Folder in WSL'."
  exit 1
fi

# -------------------------
# Azure CLI
# -------------------------
if ! command -v az >/dev/null; then
  echo "📦 Installing Azure CLI..."
  curl -fsSL https://aka.ms/InstallAzureCLIDeb | sudo bash
fi

# Azure login (only if needed)
if ! az account show >/dev/null 2>&1; then
  echo "🔐 Azure authentication required"
  az login
else
  echo "✅ Azure already authenticated"
fi

# Azure DevOps extension
az extension add --name azure-devops >/dev/null 2>&1 || true

# -------------------------
# VS Code extensions
# -------------------------
echo "📦 Installing VS Code extensions..."

code --install-extension vscjava.vscode-java-pack --force
code --install-extension redhat.vscode-xml --force
code --install-extension eriklynd.json-tools --force
code --install-extension esbenp.prettier-vscode --force
code --install-extension ms-azure-devops.azure-pipelines --force
code --install-extension redhat.vscode-yaml --force

# -------------------------
# Java 25 (Temurin)
# -------------------------
if ! java -version 2>&1 | grep -q "Temurin" || ! java -version 2>&1 | grep -q "25"; then
  echo "☕ Installing Java 25 (Temurin)..."

  sudo apt update
  sudo apt install -y wget apt-transport-https gnupg ca-certificates

  # Supprimer l'ancien fichier adoptium.list et la clé s'ils existent
  sudo rm -f /etc/apt/sources.list.d/adoptium.list
  sudo rm -f /etc/apt/keyrings/adoptium.gpg

  sudo mkdir -p /etc/apt/keyrings
  wget -qO- https://packages.adoptium.net/artifactory/api/gpg/key/public \
    | gpg --dearmor \
    | sudo tee /etc/apt/keyrings/adoptium.gpg >/dev/null

  UBUNTU_CODENAME=$(lsb_release -cs)
  echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb ${UBUNTU_CODENAME} main" \
    | sudo tee /etc/apt/sources.list.d/adoptium.list

  sudo apt update
  sudo apt install -y temurin-25-jdk

  sudo update-alternatives --set java /usr/lib/jvm/temurin-25-jdk-amd64/bin/java
  sudo update-alternatives --set javac /usr/lib/jvm/temurin-25-jdk-amd64/bin/javac
else
  echo "✅ Java 25 already installed"
fi

java -version

# -------------------------
# Maven 3.9+
# -------------------------
MAVEN_VERSION=3.9.12
MAVEN_DIR=/opt/apache-maven-${MAVEN_VERSION}

if [ ! -d "$MAVEN_DIR" ]; then
  echo "📦 Installing Maven $MAVEN_VERSION..."
  curl -fsSL https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz \
    | sudo tar -xz -C /opt
else
  echo "✅ Maven $MAVEN_VERSION already installed"
fi

# Supprimer l'ancien lien symbolique et créer le nouveau
sudo rm -f /opt/maven
sudo ln -sf "$MAVEN_DIR" /opt/maven

sudo tee /etc/profile.d/maven.sh >/dev/null <<'EOF'
export MAVEN_HOME=/opt/maven
export PATH=$MAVEN_HOME/bin:$PATH
EOF

source /etc/profile.d/maven.sh
mvn -version

# -------------------------
# Azure DevOps configuration (required for artifacts)
# -------------------------
az devops configure --defaults organization=https://dev.azure.com/datasabai

# -------------------------
# Azure Artifacts (Maven)
# -------------------------
if az artifacts --help >/dev/null 2>&1; then
  echo "📦 Downloading latest Hubsabai VS Code extension from Azure Artifacts..."
  
  # Lister toutes les versions en utilisant l'API REST Azure DevOps
  LATEST_VERSION=$(az rest \
    --method GET \
    --uri "https://feeds.dev.azure.com/datasabai/3cfd82fb-e192-45a2-bc79-bb40b999acec/_apis/packaging/feeds/hubsabai-vscode/packages/hubsabai-vscode-extension/versions?api-version=7.1-preview.1" \
    --query "value[-1].version" \
    --output tsv 2>&1)
  
  # Vérifier si la commande a échoué (authentification ou autre erreur)
  if [ $? -ne 0 ] || [ -z "$LATEST_VERSION" ]; then
    echo "⚠️ Authentication or permission error. Attempting Azure login..."
    az login
    
    # Réessayer après authentification
    LATEST_VERSION=$(az rest \
      --method GET \
      --uri "https://feeds.dev.azure.com/datasabai/3cfd82fb-e192-45a2-bc79-bb40b999acec/_apis/packaging/feeds/hubsabai-vscode/packages/hubsabai-vscode-extension/versions?api-version=7.1-preview.1" \
      --query "value[-1].version" \
      --output tsv 2>/dev/null || echo "")
  fi
  
  if [ -n "$LATEST_VERSION" ]; then
    echo "📥 Latest version found: $LATEST_VERSION"
    
    # Télécharger l'extension
    TEMP_DIR=$(mktemp -d)
    az artifacts universal download \
      --organization "https://dev.azure.com/datasabai/" \
      --project "3cfd82fb-e192-45a2-bc79-bb40b999acec" \
      --scope project \
      --feed "hubsabai-vscode" \
      --name "hubsabai-vscode-extension" \
      --version "$LATEST_VERSION" \
      --path "$TEMP_DIR"
    
    # Installer l'extension VS Code si un fichier .vsix est trouvé
    if ls "$TEMP_DIR"/*.vsix >/dev/null 2>&1; then
      for vsix in "$TEMP_DIR"/*.vsix; do
        echo "📦 Installing VS Code extension: $(basename "$vsix")"
        code --install-extension "$vsix" --force
      done
    fi
    
    rm -rf "$TEMP_DIR"
  else
    echo "⚠️ Could not retrieve latest version of hubsabai-vscode-extension"
    echo "⚠️ Please check your Azure DevOps permissions for the hubsabai-vscode feed"
  fi
else
  echo "⚠️ Azure Artifacts CLI not available (azure-devops extension missing?)"
fi

echo "✅ SDK installation completed successfully"
