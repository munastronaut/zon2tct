#!/usr/bin/env bash

install_latest() {
    if command -v wget >/dev/null 2>&1; then
        wget -q --show-progress --max-redirect 5 -O zon2tct.tar.gz "https://github.com/munastronaut/zon2tct/releases/latest/download/$1"
    else
        curl -L --max-redirs 5 "https://github.com/munastronaut/zon2tct/releases/latest/download/$1" -o zon2tct.tar.gz
    fi

    mkdir -p "$HOME/.zon2tct"
    tar -xzf zon2tct.tar.gz -C "$HOME/.zon2tct"
    chmod +x "$HOME/.zon2tct/zon2tct"
    rm zon2tct.tar.gz
}

work() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)        ARCH="x86_64";;
        arm64|aarch64) ARCH="aarch64";;
    esac

    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    case "$OS" in
        linux)  OS="linux";;
        darwin) OS="macos";;
    esac

    ASSET=$(curl -Ls \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2026-03-10" \
            https://api.github.com/repos/munastronaut/zon2tct/releases/latest | \
            grep -o '"name": "[^"]*' | \
            grep "$ARCH" | \
            grep "$OS" | \
            sed 's/"name": "//' | \
            tail -n 2 | \
            head -n 1)

    if [ -n "$ASSET" ]; then
        install_latest "$ASSET"
    else
        echo "could not find matching release for ${OS} with arch ${ARCH}"
        exit 1
    fi

    TARGET_FILE=""

    case "$SHELL" in
        *fish) TARGET_FILE="$HOME/.config/fish/config.fish";;
        *zsh)
            if [ -f "$HOME/.zshenv" ]; then
                TARGET_FILE="$HOME/.zshenv"
            elif [ -f "$HOME/.zprofile" ]; then
                TARGET_FILE="$HOME/.zprofile"
            else
                TARGET_FILE="$HOME/.zshrc"
            fi
            ;;
        *)
            if [ -f "$HOME/.bashrc" ]; then
                TARGET_FILE="$HOME/.bashrc"
            elif [ -f "$HOME/.profile" ]; then
                TARGET_FILE="$HOME/.profile"
            else
                TARGET_FILE=""
            fi
            ;;
    esac

    if [ -n "$TARGET_FILE" ]; then
        if grep -q 'Z2T_INSTALL' "$TARGET_FILE"; then
            echo "zon2tct environment variables are already present in $TARGET_FILE"
            exit 0
        fi

        case "$SHELL" in
            *fish)
                {
                    echo
                    echo "# zon2tct"
                    echo 'set -gx Z2T_INSTALL "$HOME/.zon2tct"'
                    echo 'set -gx PATH $PATH "$Z2T_INSTALL"'
                } >> "$TARGET_FILE"
                echo "restart fish or run 'source $TARGET_FILE' to start using zon2tct"
                ;;
            *)
                {
                    echo
                    echo "# zon2tct"
                    echo 'export Z2T_INSTALL="$HOME/.zon2tct"'
                    echo 'export PATH="$PATH:$Z2T_INSTALL"'
                } >> "$TARGET_FILE"
                echo "run 'source $TARGET_FILE' to start using zon2tct"
                ;;
        esac
    else
        echo
        echo "no suitable shell startup file found"
        echo "please add the following lines to your shell's startup script (or execute them in your current session):"
        case "$SHELL" in
            *fish)
                echo 'set -gx Z2T_INSTALL "$HOME/.zon2tct"'
                echo 'set -gx PATH $PATH "$Z2T_INSTALL"'
                ;;
            *)
                echo 'export Z2T_INSTALL="$HOME/.zon2tct"'
                echo 'export PATH="$PATH:$Z2T_INSTALL"'
                ;;
        esac
    fi
}

work
