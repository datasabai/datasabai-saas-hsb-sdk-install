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
# Clone Hubsabai Distribution Repository
# -------------------------
REPO_URL="https://Datasabai@dev.azure.com/datasabai/Hubsabai/_git/hubsabai-distribution"
REPO_DIR="$HOME/hubsabai-distribution"

if [ -d "$REPO_DIR" ]; then
  echo "📁 Hubsabai distribution folder already exists at $REPO_DIR"
  echo "🔄 Pulling latest changes..."
  cd "$REPO_DIR" && git pull
else
  echo "📦 Cloning Hubsabai distribution repository..."
  git clone "$REPO_URL" "$REPO_DIR"
  if [ $? -eq 0 ]; then
    echo "✅ Repository cloned successfully to $REPO_DIR"
  else
    echo "⚠️ Failed to clone repository. You may need to authenticate."
  fi
fi

# -------------------------
# Azure Artifacts - Hubsabai VS Code Extension
# -------------------------
if az artifacts --help >/dev/null 2>&1; then
  echo "📦 Fetching latest Hubsabai VS Code extension version..."
  
  # Utiliser az devops invoke pour récupérer les versions via l'API REST
  LATEST_VERSION=$(az devops invoke \
    --area packaging \
    --resource versions \
    --route-parameters project=3cfd82fb-e192-45a2-bc79-bb40b999acec feedId=hubsabai-vscode packageId=hubsabai-vscode-extension \
    --org https://dev.azure.com/datasabai/ \
    --api-version 7.1 \
    --query "value[-1].version" \
    --output tsv 2>&1 | grep -v "^WARNING" | grep -v "^ERROR" | tail -1 || echo "")
  
  if [ -z "$LATEST_VERSION" ] || [[ "$LATEST_VERSION" == *"error"* ]] || [[ "$LATEST_VERSION" == *"<!DOCTYPE"* ]]; then
    echo "⚠️ Could not fetch latest version automatically, using default: 1.3.7"
    LATEST_VERSION="1.3.7"
  else
    echo "✅ Latest version found: $LATEST_VERSION"
  fi
  
  echo "📥 Downloading Hubsabai VS Code extension v${LATEST_VERSION}..."
  
  TEMP_DIR=$(mktemp -d)
  
  if az artifacts universal download \
    --organization "https://dev.azure.com/datasabai/" \
    --project "3cfd82fb-e192-45a2-bc79-bb40b999acec" \
    --scope project \
    --feed "hubsabai-vscode" \
    --name "hubsabai-vscode-extension" \
    --version "$LATEST_VERSION" \
    --path "$TEMP_DIR"; then
    
    echo "✅ Successfully downloaded extension v${LATEST_VERSION}"
    
    # Installer l'extension VS Code si un fichier .vsix est trouvé
    if ls "$TEMP_DIR"/*.vsix >/dev/null 2>&1; then
      for vsix in "$TEMP_DIR"/*.vsix; do
        echo "📦 Installing VS Code extension: $(basename "$vsix")"
        code --install-extension "$vsix" --force
      done
    fi
  else
    echo "⚠️ Failed to download extension v${LATEST_VERSION}"
  fi
  
  rm -rf "$TEMP_DIR"
else
  echo "⚠️ Azure Artifacts CLI not available (azure-devops extension missing?)"
fi

echo "✅ SDK installation completed successfully"
