#!/usr/bin/env bash
set -Eeo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Installation paths
INSTALL_DIR="${HOME}/bin"
CONFIG_DIR="${HOME}/.config/gimme"
CONFIG_FILE="${CONFIG_DIR}/config"

# Banner
show_banner() {
    echo -e "${CYAN}"
    cat << 'BANNER'
   _____ _____ __  __ __  __ ______ 
  / ____|_   _|  \/  |  \/  |  ____|
 | |  __  | | | \  / | \  / | |__   
 | | |_ | | | | |\/| | |\/| |  __|  
 | |__| |_| |_| |  | | |  | | |____ 
  \_____|_____|_|  |_|_|  |_|______|
                                     
BANNER
    echo -e "${NC}"
    echo -e "${GREEN}Welcome to GIMME - Your Infrastructure Swiss Army Knife!${NC}"
    echo ""
    echo -e "${BLUE}GIMME is a powerful CLI tool for managing and querying your infrastructure.${NC}"
    echo ""
    echo "Features:"
    echo "  • Query node metadata (MAC, IP, hostname, etc.)"
    echo "  • Search and filter nodes by labels"
    echo "  • Check Kubernetes cluster status"
    echo "  • Find offline nodes across all clusters"
    echo "  • Identify oldest nodes"
    echo "  • SSH to nodes for hardware info"
    echo "  • Nautobot integration (optional)"
    echo ""
}

# Check dependencies
check_dependencies() {
    echo -e "${YELLOW}Checking dependencies...${NC}"
    
    local missing_deps=()
    
    # Required dependencies
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if ! command -v kubectl &> /dev/null; then
        echo -e "${YELLOW}  ⚠ kubectl not found (optional - needed for k8s features)${NC}"
    fi
    
    if ! command -v python3 &> /dev/null; then
        missing_deps+=("python3")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${RED}Error: Missing required dependencies: ${missing_deps[*]}${NC}"
        echo ""
        echo "Install them with:"
        echo "  Ubuntu/Debian: sudo apt install ${missing_deps[*]}"
        echo "  MacOS: brew install ${missing_deps[*]}"
        exit 1
    fi
    
    echo -e "${GREEN}  ✓ All required dependencies found${NC}"
}

# Prompt user
prompt() {
    local question="$1"
    local default="$2"
    local response
    
    if [ -n "$default" ]; then
        read -p "$(echo -e ${CYAN}${question}${NC}) [${default}]: " response
        echo "${response:-$default}"
    else
        read -p "$(echo -e ${CYAN}${question}${NC}): " response
        echo "$response"
    fi
}

# Prompt yes/no
prompt_yn() {
    local question="$1"
    local default="${2:-n}"
    local prompt_text
    
    if [ "$default" = "y" ]; then
        prompt_text="[Y/n]"
    else
        prompt_text="[y/N]"
    fi
    
    while true; do
        read -p "$(echo -e ${CYAN}${question}${NC}) ${prompt_text}: " response
        response="${response:-$default}"
        case "$response" in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

# Setup directories
setup_directories() {
    echo ""
    echo -e "${YELLOW}Setting up directories...${NC}"
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$CONFIG_DIR"
    
    # Check if ~/bin is in PATH
    if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
        echo -e "${YELLOW}  ⚠ $HOME/bin is not in your PATH${NC}"
        if prompt_yn "Add $HOME/bin to PATH in ~/.bashrc?" "y"; then
            echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
            echo -e "${GREEN}  ✓ Added to ~/.bashrc (restart shell or run: source ~/.bashrc)${NC}"
        fi
    fi
    
    echo -e "${GREEN}  ✓ Directories created${NC}"
}

# Configure Matchbox
configure_matchbox() {
    echo ""
    echo -e "${YELLOW}=== Matchbox Configuration ===${NC}"
    echo "Gimme reads node metadata from Matchbox JSON files."
    echo ""
    
    local default_matchbox="$HOME/matchbox/groups"
    local matchbox_dir
    
    matchbox_dir=$(prompt "Enter Matchbox groups directory path" "$default_matchbox")
    
    if [ ! -d "$matchbox_dir" ]; then
        echo -e "${YELLOW}  ⚠ Directory does not exist yet: $matchbox_dir${NC}"
        if ! prompt_yn "Continue anyway?" "y"; then
            echo "Please create the directory and re-run setup."
            exit 1
        fi
    fi
    
    echo "MATCHBOX_DIR=\"$matchbox_dir\"" >> "$CONFIG_FILE"
    echo -e "${GREEN}  ✓ Matchbox configured${NC}"
}

# Configure Nautobot
configure_nautobot() {
    echo ""
    echo -e "${YELLOW}=== Nautobot Configuration (Optional) ===${NC}"
    echo "Nautobot integration allows you to query device status, rack location, and notes."
    echo ""
    
    if ! prompt_yn "Do you want to configure Nautobot integration?" "n"; then
        echo -e "${BLUE}  ⏭  Skipping Nautobot setup${NC}"
        return 0
    fi
    
    echo ""
    local nautobot_url
    local nautobot_token
    
    nautobot_url=$(prompt "Enter Nautobot URL (e.g., https://nautobot.example.com)")
    
    if [ -z "$nautobot_url" ]; then
        echo -e "${YELLOW}  ⏭  Skipping Nautobot (no URL provided)${NC}"
        return 0
    fi
    
    nautobot_token=$(prompt "Enter Nautobot API token")
    
    if [ -z "$nautobot_token" ]; then
        echo -e "${YELLOW}  ⏭  Skipping Nautobot (no token provided)${NC}"
        return 0
    fi
    
    echo "export NAUTOBOT_URL=\"$nautobot_url\"" >> "$CONFIG_FILE"
    echo "export NAUTOBOT_TOKEN=\"$nautobot_token\"" >> "$CONFIG_FILE"
    
    # Check if pynautobot is installed
    if python3 -c "import pynautobot" 2>/dev/null; then
        echo -e "${GREEN}  ✓ pynautobot already installed${NC}"
    else
        echo ""
        echo -e "${YELLOW}  ⚠ pynautobot Python library not found${NC}"
        if prompt_yn "Install pynautobot now?" "y"; then
            echo "  Installing pynautobot..."
            
            # Try installation with proper output handling
            local pip_output
            local install_success=false
            
            # Method 1: pip3 with --break-system-packages (Ubuntu 24.04+)
            if pip_output=$(pip3 install --user --break-system-packages pynautobot 2>&1); then
                install_success=true
            # Method 2: python3 -m pip with --break-system-packages
            elif pip_output=$(python3 -m pip install --user --break-system-packages pynautobot 2>&1); then
                install_success=true
            # Method 3: Regular pip3 --user (older systems)
            elif pip_output=$(pip3 install --user pynautobot 2>&1); then
                install_success=true
            # Method 4: python3 -m pip
            elif pip_output=$(python3 -m pip install --user pynautobot 2>&1); then
                install_success=true
            fi
            
            # Verify installation actually worked
            if $install_success && python3 -c "import pynautobot" 2>/dev/null; then
                echo -e "${GREEN}  ✓ pynautobot installed successfully${NC}"
            else
                echo -e "${RED}  ✗ Failed to install pynautobot${NC}"
                echo ""
                echo "Installation output:"
                echo "$pip_output"
                echo ""
                echo "Please try installing manually:"
                echo "  pip3 install --user --break-system-packages pynautobot"
                echo ""
                echo "Nautobot features will be unavailable until pynautobot is installed."
                echo ""
                if ! prompt_yn "Continue installation anyway?" "y"; then
                    exit 1
                fi
            fi
        fi
    fi
    
    echo -e "${GREEN}  ✓ Nautobot configured${NC}"
}

# Configure kubectl timeout
configure_kubectl() {
    echo ""
    echo -e "${YELLOW}=== Kubectl Configuration ===${NC}"
    echo "Set default timeout for kubectl commands (e.g., 5s, 10s, 30s)"
    echo ""
    
    local timeout
    timeout=$(prompt "Kubectl timeout" "5s")
    
    echo "export GIMME_KUBECTL_TIMEOUT=\"$timeout\"" >> "$CONFIG_FILE"
    echo -e "${GREEN}  ✓ Kubectl timeout set to $timeout${NC}"
}

# Install scripts
install_scripts() {
    echo ""
    echo -e "${YELLOW}Installing scripts...${NC}"
    
    # Copy gimme
    if [ -f "bin/gimme" ]; then
        cp bin/gimme "$INSTALL_DIR/gimme"
        chmod +x "$INSTALL_DIR/gimme"
        echo -e "${GREEN}  ✓ Installed gimme${NC}"
    else
        echo -e "${RED}  ✗ bin/gimme not found!${NC}"
        exit 1
    fi
    
    # Copy gimme-nauto if it exists
    if [ -f "bin/gimme-nauto" ]; then
        cp bin/gimme-nauto "$INSTALL_DIR/gimme-nauto"
        chmod +x "$INSTALL_DIR/gimme-nauto"
        echo -e "${GREEN}  ✓ Installed gimme-nauto${NC}"
    fi
}

# Add config to bashrc
setup_bashrc() {
    echo ""
    if prompt_yn "Add gimme configuration to ~/.bashrc?" "y"; then
        if ! grep -q "# GIMME configuration" ~/.bashrc; then
            cat >> ~/.bashrc << BASHRC_EOF

# GIMME configuration
if [ -f "${CONFIG_FILE}" ]; then
    source "${CONFIG_FILE}"
fi
BASHRC_EOF
            echo -e "${GREEN}  ✓ Added to ~/.bashrc${NC}"
        else
            echo -e "${BLUE}  ⏭  Already in ~/.bashrc${NC}"
        fi
    fi
}

# Show completion message
show_completion() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                  Installation Complete! 🎉                 ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Quick Start:${NC}"
    echo ""
    echo "  # Reload your shell configuration"
    echo "  source ~/.bashrc"
    echo ""
    echo "  # Try these commands:"
    echo "  gimme list-fields"
    echo "  gimme mac <node>"
    echo "  gimme ip <node>"
    echo "  gimme k8s <node>"
    echo "  gimme offline"
    echo "  gimme oldest"
    
    if grep -q "NAUTOBOT_URL" "$CONFIG_FILE" 2>/dev/null; then
        echo "  gimme nauto status <node>"
    fi
    
    echo ""
    echo -e "${CYAN}Configuration:${NC}"
    echo "  Config file: $CONFIG_FILE"
    echo "  Installed to: $INSTALL_DIR"
    echo ""
    echo -e "${CYAN}Documentation:${NC}"
    echo "  See README.md for full documentation"
    echo ""
    echo -e "${YELLOW}Don't forget to run: ${GREEN}source ~/.bashrc${NC}"
    echo ""
}

# Main installation flow
main() {
    show_banner
    
    echo -e "${CYAN}This wizard will help you set up gimme.${NC}"
    echo ""
    
    if ! prompt_yn "Continue with installation?" "y"; then
        echo "Installation cancelled."
        exit 0
    fi
    
    check_dependencies
    setup_directories
    
    # Create config file
    echo "# GIMME Configuration" > "$CONFIG_FILE"
    echo "# Generated on $(date)" >> "$CONFIG_FILE"
    echo "" >> "$CONFIG_FILE"
    
    configure_matchbox
    configure_nautobot
    configure_kubectl
    
    install_scripts
    setup_bashrc
    
    show_completion
}

# Run main
main
