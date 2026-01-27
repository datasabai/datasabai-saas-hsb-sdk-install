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
# Git - Latest Version
# -------------------------
echo "📦 Updating Git to latest version..."
sudo add-apt-repository ppa:git-core/ppa -y >/dev/null 2>&1
sudo apt update >/dev/null 2>&1
sudo apt install -y git >/dev/null 2>&1
echo "✅ Git updated: $(git --version)"

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
# Clone Hubsabai Distribution Repository (skeleton structure)
# -------------------------
REPO_URL="https://dev.azure.com/datasabai/Hubsabai/_git/hubsabai-distribution"
REPO_DIR="$HOME/hubsabai"

if [ ! -d "$REPO_DIR" ]; then
  echo "📦 Cloning Hubsabai distribution repository skeleton..."
  
  # Configurer Git pour utiliser Azure DevOps credential helper
  git config --global credential.helper store
  
  # Obtenir un token d'accès depuis Azure CLI
  AZURE_DEVOPS_TOKEN=$(az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query accessToken --output tsv)
  
  if [ -n "$AZURE_DEVOPS_TOKEN" ]; then
    # Cloner avec le token dans l'URL
    git clone "https://token:${AZURE_DEVOPS_TOKEN}@dev.azure.com/datasabai/Hubsabai/_git/hubsabai-distribution" "$REPO_DIR"
    
    if [ $? -eq 0 ]; then
      echo "✅ Repository skeleton cloned successfully to $REPO_DIR"
      
      # Supprimer le dossier .git pour désynchroniser (c'est juste un squelette)
      echo "🔓 Removing Git tracking (this is a skeleton, not for commits)..."
      rm -rf "$REPO_DIR/.git"
      echo "✅ Repository desynchronized - ready for development"
    else
      echo "⚠️ Failed to clone repository"
    fi
  else
    echo "⚠️ Could not get Azure DevOps access token"
  fi
else
  echo "✅ Hubsabai development folder already exists at $REPO_DIR"
fi

# -------------------------
# Azure Artifacts - Hubsabai VS Code Extension
# -------------------------
if az artifacts --help >/dev/null 2>&1; then
  echo "📦 Fetching latest Hubsabai VS Code extension version..."
  
  # Récupérer le GUID du package
  PACKAGE_ID=$(az devops invoke \
    --area packaging \
    --resource packages \
    --route-parameters project=3cfd82fb-e192-45a2-bc79-bb40b999acec feedId=hubsabai-vscode protocolType=UPack \
    --org https://dev.azure.com/datasabai/ \
    --api-version 7.1 \
    --query "value[?name=='hubsabai-vscode-extension'].id" \
    --output tsv 2>&1)
  
  if [ -n "$PACKAGE_ID" ]; then
    # Récupérer la dernière version avec le GUID
    LATEST_VERSION=$(az devops invoke \
      --area packaging \
      --resource versions \
      --route-parameters project=3cfd82fb-e192-45a2-bc79-bb40b999acec feedId=hubsabai-vscode packageId="$PACKAGE_ID" \
      --org https://dev.azure.com/datasabai/ \
      --api-version 7.1 \
      --query "value[0].version" \
      --output tsv 2>&1)
    
    echo "✅ Latest version found: $LATEST_VERSION"
  else
    echo "⚠️ Could not fetch package ID, using default version: 1.3.7"
    LATEST_VERSION="1.3.7"
  fi
  
  echo "📥 Downloading Hubsabai VS Code extension v${LATEST_VERSION}..."
  
  # Créer le répertoire .vscode dans le projet hubsabai
  VSCODE_DIR="$REPO_DIR/.vscode"
  mkdir -p "$VSCODE_DIR"
  
  if az artifacts universal download \
    --organization "https://dev.azure.com/datasabai/" \
    --project "3cfd82fb-e192-45a2-bc79-bb40b999acec" \
    --scope project \
    --feed "hubsabai-vscode" \
    --name "hubsabai-vscode-extension" \
    --version "$LATEST_VERSION" \
    --path "$VSCODE_DIR"; then
    
    echo "✅ Successfully downloaded extension v${LATEST_VERSION} to $VSCODE_DIR"
    
    # Installer l'extension VS Code si un fichier .vsix est trouvé
    if ls "$VSCODE_DIR"/*.vsix >/dev/null 2>&1; then
      for vsix in "$VSCODE_DIR"/*.vsix; do
        echo "📦 Installing VS Code extension: $(basename "$vsix")"
        code --install-extension "$vsix" --force
      done
    fi
  else
    echo "⚠️ Failed to download extension v${LATEST_VERSION}"
  fi
else
  echo "⚠️ Azure Artifacts CLI not available (azure-devops extension missing?)"
fi

# -------------------------
# Download Hubsabai JAR artifacts
# -------------------------
echo "📦 Downloading Hubsabai JAR artifacts..."

# Créer le répertoire bin dans le projet hubsabai
BIN_DIR="$REPO_DIR/bin"
mkdir -p "$BIN_DIR"

# Configurer Maven pour Azure Artifacts
MAVEN_SETTINGS="$HOME/.m2/settings.xml"
mkdir -p "$HOME/.m2"

# Générer un PAT (Personal Access Token) depuis Azure CLI
AZURE_DEVOPS_PAT=$(az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query accessToken --output tsv)

if [ -n "$AZURE_DEVOPS_PAT" ]; then
  # Créer/Mettre à jour settings.xml avec les credentials Azure Artifacts
  cat > "$MAVEN_SETTINGS" <<EOF
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 https://maven.apache.org/xsd/settings-1.0.0.xsd">
  <servers>
    <server>
      <id>hubsabai-maven</id>
      <username>datasabai</username>
      <password>${AZURE_DEVOPS_PAT}</password>
    </server>
  </servers>
  <profiles>
    <profile>
      <id>azure-artifacts</id>
      <repositories>
        <repository>
          <id>hubsabai-maven</id>
          <url>https://pkgs.dev.azure.com/datasabai/Hubsabai/_packaging/hubsabai-maven/maven/v1</url>
          <releases>
            <enabled>true</enabled>
          </releases>
          <snapshots>
            <enabled>true</enabled>
          </snapshots>
        </repository>
      </repositories>
    </profile>
  </profiles>
  <activeProfiles>
    <activeProfile>azure-artifacts</activeProfile>
  </activeProfiles>
</settings>
EOF

  echo "✅ Maven settings configured for Azure Artifacts"
  
  # Télécharger sdk-app JAR
  echo "📥 Downloading sdk-app 1.0.0-SNAPSHOT..."
  mvn dependency:copy \
    -Dartifact=com.datasabai.hsb:sdk-app:1.0.0-SNAPSHOT \
    -DoutputDirectory="$BIN_DIR" \
    -s "$MAVEN_SETTINGS"
  
  if [ $? -eq 0 ]; then
    echo "✅ sdk-app downloaded to $BIN_DIR"
  else
    echo "⚠️ Failed to download sdk-app"
  fi
  
  # Télécharger integration-engine-light JAR
  echo "📥 Downloading integration-engine-light 1.0.1..."
  mvn dependency:copy \
    -Dartifact=com.datasabai.hsb:integration-engine-light:1.0.1 \
    -DoutputDirectory="$BIN_DIR" \
    -DremoteRepositories=hubsabai-maven::::https://pkgs.dev.azure.com/datasabai/Hubsabai/_packaging/hubsabai-maven/maven/v1 \
    -s "$MAVEN_SETTINGS" \
    -DremoteRepositories=hubsabai-maven::::https://pkgs.dev.azure.com/datasabai/Hubsabai/_packaging/hubsabai-maven/maven/v1 \
    -s "$MAVEN_SETTINGS" >/dev/null 2>&1
  
  if [ $? -eq 0 ]; then
    echo "✅ integration-engine-light downloaded to $BIN_DIR"
  else
    echo "⚠️ Failed to download integration-engine-light"
  fi
else
  echo "⚠️ Could not get Azure DevOps access token for Maven"
fi

echo "✅ SDK installation completed successfully"
