#!/bin/sh

err() {
    echo "$@"
    exit 1
}

latest_ver() {
    lv_asset=$(curl -Ls \
                  -H 'Accept: application/vnd.github+json' \
                  -H 'X-GitHub-Api-Version: 2026-03-10' \
                  https://api.github.com/repos/munastronaut/zon2tct/releases/latest?per_page=1)

    [ -n "$lv_asset" ] || err 'failed to find latest version'

    echo "$lv_asset" | sed -n 's/.*"tag_name": "\(.*\)".*/\1/p'
}

arch() {
    a_arch=$(uname -m)

    case "$a_arch" in
        x86_64)        a_arch="x86_64";;
        arm64|aarch64) a_arch="aarch64";;
    esac

    echo "$a_arch"
}

os() {
    o_os=$(uname -s | tr '[:upper:]' '[:lower:]')

    case "$o_os" in
        linux)  o_os="linux";;
        darwin) o_os="macos";;
    esac

    echo "$o_os"
}

# first arg: arch
# second arg: os
# third arg: ver
install_inner() {
    i_arg_arch=$1
    i_arg_os=$2
    i_arg_ver=$3

    i_asset="zon2tct-$i_arg_arch-$i_arg_os-$i_arg_ver.tar.gz"
    i_link="https://github.com/munastronaut/zon2tct/releases/latest/download/$i_asset"

    if command -v wget > /dev/null 2>&1; then
        wget --quiet --max-redirect 5 --output-document=zon2tct.tar.gz "$i_link" || return 0
    else
        curl --location --silent --max-redirs 5 --output zon2tct.tar.gz "$i_link" || return 0
    fi

    mkdir -p "$HOME/.zon2tct"
    tar -xzf zon2tct.tar.gz -C "$HOME/.zon2tct"
    chmod +x "$HOME/.zon2tct/zon2tct"
    rm zon2tct.tar.gz
}

install() {
    install_inner "$1" "$2" "$3" || err 'failed to install zon2tct'
}

# handles environment stuff
environ() {
    env_config_file=''

    case "$SHELL" in
        *fish)
            env_config_file="$HOME/.config/fish/config.fish"
            ;;
        *zsh)
            if [ -f "$HOME/.zshenv" ]; then
                env_config_file="$HOME/.zshenv"
            elif [ -f "$HOME/.zprofile" ]; then
                env_config_file="$HOME/.zprofile"
            else
                env_config_file="$HOME/.zshrc"
            fi
            ;;
        *)
            if [ -f "$HOME/.bashrc" ]; then
                env_config_file="$HOME/.bashrc"
            elif [ -f "$HOME/.profile" ]; then
                env_config_file="$HOME/.profile"
            else
                env_config_file=''
            fi
            ;;
    esac

    if [ -n "$env_config_file" ]; then
        if grep -q 'Z2T_INSTALL' "$env_config_file"; then
            exit 0
        fi

        case "$SHELL" in
            *fish)
                {
                    echo
                    echo '# zon2tct'
                    echo 'set -gx Z2T_INSTALL "$HOME/.zon2tct"'
                    echo 'set -gx PATH $PATH "$Z2T_INSTALL"'
                } >> "$env_config_file"
                echo "restart fish or run 'source $env_config_file' to start using zon2tct"
                ;;
            *)
                {
                    echo
                    echo '# zon2tct'
                    echo 'export Z2T_INSTALL="$HOME/.zon2tct"'
                    echo 'export PATH="$PATH:$Z2T_INSTALL"'
                } >> "$env_config_file"
                echo "run 'source $env_config_file' to start using zon2tct"
                ;;
        esac
    else
        echo 'failed to find a suitable shell startup file'
        echo "please add the following lines to your shell's startup script"

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

main() {
    arch=$(arch)
    os=$(os)
    latest_ver=$(latest_ver)

    install "$arch" "$os" "$latest_ver"
    environ
}

main
