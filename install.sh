#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# 检查root权限
[[ $EUID -ne 0 ]] && echo -e "${red}致命错误: ${plain} 请使用root权限运行此脚本 \n " && exit 1

# 检查操作系统并设置发行版变量
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "无法检测系统操作系统，请联系作者!" >&2
    exit 1
fi
echo "操作系统版本: $release"

arch() {
    case "$(uname -m)" in
    x86_64 | x64 | amd64) echo 'amd64' ;;
    i*86 | x86) echo '386' ;;
    armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
    armv7* | armv7 | arm) echo 'armv7' ;;
    armv6* | armv6) echo 'armv6' ;;
    armv5* | armv5) echo 'armv5' ;;
    s390x) echo 's390x' ;;
    *) echo -e "${green}不支持的CPU架构! ${plain}" && rm -f install.sh && exit 1 ;;
    esac
}

echo "系统架构: $(arch)"

install_base() {
    case "${release}" in
    ubuntu | debian | armbian)
        apt-get update && apt-get install -y -q wget curl tar tzdata
        ;;
    centos | rhel | almalinux | rocky | ol)
        yum -y update && yum install -y -q wget curl tar tzdata
        ;;
    fedora | amzn | virtuozzo)
        dnf -y update && dnf install -y -q wget curl tar tzdata
        ;;
    arch | manjaro | parch)
        pacman -Syu && pacman -Syu --noconfirm wget curl tar tzdata
        ;;
    opensuse-tumbleweed | opensuse-leap)
        zypper refresh && zypper -q install -y wget curl tar timezone
        ;;
    alpine)
        apk update && apk add wget curl tar tzdata
        ;;
    *)
        apt-get update && apt-get install -y -q wget curl tar tzdata
        ;;
    esac
}

gen_random_string() {
    local length="$1"
    local random_string=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1)
    echo "$random_string"
}

config_after_install() {
    local existing_hasDefaultCredential=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'hasDefaultCredential: .+' | awk '{print $2}')
    local existing_webBasePath=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
    local URL_lists=(
        "https://api4.ipify.org"
        "https://ipv4.icanhazip.com"
        "https://v4.api.ipinfo.io/ip"
        "https://ipv4.myexternalip.com/raw"
        "https://4.ident.me"
        "https://check-host.net/ip"
    )
    local server_ip=""
    for ip_address in "${URL_lists[@]}"; do
        server_ip=$(curl -s --max-time 3 "${ip_address}" 2>/dev/null | tr -d '[:space:]')
        if [[ -n "${server_ip}" ]]; then
            break
        fi
    done

    if [[ ${#existing_webBasePath} -lt 4 ]]; then
        if [[ "$existing_hasDefaultCredential" == "true" ]]; then
            local config_webBasePath=$(gen_random_string 18)
            local config_username=$(gen_random_string 10)
            local config_password=$(gen_random_string 10)

            read -rp "是否自定义面板端口设置? (如果选择否，将使用随机端口) [y/n]: " config_confirm
            if [[ "${config_confirm}" == "y" || "${config_confirm}" == "Y" ]]; then
                read -rp "请设置面板端口: " config_port
                echo -e "${yellow}您的面板端口: ${config_port}${plain}"
            else
                local config_port=$(shuf -i 1024-62000 -n 1)
                echo -e "${yellow}生成的随机端口: ${config_port}${plain}"
            fi

            /usr/local/x-ui/x-ui setting -username "${config_username}" -password "${config_password}" -port "${config_port}" -webBasePath "${config_webBasePath}"
            echo -e "这是一个全新安装，为安全考虑生成随机登录信息:"
            echo -e "###############################################"
            echo -e "${green}用户名: ${config_username}${plain}"
            echo -e "${green}密码: ${config_password}${plain}"
            echo -e "${green}端口: ${config_port}${plain}"
            echo -e "${green}Web基础路径: ${config_webBasePath}${plain}"
            echo -e "${green}访问地址: http://${server_ip}:${config_port}/${config_webBasePath}${plain}"
            echo -e "###############################################"
        else
            local config_webBasePath=$(gen_random_string 18)
            echo -e "${yellow}Web基础路径缺失或太短，正在生成新的路径...${plain}"
            /usr/local/x-ui/x-ui setting -webBasePath "${config_webBasePath}"
            echo -e "${green}新的Web基础路径: ${config_webBasePath}${plain}"
            echo -e "${green}访问地址: http://${server_ip}:${existing_port}/${config_webBasePath}${plain}"
        fi
    else
        if [[ "$existing_hasDefaultCredential" == "true" ]]; then
            local config_username=$(gen_random_string 10)
            local config_password=$(gen_random_string 10)

            echo -e "${yellow}检测到默认凭证，需要进行安全更新...${plain}"
            /usr/local/x-ui/x-ui setting -username "${config_username}" -password "${config_password}"
            echo -e "已生成新的随机登录凭证:"
            echo -e "###############################################"
            echo -e "${green}用户名: ${config_username}${plain}"
            echo -e "${green}密码: ${config_password}${plain}"
            echo -e "###############################################"
        else
            echo -e "${green}用户名、密码和Web基础路径已正确设置，退出...${plain}"
        fi
    fi

    /usr/local/x-ui/x-ui migrate
}

# 选择下载镜像源
select_mirror() {
    echo -e "${yellow}请选择GitHub资源下载镜像源:${plain}"
    echo -e "1. 不使用加速 (直接访问GitHub)"
    echo -e "2. 使用国内加速镜像 https://ghfast.top/"
    echo -e "3. 自定义镜像源 (请以/结尾)"
    read -rp "请输入选择 [1-3]: " mirror_choice

    case $mirror_choice in
    1)
        echo -e "${green}已选择: 直接访问GitHub${plain}"
        MIRROR_URL=""
        ;;
    2)
        echo -e "${green}已选择: 使用国内加速镜像 https://ghfast.top/${plain}"
        MIRROR_URL="https://ghfast.top/"
        ;;
    3)
        read -rp "请输入自定义镜像源URL (以/结尾): " custom_mirror
        if [[ $custom_mirror =~ ^https?://.*/$ ]]; then
            MIRROR_URL=$custom_mirror
            echo -e "${green}已选择: 使用自定义镜像源 ${MIRROR_URL}${plain}"
        else
            echo -e "${red}镜像源格式错误，必须是以http://或https://开头且以/结尾的URL${plain}"
            exit 1
        fi
        ;;
    *)
        echo -e "${red}无效选择，使用默认选项: 直接访问GitHub${plain}"
        MIRROR_URL=""
        ;;
    esac
}

install_x-ui() {
    cd /usr/local/

    # 选择镜像源
    select_mirror

    # 下载资源
    if [ $# == 0 ]; then
        tag_version=$(curl -Ls "${MIRROR_URL}https://api.github.com/repos/ruyawwj/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$tag_version" ]]; then
            echo -e "${yellow}尝试使用IPv4获取版本...${plain}"
            tag_version=$(curl -4 -Ls "${MIRROR_URL}https://api.github.com/repos/ruyawwj/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
            if [[ ! -n "$tag_version" ]]; then
                echo -e "${red}获取x-ui版本失败，可能是由于GitHub API限制，请稍后重试${plain}"
                exit 1
            fi
        fi
        echo -e "获取到x-ui最新版本: ${tag_version}，开始安装..."
        wget --inet4-only -N -O /usr/local/x-ui-linux-$(arch).tar.gz "${MIRROR_URL}https://github.com/ruyawwj/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz"
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载x-ui失败，请确保服务器可以访问GitHub ${plain}"
            exit 1
        fi
    else
        tag_version=$1
        tag_version_numeric=${tag_version#v}
        min_version="2.3.5"

        if [[ "$(printf '%s\n' "$min_version" "$tag_version_numeric" | sort -V | head -n1)" != "$min_version" ]]; then
            echo -e "${red}请使用更新的版本 (至少v2.3.5)。停止安装。${plain}"
            exit 1
        fi

        url="${MIRROR_URL}https://github.com/ruyawwj/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz"
        echo -e "开始安装 x-ui $1"
        wget --inet4-only -N -O /usr/local/x-ui-linux-$(arch).tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 x-ui $1 失败，请检查版本是否存在 ${plain}"
            exit 1
        fi
    fi
    
    wget --inet4-only -O /usr/bin/x-ui-temp "${MIRROR_URL}https://raw.githubusercontent.com/ruyawwj/3x-ui/main/x-ui.sh"
    if [[ $? -ne 0 ]]; then
        echo -e "${red}下载x-ui.sh失败${plain}"
        exit 1
    fi

    # 停止x-ui服务并移除旧资源
    if [[ -e /usr/local/x-ui/ ]]; then
        if [[ $release == "alpine" ]]; then
            rc-service x-ui stop
        else
            systemctl stop x-ui
        fi
        rm /usr/local/x-ui/ -rf
    fi

    # 解压资源并设置权限
    tar zxvf x-ui-linux-$(arch).tar.gz
    rm x-ui-linux-$(arch).tar.gz -f
    
    cd x-ui
    chmod +x x-ui
    chmod +x x-ui.sh

    # 检查系统架构并相应重命名文件
    if [[ $(arch) == "armv5" || $(arch) == "armv6" || $(arch) == "armv7" ]]; then
        mv bin/xray-linux-$(arch) bin/xray-linux-arm
        chmod +x bin/xray-linux-arm
    fi
    chmod +x x-ui bin/xray-linux-$(arch)

    # 更新x-ui cli并设置权限
    mv -f /usr/bin/x-ui-temp /usr/bin/x-ui
    chmod +x /usr/bin/x-ui
    config_after_install

    if [[ $release == "alpine" ]]; then
        wget --inet4-only -O /etc/init.d/x-ui "${MIRROR_URL}https://raw.githubusercontent.com/ruyawwj/3x-ui/main/x-ui.rc"
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载x-ui.rc失败${plain}"
            exit 1
        fi
        chmod +x /etc/init.d/x-ui
        rc-update add x-ui
        rc-service x-ui start
    else
        cp -f x-ui.service /etc/systemd/system/
        systemctl daemon-reload
        systemctl enable x-ui
        systemctl start x-ui
    fi

    echo -e "${green}x-ui ${tag_version}${plain} 安装完成，现在正在运行..."
    echo -e ""
    echo -e "
   ===================================
   ${blue}x-ui 控制菜单用法 (子命令):${plain}
   ===================================
   ${blue}x-ui${plain}       - 管理脚本 
   ${blue}x-ui start${plain}   - 启动
   ${blue}x-ui stop${plain}    - 停止
   ${blue}x-ui restart${plain}   - 重启
   ${blue}x-ui status${plain}    - 状态
   ${blue}x-ui settings${plain}   - 当前设置
   ${blue}x-ui enable${plain}     - 开机自启
   ${blue}x-ui disable${plain}      - 禁用自启
   ${blue}x-ui log${plain}          - 查看日志
   ${blue}x-ui banlog${plain}        - 查看封禁日志
   ${blue}x-ui update${plain}         - 更新
   ${blue}x-ui update-all-geofiles${plain} - 更新所有geo文件
   ${blue}x-ui legacy${plain}           - 旧版本
   ${blue}x-ui install${plain}            - 安装
   ${blue}x-ui uninstall${plain}           - 卸载
   ===================================
"
}
echo -e "${green}运行中...${plain}"
install_base
install_x-ui $1