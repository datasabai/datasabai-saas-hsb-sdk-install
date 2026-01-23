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
code --install-extension ms-vscode.azure-account --force
code --install-extension redhat.vscode-yaml --force

# -------------------------
# Java 21 (Temurin)
# -------------------------
if ! java -version 2>&1 | grep -q "21"; then
  echo "☕ Installing Java 21 (Temurin)..."

  sudo apt update
  sudo apt install -y wget apt-transport-https gnupg ca-certificates

  sudo mkdir -p /etc/apt/keyrings
  wget -qO- https://packages.adoptium.net/artifactory/api/gpg/key/public \
    | sudo tee /etc/apt/keyrings/adoptium.gpg >/dev/null

  echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb stable main" \
    | sudo tee /etc/apt/sources.list.d/adoptium.list

  sudo apt update
  sudo apt install -y temurin-21-jdk

  sudo update-alternatives --set java /usr/lib/jvm/temurin-21-jdk-amd64/bin/java
  sudo update-alternatives --set javac /usr/lib/jvm/temurin-21-jdk-amd64/bin/javac
else
  echo "✅ Java 21 already installed"
fi

java -version

# -------------------------
# Maven 3.9+
# -------------------------
MAVEN_VERSION=3.9.6
MAVEN_DIR=/opt/apache-maven-${MAVEN_VERSION}

if [ ! -d "$MAVEN_DIR" ]; then
  echo "📦 Installing Maven $MAVEN_VERSION..."
  curl -fsSL https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz \
    | sudo tar -xz -C /opt
else
  echo "✅ Maven $MAVEN_VERSION already installed"
fi

sudo ln -sf "$MAVEN_DIR" /opt/maven

sudo tee /etc/profile.d/maven.sh >/dev/null <<'EOF'
export MAVEN_HOME=/opt/maven
export PATH=$MAVEN_HOME/bin:$PATH
EOF

source /etc/profile.d/maven.sh
mvn -version

# -------------------------
# Azure Artifacts (Maven)
# -------------------------
az artifacts login --tool maven || true

echo "✅ SDK installation completed successfully"
