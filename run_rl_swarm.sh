#!/bin/bash

# Set the root directory to the current working directory
ROOT=$PWD

# Export environment variables
export PUB_MULTI_ADDRS
export PEER_MULTI_ADDRS
export HOST_MULTI_ADDRS
export IDENTITY_PATH
export CONNECT_TO_TESTNET
export ORG_ID
export HF_HUB_DOWNLOAD_TIMEOUT=120

# Set default values for environment variables if not already defined
DEFAULT_PUB_MULTI_ADDRS=""
PUB_MULTI_ADDRS=${PUB_MULTI_ADDRS:-$DEFAULT_PUB_MULTI_ADDRS}

DEFAULT_PEER_MULTI_ADDRS="/ip4/38.101.215.13/tcp/30002/p2p/QmQ2gEXoPJg6iMBSUFWGzAabS2VhnzuS782Y637hGjfsRJ"
PEER_MULTI_ADDRS=${PEER_MULTI_ADDRS:-$DEFAULT_PEER_MULTI_ADDRS}

DEFAULT_HOST_MULTI_ADDRS="/ip4/0.0.0.0/tcp/38331"
HOST_MULTI_ADDRS=${HOST_MULTI_ADDRS:-$DEFAULT_HOST_MULTI_ADDRS}

DEFAULT_IDENTITY_PATH="$ROOT"/swarm.pem
IDENTITY_PATH=${IDENTITY_PATH:-$DEFAULT_IDENTITY_PATH}

# Prompt user to connect to Testnet
while true; do
    read -p "Would you like to connect to the Testnet? [Y/n] " yn
    yn=${yn:-Y}
    case $yn in
        [Yy]* ) CONNECT_TO_TESTNET=True && break;;
        [Nn]* ) CONNECT_TO_TESTNET=False && break;;
        * ) echo ">>> Please answer yes or no.";;
    esac
done

if [ "$CONNECT_TO_TESTNET" = "True" ]; then
    echo "Please login to create an Ethereum Server Wallet"
    cd modal-login
    source ~/.bashrc
    
    # Install Yarn if not present
    if ! command -v yarn >/dev/null 2>&1; then
        echo "Yarn is not installed. Installing Yarn..."
        curl -o- -L https://yarnpkg.com/install.sh | sh
        echo 'export PATH="$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin:$PATH"' >> ~/.bashrc
        source ~/.bashrc
    fi
    yarn install

    # Start the development server in the background
    echo "Starting the development server..."
    yarn next dev > server.log 2>&1 &
    SERVER_PID=$!
    
    echo "Waiting for server to start..."
    MAX_WAIT=60
    counter=0
    while [ $counter -lt $MAX_WAIT ]; do
        if grep -q "Local:        http://localhost:" server.log; then
            PORT=$(grep "Local:        http://localhost:" server.log | sed -n 's/.*http:\/\/localhost:\([0-9]*\).*/\1/p')
            if [ -n "$PORT" ]; then
                echo "Server is running on port $PORT"
                break
            fi
        fi
        sleep 1
        counter=$((counter + 1))
    done
    
    if [ $counter -eq $MAX_WAIT ]; then
        echo "Timeout waiting for server to start."
        echo "Contents of server.log:"
        cat server.log
        kill $SERVER_PID 2>/dev/null || true
        exit 1
    fi

    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
    
    print_step() {
        echo -e "\n${BLUE}${BOLD}Step $1: $2${NC}"
    }
    
    check_success() {
        if [ $? -eq 0 ]; then
            echo -e "${GREEN} ^|^s Success!${NC}"
        else
            echo -e "${RED} ^|^w Failed! Please check errors above and try again.${NC}"
            exit 1
        fi
    }
    
    print_step 1 "Detecting system architecture"
    ARCH=$(uname -m)
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    if [ "$ARCH" = "x86_64" ]; then
        NGROK_ARCH="amd64"
        echo "Detected x86_64 architecture"
    elif [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then
        NGROK_ARCH="arm64"
        echo "Detected ARM64 architecture"
    elif [[ "$ARCH" == arm* ]]; then
        NGROK_ARCH="arm"
        echo "Detected ARM architecture"
    else
        echo -e "${RED}Unsupported architecture: $ARCH${NC}"
        exit 1
    fi
    
    print_step 2 "Downloading and installing ngrok"
    echo -e "Downloading ngrok for $OS-$NGROK_ARCH..."
    cd ..
    echo -e "\nWaiting for you to complete the login process..."
    while [ ! -f "modal-login/temp-data/userData.json" ]; do
        sleep 5
    done
    echo -e "\n${GREEN}${BOLD} ^|^s Success! userData.json found. Proceeding...${NC}"

    # Extract ORG_ID from userData.json
    ORG_ID=$(awk 'BEGIN { FS = "\"" } !/^[ \t]*[{}]/ { print $(NF - 1); exit }' modal-login/temp-data/userData.json)
    echo "ORG_ID set to: $ORG_ID"

    # Cleanup function for graceful shutdown
    cleanup() {
        echo "Shutting down server and ngrok..."
        kill $SERVER_PID 2>/dev/null || true
        kill $NGROK_PID 2>/dev/null || true
        exit 0
    }

    trap cleanup INT
fi

# Install Python requirements
echo "Getting requirements..."
pip install -r "$ROOT"/requirements-hivemind.txt > /dev/null
pip install -r "$ROOT"/requirements.txt > /dev/null

# Determine config path based on hardware
if ! which nvidia-smi; then
    CONFIG_PATH="$ROOT/hivemind_exp/configs/mac/grpo-qwen-2.5-0.5b-deepseek-r1.yaml"
elif [ -n "$CPU_ONLY" ]; then
    CONFIG_PATH="$ROOT/hivemind_exp/configs/mac/grpo-qwen-2.5-0.5b-deepseek-r1.yaml"
else
    pip install -r "$ROOT"/requirements_gpu.txt > /dev/null
    CONFIG_PATH="$ROOT/hivemind_exp/configs/gpu/grpo-qwen-2.5-0.5b-deepseek-r1.yaml"
fi

echo ">> Done!"
echo ""

# Handle Hugging Face token
if [ -n "${HF_TOKEN}" ]; then
    HUGGINGFACE_ACCESS_TOKEN=${HF_TOKEN}
else
    read -p "Would you like to push models you train in the RL swarm to the Hugging Face Hub? [y/N] " yn
    yn=${yn:-N}
    case $yn in
        [Yy]* ) read -p "Enter your Hugging Face access token: " HUGGINGFACE_ACCESS_TOKEN;;
        [Nn]* ) HUGGINGFACE_ACCESS_TOKEN="None";;
        * ) echo ">>> No answer was given, so NO models will be pushed to Hugging Face Hub" && HUGGINGFACE_ACCESS_TOKEN="None";;
    esac
fi

echo ""
echo "Good luck in the swarm!"

# Run the Python training script with appropriate parameters
if [ -n "$ORG_ID" ]; then
    python -m hivemind_exp.gsm8k.train_single_gpu \
        --hf_token "$HUGGINGFACE_ACCESS_TOKEN" \
        --identity_path "$IDENTITY_PATH" \
        --modal_org_id "$ORG_ID" \
        --config "$CONFIG_PATH"
else
    python -m hivemind_exp.gsm8k.train_single_gpu \
        --hf_token "$HUGGINGFACE_ACCESS_TOKEN" \
        --identity_path "$IDENTITY_PATH" \
        --public_maddr "$PUB_MULTI_ADDRS" \
        --initial_peers "$PEER_MULTI_ADDRS" \
        --host_maddr "$HOST_MULTI_ADDRS" \
        --config "$CONFIG_PATH"
fi

wait
