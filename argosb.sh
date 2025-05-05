#!/bin/bash
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "甬哥Github项目   ：github.com/yonggekkk"
echo "甬哥Blogger博客  ：ygkkk.blogspot.com"
echo "甬哥YouTube频道  ：www.youtube.com/@ygkkk"
echo "ArgoSB真一键无交互脚本"
echo "当前版本：25.4.28 测试beta5版 (Gist Upload + Fix)" # Modified version name
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "此脚本增加可选功能：通过环境变量 GIST_ID 和 GITHUB_TOKEN 将节点上传到 GitHub Gist。"
echo "如需使用，请先设置环境变量，例如: export GIST_ID='your_gist_id' && export GITHUB_TOKEN='your_personal_access_token'"
echo "请确保 GITHUB_TOKEN 具有 'gist' 权限。"
echo "如果您在 root 环境下运行，可能需要使用 'sudo -E bash $0'"
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
export LANG=en_US.UTF-8

# --- Color Codes ---
red(){ echo -e "\033[0;31m$1\033[0m"; }
yellow(){ echo -e "\033[0;33m$1\033[0m"; }
green(){ echo -e "\033[0;32m$1\033[0m"; }
# --- End Color Codes ---

# --- Must run as root ---
[[ $EUID -ne 0 ]] && red "错误：请以root模式运行脚本" && exit 1

# --- OS Detection ---
detect_os() {
    if [[ -f /etc/redhat-release ]]; then
        release="Centos"
    elif cat /etc/issue | grep -q -E -i "alpine"; then
        release="alpine"
    elif cat /etc/issue | grep -q -E -i "debian"; then
        release="Debian"
    elif cat /etc/issue | grep -q -E -i "ubuntu"; then
        release="Ubuntu"
    elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
        release="Centos"
    elif cat /proc/version | grep -q -E -i "debian"; then
        release="Debian"
    elif cat /proc/version | grep -q -E -i "ubuntu"; then
        release="Ubuntu"
    elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
        release="Centos"
    else
        release="unknown"
    fi

    op=$(cat /etc/redhat-release 2>/dev/null || cat /etc/os-release 2>/dev/null | grep -i pretty_name | cut -d \" -f2) || op="N/A"

    if [[ "$release" == "unknown" ]] || [[ $(echo "$op" | grep -i -E "arch|manjaro") ]]; then
        red "脚本不支持当前的系统 ($op / $release)，请选择使用 Ubuntu, Debian, Centos 系统。" && exit 1
    fi
}
detect_os # Run OS detection
# --- End OS Detection ---

# --- System Info ---
get_system_info() {
    [[ -z $(systemd-detect-virt 2>/dev/null) ]] && virt_type=$(virt-what 2>/dev/null) || virt_type=$(systemd-detect-virt 2>/dev/null)
    virt_type=${virt_type:-"N/A"} # Default if detection fails

    case $(uname -m) in
    aarch64) cpu=arm64;;
    x86_64) cpu=amd64;;
    *) red "错误：目前脚本不支持 $(uname -m) 架构" && exit 1;;
    esac
    hostname=$(hostname)
}
get_system_info # Run system info gathering
# --- End System Info ---

# --- Input Env Vars ---
# Values will be used if set, otherwise defaults apply later
export UUID=${uuid:-''}
export port_vm_ws=${vmpt:-''}
export ARGO_DOMAIN=${agn:-''}
export ARGO_AUTH=${agk:-''}
# --- End Input Env Vars ---

# --- Function Definitions ---
_check_pid() {
  [[ -f "$1" ]] && ps -p $(cat "$1") > /dev/null 2>&1
}

del(){
  yellow "开始卸载 ArgoSB..."
  # Kill processes using PID files first
  [[ -f /etc/s-box-ag/sbargopid.log ]] && kill -15 $(cat /etc/s-box-ag/sbargopid.log 2>/dev/null) >/dev/null 2>&1
  [[ -f /etc/s-box-ag/sbpid.log ]] && kill -15 $(cat /etc/s-box-ag/sbpid.log 2>/dev/null) >/dev/null 2>&1
  sleep 1
  # Force kill remaining processes by pattern matching (more robust)
  pkill -9 -f "/etc/s-box-ag/cloudflared tunnel" >/dev/null 2>&1
  pkill -9 -f "/etc/s-box-ag/sing-box run" >/dev/null 2>&1

  # Remove service files (if they exist from previous versions/attempts)
  if [[ x"${release}" == x"alpine" ]]; then
      rc-service sing-box stop >/dev/null 2>&1
      rc-update del sing-box default >/dev/null 2>&1
      rm -f /etc/init.d/sing-box
  else
      systemctl stop sing-box >/dev/null 2>&1
      systemctl disable sing-box >/dev/null 2>&1
      rm -f /etc/systemd/system/sing-box.service
      systemctl daemon-reload >/dev/null 2>&1 # Reload after removing service file
  fi

  # Remove crontab entries
  if command -v crontab &> /dev/null; then
      # Use grep -v to filter out lines containing the patterns
      (crontab -l 2>/dev/null | grep -v 's-box-ag/cloudflared' | grep -v 's-box-ag/sing-box') | crontab - >/dev/null 2>&1
  fi

  # Remove files
  rm -rf /etc/s-box-ag /usr/bin/agsb
  green "卸载完成"
}

up(){
  yellow "开始更新 ArgoSB 脚本..."
  if ! command -v curl &> /dev/null; then
     red "错误: curl 未安装，无法更新。请先手动安装 curl。"
     exit 1
  fi
  # Use a temporary file for safer download and replace
  tmp_agsb="/tmp/agsb_update.$$"
  if curl -L -o "$tmp_agsb" -# --retry 2 --connect-timeout 10 --insecure https://raw.githubusercontent.com/yonggekkk/argosb/main/argosb.sh; then
      # Verify download is a shell script (basic check)
      if head -n 1 "$tmp_agsb" | grep -q "#!/bin/bash"; then
          chmod +x "$tmp_agsb"
          # Replace the existing script
          if mv "$tmp_agsb" /usr/bin/agsb; then
              green "更新完成，请重新运行脚本: agsb"
          else
              red "错误：无法将下载的脚本移动到 /usr/bin/agsb。请检查权限。"
              rm -f "$tmp_agsb"
              exit 1
          fi
      else
          red "错误：下载的文件似乎不是有效的脚本。"
          rm -f "$tmp_agsb"
          exit 1
      fi
  else
      red "下载更新失败，请检查网络或稍后重试。"
      rm -f "$tmp_agsb" # Clean up temp file on failure
      exit 1
  fi
}
# --- End Function Definitions ---

# --- Command Line Arguments ---
if [[ "$1" == "del" ]]; then
  del
  exit 0
elif [[ "$1" == "up" ]]; then
  up
  exit 0
fi
# --- End Command Line Arguments ---

# --- Check Existing Installation Status ---
check_installation() {
    singbox_running=false
    cloudflared_running=false

    # Check using pid files first, then fallback to pgrep for robustness
    if _check_pid "/etc/s-box-ag/sbpid.log" || pgrep -f "/etc/s-box-ag/sing-box run" > /dev/null; then
        singbox_running=true
    fi
    if _check_pid "/etc/s-box-ag/sbargopid.log" || pgrep -f "/etc/s-box-ag/cloudflared tunnel" > /dev/null; then
        cloudflared_running=true
    fi

    if $singbox_running && $cloudflared_running && [[ -e /etc/s-box-ag/list.txt ]]; then
      green "ArgoSB 脚本检测到正在运行中"
      argoname=$(cat /etc/s-box-ag/sbargoym.log 2>/dev/null)
      if [ -z "$argoname" ]; then
          # Try to get temporary domain more reliably from logs
          argodomain=$(grep -o -E 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' /etc/s-box-ag/argo.log 2>/dev/null | head -n 1 | sed 's|https://||')
          if [ -z "$argodomain" ]; then
              yellow "无法获取当前 Argo 临时域名。日志可能已被清理或隧道未成功启动。"
              yellow "您可以尝试查看日志 (cat /etc/s-box-ag/argo.log) 或重新安装 (agsb del && bash $0)"
          else
              echo "当前 Argo 最新临时域名：$argodomain"
              echo "--- 节点信息 ---"
              cat /etc/s-box-ag/list.txt
              echo "------------------"
          fi
      else
          echo "当前 Argo 固定域名：$argoname"
          token_preview=$(head -c 10 /etc/s-box-ag/sbargotoken.log 2>/dev/null)...
          echo "当前 Argo 固定域名 token：$token_preview"
          echo "--- 节点信息 ---"
          cat /etc/s-box-ag/list.txt
          echo "------------------"
      fi
      exit 0 # Exit successfully as it's already running
    elif ! $singbox_running && ! $cloudflared_running; then
      echo "VPS 系统：$op ($release)"
      echo "CPU 架构：$cpu"
      echo "虚拟化：$virt_type"
      yellow "ArgoSB 脚本未安装或未运行，开始安装..." && sleep 2
      echo
      # Proceed with installation
    else
      red "ArgoSB 脚本状态异常 (sing-box 和 cloudflared 运行状态不一致)。"
      yellow "sing-box 运行状态: $singbox_running"
      yellow "cloudflared 运行状态: $cloudflared_running"
      red "可能与其他脚本冲突，或进程异常退出。"
      red "建议先卸载脚本 (agsb del) 再重新安装。"
      exit 1
    fi
}
check_installation # Run installation check
# --- End Check Existing Installation Status ---

# --- Install Dependencies ---
install_dependencies() {
    yellow "正在安装依赖包 (curl, wget, tar, gzip, cron, jq, coreutils)..."
    install_cmd=""
    update_cmd=""
    pkg_list="curl wget tar gzip jq coreutils" # coreutils for 'shuf', 'setsid', 'hostname', 'base64'

    # Add cron package based on release
    case "$release" in
        alpine)
            update_cmd="apk update -y"
            install_cmd="apk add --no-cache dcron tzdata openssl grep $pkg_list"
            cron_svc="dcron"
            ;;
        Debian|Ubuntu)
            update_cmd="apt-get update -y"
            install_cmd="apt-get install -y cron tzdata $pkg_list"
            cron_svc="cron"
            ;;
        Centos)
            update_cmd="yum update -y" # Consider removing '-y' if interaction is desired on failure
            install_cmd="yum install -y cronie tzdata $pkg_list"
            cron_svc="crond"
            ;;
        *)
            red "错误：无法为发行版 $release 确定包管理器。"
            exit 1
            ;;
    esac

    if ! $update_cmd || ! $install_cmd; then
        red "错误：依赖包安装失败，请检查错误信息。"
        exit 1
    fi

    # Ensure cron service is running and enabled
    if [[ "$release" == "alpine" ]]; then
        if ! rc-service $cron_svc status >/dev/null 2>&1; then
            rc-service $cron_svc start
            rc-update add $cron_svc default
        fi
    else
        if ! systemctl is-active --quiet $cron_svc; then
             systemctl start $cron_svc
             systemctl enable $cron_svc
        fi
    fi

    # Verify jq installation
    if ! command -v jq &> /dev/null; then
       red "错误: jq 安装失败或未找到。脚本需要 jq 来处理 JSON。"
       exit 1
    fi

    green "依赖包安装完成。"
}
install_dependencies
# --- End Install Dependencies ---

# --- WARP Check / Network Setup ---
setup_network() {
    warpcheck(){
      wgcfv6=$(curl -s6m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
      wgcfv4=$(curl -s4m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    }
    v4orv6(){
      # Add Cloudflare IPv6 DNS if IPv4 connectivity seems unavailable
      if ! curl -s4m5 icanhazip.com -k > /dev/null; then
          yellow "检测到 IPv4 可能不可用，尝试添加 IPv6 DNS..."
          # Prepend DNS servers to avoid overwriting existing ones completely
          # Check if DNS already exists to prevent duplicates
          if ! grep -q "2a00:1098:2b::1" /etc/resolv.conf; then
              echo -e "nameserver 2a00:1098:2b::1\nnameserver 2a00:1098:2c::1\nnameserver 2a01:4f8:c2c:123f::1" | cat - /etc/resolv.conf > /tmp/resolv.conf.new && mv /tmp/resolv.conf.new /etc/resolv.conf
          fi
      fi
    }
    warpcheck
    if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
      yellow "未检测到 WARP，执行网络检查..."
      v4orv6
    else
      yellow "检测到 WARP，尝试重启相关服务 (如果存在)..."
      systemctl stop wg-quick@wgcf >/dev/null 2>&1
      pkill -15 warp-go >/dev/null 2>&1 && sleep 1 # Shorter sleep
      v4orv6 # Check network again
      systemctl start wg-quick@wgcf >/dev/null 2>&1
      if command -v warp-go &> /dev/null; then
          systemctl enable warp-go >/dev/null 2>&1 # Ensure enabled before starting/restarting
          systemctl restart warp-go >/dev/null 2>&1
      fi
    fi
}
setup_network
# --- End WARP Check / Network Setup ---

# --- Create Directory ---
mkdir -p /etc/s-box-ag
# --- End Create Directory ---

# --- Download Sing-box ---
download_singbox() {
    yellow "正在获取最新的 sing-box 版本信息..."
    sbcore_url="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
    sbcore=$(curl -Ls --connect-timeout 10 $sbcore_url | jq -r '.tag_name' | sed 's/v//')

    if [[ -z "$sbcore" || "$sbcore" == "null" ]]; then
      yellow "无法从 GitHub API 获取最新的 sing-box 版本号。尝试使用 jsDelivr..."
      sbcore=$(curl -Ls --connect-timeout 10 https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"[0-9.]+"' | head -n 1 | tr -d '"')
      if [[ -z "$sbcore" ]]; then
          red "错误：也无法从 jsDelivr 获取版本号。请检查网络或稍后再试。"
          exit 1
      fi
    fi

    sbname="sing-box-${sbcore}-linux-${cpu}"
    sbtargz="${sbname}.tar.gz"
    sb_download_url="https://github.com/SagerNet/sing-box/releases/download/v${sbcore}/${sbtargz}"
    sb_archive_path="/etc/s-box-ag/sing-box.tar.gz"
    sb_executable_path="/etc/s-box-ag/sing-box"

    echo "下载 sing-box v${sbcore} (${cpu}) 内核..."
    if curl -L -o "$sb_archive_path" -# --retry 3 --retry-delay 2 --connect-timeout 15 "$sb_download_url"; then
      green "下载成功。"
      yellow "解压 sing-box..."
      # Extract directly to /etc/s-box-ag and strip the top-level directory
      if tar xzf "$sb_archive_path" -C /etc/s-box-ag --strip-components=1 "${sbname}/sing-box"; then
          rm -f "$sb_archive_path" # Remove archive only on successful extraction
          chmod +x "$sb_executable_path"
          green "sing-box 内核准备就绪。"
          # Validate the executable
          if ! "$sb_executable_path" version &> /dev/null; then
             red "错误：sing-box 可执行文件校验失败！可能是下载损坏或架构不匹配。"
             rm -f "$sb_executable_path" # Clean up corrupted binary
             exit 1
          fi
      else
          red "错误：解压 sing-box 失败。"
          rm -f "$sb_archive_path" # Clean up archive
          exit 1
      fi
    else
      red "错误：下载 sing-box 失败。请检查网络、GitHub Release 或 CPU 架构 ($cpu)。"
      rm -f "$sb_archive_path" # Clean up partial download
      exit 1
    fi
}
download_singbox
# --- End Download Sing-box ---

# --- Generate UUID and Port ---
generate_config_params() {
    if [ -z "$port_vm_ws" ]; then
      port_vm_ws=$(shuf -i 10000-65535 -n 1)
    fi
    # !! crucial fix for jq error: Validate the port !!
    if ! [[ "$port_vm_ws" =~ ^[0-9]+$ ]] || [ "$port_vm_ws" -lt 1 ] || [ "$port_vm_ws" -gt 65535 ]; then
        yellow "警告：环境变量中的端口 '$port_vm_ws' 无效。重新生成随机端口。"
        port_vm_ws=$(shuf -i 10000-65535 -n 1)
    fi
    # Final check after generation/validation
     if ! [[ "$port_vm_ws" =~ ^[0-9]+$ ]]; then
        red "错误：未能生成有效的端口号 (port_vm_ws='$port_vm_ws')。"
        exit 1
    fi


    if [ -z "$UUID" ]; then
      if [[ -x "/etc/s-box-ag/sing-box" ]]; then
          UUID=$(/etc/s-box-ag/sing-box generate uuid)
      else
          red "错误：无法执行 sing-box 生成 UUID。sing-box 未正确安装。"
          exit 1
      fi
    fi
    # Basic UUID format check (optional but good)
    if ! [[ "$UUID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
       red "错误：生成的 UUID '$UUID' 格式无效。"
       # Attempt to regenerate once
       UUID=$(/etc/s-box-ag/sing-box generate uuid)
       if ! [[ "$UUID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
          red "错误：再次生成的 UUID 仍然无效。退出。"
          exit 1
       fi
    fi

    echo
    echo "当前 vmess 主协议端口：$port_vm_ws"
    echo "当前 uuid 密码：$UUID"
    echo
    sleep 1
}
generate_config_params
# --- End Generate UUID and Port ---

# --- Create Sing-box Config ---
create_singbox_config() {
    sb_config_path="/etc/s-box-ag/sb.json"
    yellow "正在生成 sing-box 配置文件: $sb_config_path"
    cat > "$sb_config_path" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vmess",
      "tag": "vmess-in",
      "listen": "::",
      "listen_port": ${port_vm_ws},
      "users": [
        {
          "uuid": "${UUID}",
          "alterId": 0
        }
      ],
      "transport": {
        "type": "ws",
        "path": "/${UUID}-vm",
        "max_early_data": 2048,
        "early_data_header_name": "Sec-WebSocket-Protocol"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF
    # Validate JSON syntax
    if ! jq '.' "$sb_config_path" > /dev/null; then
        red "错误：生成的 sing-box 配置文件 ($sb_config_path) JSON 格式无效！请检查变量或模板。"
        cat "$sb_config_path" # Print the invalid config for debugging
        exit 1
    else
       green "sing-box 配置文件生成成功。"
    fi
}
create_singbox_config
# --- End Create Sing-box Config ---

# --- Start Sing-box Process and Setup Cron ---
start_singbox() {
    sb_executable_path="/etc/s-box-ag/sing-box"
    sb_config_path="/etc/s-box-ag/sb.json"
    sb_pid_file="/etc/s-box-ag/sbpid.log"
    sb_log_file="/etc/s-box-ag/singbox.log"

    yellow "启动 sing-box 进程..."
    # Kill existing process just in case before starting new one
    pkill -9 -f "$sb_executable_path run -c $sb_config_path" >/dev/null 2>&1
    # Start using nohup and setsid, redirect logs
    nohup /usr/bin/setsid "$sb_executable_path" run -c "$sb_config_path" > "$sb_log_file" 2>&1 &
    # Save PID
    echo "$!" > "$sb_pid_file"
    sleep 2 # Give it a moment to start

    # Verify process started
    if ! _check_pid "$sb_pid_file"; then
        red "错误：启动 sing-box 进程失败！"
        red "请检查日志: tail -n 20 $sb_log_file"
        # Attempt cleanup before exiting
        [[ -f "$sb_pid_file" ]] && kill -9 $(cat "$sb_pid_file") >/dev/null 2>&1
        rm -f "$sb_pid_file"
        exit 1
    else
        green "sing-box 进程启动成功 (PID: $(cat "$sb_pid_file"))."
    fi

    yellow "添加 sing-box 到 crontab 实现开机自启..."
    if command -v crontab &> /dev/null; then
        # Remove existing entry first to prevent duplicates
        (crontab -l 2>/dev/null | grep -v "$sb_config_path") | crontab -
        # Add new entry using full paths
        (crontab -l 2>/dev/null; echo "@reboot /usr/bin/nohup /usr/bin/setsid $sb_executable_path run -c $sb_config_path > $sb_log_file 2>&1 & echo \$! > $sb_pid_file") | crontab -
        green "sing-box Crontab 设置完成。"
    else
        yellow "警告：未找到 crontab 命令，无法设置开机自启。请手动配置。"
    fi
}
start_singbox
# --- End Start Sing-box Process ---

# --- Download Cloudflared ---
download_cloudflared() {
    yellow "正在获取最新的 cloudflared 版本信息..."
    cfd_url="https://api.github.com/repos/cloudflare/cloudflared/releases/latest"
    argocore=$(curl -Ls --connect-timeout 10 $cfd_url | jq -r '.tag_name')

    if [[ -z "$argocore" || "$argocore" == "null" ]]; then
      yellow "无法从 GitHub API 获取最新的 cloudflared 版本号。尝试使用 jsDelivr..."
      argocore=$(curl -Ls --connect-timeout 10 https://data.jsdelivr.com/v1/package/gh/cloudflare/cloudflared | grep -Eo '"[0-9.]+"' | head -n 1 | tr -d '"')
      if [[ -z "$argocore" ]]; then
          red "错误：也无法从 jsDelivr 获取 cloudflared 版本号。请检查网络或稍后再试。"
          start_singbox stop # Stop sing-box if CF download fails
          exit 1
      fi
    fi

    cfd_download_url="https://github.com/cloudflare/cloudflared/releases/download/${argocore}/cloudflared-linux-${cpu}"
    cfd_executable_path="/etc/s-box-ag/cloudflared"

    echo "下载 cloudflared ${argocore} (${cpu}) 内核..."
    if curl -L -o "$cfd_executable_path" -# --retry 3 --retry-delay 2 --connect-timeout 15 "$cfd_download_url"; then
      chmod +x "$cfd_executable_path"
      green "cloudflared 下载成功。"
      # Validate the executable
      if ! "$cfd_executable_path" --version &> /dev/null; then
          red "错误：cloudflared 可执行文件校验失败！可能是下载损坏或架构不匹配。"
          rm -f "$cfd_executable_path" # Clean up bad binary
          start_singbox stop # Stop sing-box
          exit 1
      fi
    else
      red "错误：下载 cloudflared 失败。"
      rm -f "$cfd_executable_path" # Clean up partial download
      start_singbox stop # Stop sing-box
      exit 1
    fi
}
download_cloudflared
# --- End Download Cloudflared ---

# --- Start Cloudflared Process and Setup Cron ---
start_cloudflared() {
    cfd_executable_path="/etc/s-box-ag/cloudflared"
    cfd_pid_file="/etc/s-box-ag/sbargopid.log"
    cfd_log_file="/etc/s-box-ag/argo.log"
    argo_domain_file="/etc/s-box-ag/sbargoym.log"
    argo_token_file="/etc/s-box-ag/sbargotoken.log"

    # Kill existing process first
    pkill -9 -f "$cfd_executable_path tunnel" >/dev/null 2>&1
    rm -f "$cfd_pid_file" "$argo_domain_file" "$argo_token_file" # Clean previous state files

    # Determine target URL for temporary tunnel
    target_port=$(jq -r '.inbounds[0].listen_port' /etc/s-box-ag/sb.json)
    target_url="http://localhost:${target_port}"

    argo_cmd_base="$cfd_executable_path tunnel --no-autoupdate --edge-ip-version auto --protocol http2"
    cron_cmd_base="/usr/bin/nohup /usr/bin/setsid $cfd_executable_path tunnel --no-autoupdate --edge-ip-version auto --protocol http2"
    argo_start_cmd=""
    cron_start_cmd=""
    tunnel_type="" # '固定' or '临时'

    if [[ -n "${ARGO_DOMAIN}" && -n "${ARGO_AUTH}" ]]; then
      tunnel_type='固定'
      yellow "使用提供的 token 启动 Argo 固定域名隧道 (${ARGO_DOMAIN})..."
      argo_start_cmd="$argo_cmd_base run --token ${ARGO_AUTH}"
      cron_start_cmd="$cron_cmd_base run --token \$(cat $argo_token_file 2>/dev/null)" # Read token from file in cron

      # Store domain and token persistently
      echo "${ARGO_DOMAIN}" > "$argo_domain_file"
      echo "${ARGO_AUTH}" > "$argo_token_file"
    else
      tunnel_type='临时'
      yellow "启动 Argo 临时域名隧道 (目标: $target_url)..."
      argo_start_cmd="$argo_cmd_base --url $target_url"
      cron_start_cmd="$cron_cmd_base --url $target_url" # Use the same target URL in cron
    fi

    # Start the tunnel process
    nohup /usr/bin/setsid $argo_start_cmd > "$cfd_log_file" 2>&1 &
    echo "$!" > "$cfd_pid_file"

    echo "等待 Argo $tunnel_type 隧道建立... (最多等待 25 秒)"
    success=false
    final_argodomain=""
    # Wait loop
    for i in {1..10}; do
      sleep 2.5 # Check every 2.5 seconds
      # Check if process is still running
      if ! _check_pid "$cfd_pid_file"; then
          red "错误：cloudflared 进程在启动期间意外终止！"
          success=false
          break # Exit loop early
      fi
      # Check for success based on type
      if [[ "$tunnel_type" == "固定" ]]; then
          # For fixed domain, check for connection registration messages
          if grep -q -E "Connection [a-zA-Z0-9]+ registered" "$cfd_log_file"; then
              final_argodomain=$(cat "$argo_domain_file" 2>/dev/null) # Read stored domain
              if [[ -n "$final_argodomain" ]]; then
                  success=true
                  break
              fi
          fi
      else # Temporary domain
          # Extract domain from log file
          final_argodomain=$(grep -o -E 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' "$cfd_log_file" | head -n 1 | sed 's|https://||')
          if [[ -n "$final_argodomain" ]]; then
              success=true
              # Store temporary domain for reference (optional)
              echo "$final_argodomain" > "$argo_domain_file"
              break
          fi
      fi
      echo -n "." # Progress indicator
    done
    echo # Newline after progress dots

    # Check result
    if $success && [[ -n "$final_argodomain" ]]; then
      green "Argo $tunnel_type 隧道申请成功！域名: $final_argodomain"
      # Store the validated domain (useful if temporary domain was extracted)
      echo "$final_argodomain" > "$argo_domain_file"
    else
      red "错误：Argo $tunnel_type 隧道申请失败。"
      red "请检查日志: tail -n 20 $cfd_log_file"
      del # Clean up failed setup
      exit 1
    fi

    # Setup Crontab for Cloudflared
    yellow "添加 Argo 隧道到 crontab 实现开机自启..."
    if command -v crontab &> /dev/null; then
        # Remove existing entry first
        (crontab -l 2>/dev/null | grep -v "$cfd_executable_path tunnel") | crontab -
        # Add new entry
        (crontab -l 2>/dev/null; echo "@reboot $cron_start_cmd > $cfd_log_file 2>&1 & echo \$! > $cfd_pid_file") | crontab -
        green "Argo Crontab 设置完成。"
    else
        yellow "警告：未找到 crontab 命令，无法为 Argo 设置开机自启。请手动配置。"
    fi
    # Assign the validated domain to the global variable for link generation
    argodomain=$final_argodomain
}
start_cloudflared
# --- End Start Cloudflared Process ---

# --- Update agsb Command ---
update_agsb_command() {
    yellow "创建/更新 agsb 快捷命令..."
    # Use the already downloaded script content if 'up' wasn't called
    if [[ -f "/usr/bin/agsb" ]]; then
        cp "$0" /usr/bin/agsb # Update with current script if running directly
        chmod +x /usr/bin/agsb
        green "agsb 命令已更新为当前运行的脚本。"
    elif command -v curl &> /dev/null; then
         # If agsb doesn't exist, try downloading the latest one
        if curl -L -o /usr/bin/agsb -# --retry 2 --connect-timeout 10 --insecure https://raw.githubusercontent.com/yonggekkk/argosb/main/argosb.sh; then
           chmod +x /usr/bin/agsb
           green "agsb 命令创建成功。"
        else
           yellow "警告：无法下载最新脚本以创建 agsb 命令。安装仍会继续。"
           yellow "您可以稍后手动运行: agsb up"
        fi
    else
         yellow "警告：curl 命令不可用，无法下载最新脚本创建 agsb 命令。"
    fi
}
update_agsb_command
# --- End Update agsb Command ---

# --- Generate VMess Links ---
generate_vmess_links() {
    yellow "生成 VMess 节点链接..."
    vmess_links_file="/etc/s-box-ag/jh.txt"
    > "$vmess_links_file" # Clear existing file

    # Use the globally set $argodomain validated during tunnel startup
    if [[ -z "$argodomain" ]]; then
       red "错误：无法获取有效的 Argo 域名，无法生成链接。"
       exit 1
    fi

    vmess_path="/${UUID}-vm?ed=2048"
    # Define Cloudflare IPs and Ports
    # Format: "IP Port TLS_Flag PS_Suffix"
    cf_endpoints=(
        "104.16.0.0 443 tls v4"
        "104.17.0.0 8443 tls v4"
        "104.18.0.0 2053 tls v4"
        "104.19.0.0 2083 tls v4"
        "104.20.0.0 2087 tls v4"
        "[2606:4700::] 2096 tls v6" # IPv6 TLS
        "104.21.0.0 80 none v4"
        "104.22.0.0 8080 none v4"
        "104.24.0.0 8880 none v4"
        "104.25.0.0 2052 none v4"
        "104.26.0.0 2082 none v4"
        "104.27.0.0 2086 none v4"
        "[2400:cb00:2049::] 2095 none v6" # IPv6 Non-TLS
    )

    # Loop through endpoints and generate links
    for endpoint in "${cf_endpoints[@]}"; do
        read -r ip port tls_flag ps_suffix <<< "$endpoint" # Read space-separated values

        local tls_val=""
        local sni_val=""
        local ps_prefix="vmess-ws"

        if [[ "$tls_flag" == "tls" ]]; then
            tls_val="tls"
            sni_val="$argodomain"
            ps_prefix="vmess-ws-tls"
        fi

        # Use jq for robust JSON creation and base64 encoding
        local config_json
        config_json=$(jq -nc \
            --arg v "2" \
            --arg ps "${ps_prefix}-argo-${hostname}-${port}-${ps_suffix}" \
            --arg add "$ip" \
            --arg port "$port" \
            --arg id "$UUID" \
            --arg aid "0" \
            --arg scy "auto" \
            --arg net "ws" \
            --arg type "none" \
            --arg host "$argodomain" \
            --arg path "$vmess_path" \
            --arg tls "$tls_val" \
            --arg sni "$sni_val" \
            --arg alpn "" \
            --arg fp "" \
            '{v:$v, ps:$ps, add:$add, port:$port, id:$id, aid:$aid, scy:$scy, net:$net, type:$type, host:$host, path:$path, tls:$tls, sni:$sni, alpn:$alpn, fp:$fp}')

        if [[ $? -ne 0 ]]; then
             red "错误：使用 jq 生成节点配置时出错 (IP: $ip, Port: $port)。"
             continue # Skip this link
        fi

        echo "vmess://$(echo "$config_json" | base64 -w 0)" >> "$vmess_links_file"
    done

    green "VMess 节点链接生成完成。"

    # Prepare output variables
    baseurl=$(base64 -w 0 < "$vmess_links_file")
    line1=$(sed -n '1p' "$vmess_links_file")  # 443 TLS v4
    line6=$(sed -n '6p' "$vmess_links_file")  # 2096 TLS v6
    line7=$(sed -n '7p' "$vmess_links_file")  # 80 NoTLS v4
    line13=$(sed -n '13p' "$vmess_links_file") # 2095 NoTLS v6
}
generate_vmess_links
# --- End Generate VMess Links ---


# <<<-------------------- GIST UPLOAD SECTION (via Env Vars) -------------------->>>
upload_to_gist() {
    # Read Gist ID and GitHub Token from environment variables
    GIST_ID_FROM_ENV="${GIST_ID:-}"           # Read GIST_ID or default to empty
    GITHUB_TOKEN_FROM_ENV="${GITHUB_TOKEN:-}" # Read GITHUB_TOKEN or default to empty
    GIST_FILENAME="aggregated_nodes.txt" # Filename within the Gist (make unique per host)

    # Initialize response_code to indicate skipped state initially
    gist_response_code="skipped" # Possible values: skipped, 200 (success), other HTTP codes (failure)

    # Check if both variables were successfully read from the environment and are not empty
    if [[ -n "$GIST_ID_FROM_ENV" && -n "$GITHUB_TOKEN_FROM_ENV" ]]; then
        yellow "GIST_ID and GITHUB_TOKEN found in environment. Preparing Gist upload..."
        echo "确保您的 GitHub Token 具有 'gist' 写入权限。"

        if [[ -z "$baseurl" ]]; then
            red "错误: 无法读取聚合节点内容 (baseurl is empty)。跳过 Gist 上传。"
            gist_response_code="error_no_content"
            return # Exit function
        fi

        # Construct the JSON payload for the Gist API using jq for safety
        # Use jq to escape the base64 content properly within the JSON string
        json_payload=$(jq -nc \
            --arg desc "ArgoSB Aggregated Nodes - $(date '+%Y-%m-%d %H:%M:%S %Z') ($hostname)" \
            --arg filename "$GIST_FILENAME" \
            --arg content "$baseurl" \
            '{description: $desc, files: {($filename): {content: $content}}}')

        if [[ $? -ne 0 ]]; then
            red "错误: 使用 jq 构建 Gist JSON 负载时出错。跳过 Gist 上传。"
            gist_response_code="error_json_build"
            return # Exit function
        fi

        # Make the API call to update the Gist
        echo "正在上传到 Gist ID: $GIST_ID_FROM_ENV ..."
        api_response=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
             -X PATCH \
             -H "Authorization: token $GITHUB_TOKEN_FROM_ENV" \
             -H "Accept: application/vnd.github.v3+json" \
             -d "$json_payload" \
             "https://api.github.com/gists/$GIST_ID_FROM_ENV")

        # Extract HTTP code from the response
        gist_response_code=$(echo "$api_response" | grep "HTTP_CODE:" | cut -d':' -f2)
        response_body=$(echo "$api_response" | sed '$d') # Get body without the code line

        if [[ "$gist_response_code" -eq 200 ]]; then
            green "成功上传聚合节点到 Gist！"
            echo "Gist URL: https://gist.github.com/$GIST_ID_FROM_ENV"
        else
            red "上传到 Gist 失败！HTTP Status Code: $gist_response_code"
            yellow "请检查 Gist ID、GitHub Token (需要 'gist' 权限) 或网络连接。"
            # Print API response body if available and not too long
            if [[ -n "$response_body" ]]; then
               yellow "GitHub API 响应:"
               echo "$response_body" | head -n 5 # Show first few lines of error
            fi
        fi
    else
        yellow "GIST_ID 或 GITHUB_TOKEN 环境变量未设置或为空。跳过 Gist 上传。"
        gist_response_code="skipped" # Keep it as skipped
    fi
    # Expose the result code globally if needed outside the function
    export GIST_UPLOAD_STATUS_CODE=$gist_response_code
}
upload_to_gist # Execute the Gist upload function
# <<<------------------ END GIST UPLOAD SECTION ------------------>>>


# --- Prepare and Display Final Output ---
generate_final_output() {
    green "ArgoSB 脚本安装完毕" && sleep 1
    output_file="/etc/s-box-ag/list.txt"
    tunnel_mode=$([[ -n "${ARGO_DOMAIN}" && -n "${ARGO_AUTH}" ]] && echo "固定" || echo "临时")

    # Get Gist status message based on the code
    gist_status_message=""
    case "$GIST_UPLOAD_STATUS_CODE" in
        "200")
            gist_status_message="Success (https://gist.github.com/${GIST_ID_FROM_ENV})"
            ;;
        "skipped")
            gist_status_message="Skipped (Set GIST_ID and GITHUB_TOKEN env vars to enable)"
            ;;
        "error_no_content")
            gist_status_message="Failed (Node content was empty)"
            ;;
        "error_json_build")
            gist_status_message="Failed (Could not build JSON payload)"
            ;;
        *)
            gist_status_message="Failed (HTTP $GIST_UPLOAD_STATUS_CODE)"
            ;;
    esac


    # Create the final output file
    cat > "$output_file" <<EOF
---------------------------------------------------------
甬哥Github项目: github.com/yonggekkk
甬哥YouTube频道: www.youtube.com/@ygkkk
---------------------------------------------------------
ArgoSB 节点配置信息
主机名        : ${hostname}
系统          : ${op} (${release})
架构          : ${cpu}
---------------------------------------------------------
Argo 域名     : ${argodomain} (${tunnel_mode})
Sing-box 端口 : ${port_vm_ws} (本地监听)
Sing-box UUID : ${UUID}
---------------------------------------------------------
单节点配置示例 (推荐优先使用)：

1. Vmess + WS + TLS (端口 443, Cloudflare IPv4)
$line1

2. Vmess + WS + TLS (端口 2096, Cloudflare IPv6) [需本地网络支持IPv6]
$line6

3. Vmess + WS (无TLS) (端口 80, Cloudflare IPv4)
$line7

4. Vmess + WS (无TLS) (端口 2095, Cloudflare IPv6) [需本地网络支持IPv6]
$line13

---------------------------------------------------------
聚合节点配置输出 (Base64 编码, 包含所有13个节点):
(复制下面的全部内容导入客户端)

$baseurl

---------------------------------------------------------
Gist Upload Status: $gist_status_message
---------------------------------------------------------
相关快捷方式:
  agsb      显示当前域名及节点信息 (如果脚本正在运行)
  agsb up   升级 ArgoSB 脚本 (下载最新版并替换 /usr/bin/agsb)
  agsb del  卸载 ArgoSB 脚本 (停止进程, 清理文件和 Cron)
---------------------------------------------------------
日志文件:
Sing-box : /etc/s-box-ag/singbox.log
Cloudflared: /etc/s-box-ag/argo.log
---------------------------------------------------------
EOF

    # Display the final output from the file
    echo "========================================================="
    green "ArgoSB 脚本安装/配置完成！节点信息如下："
    echo "========================================================="
    cat "$output_file"
    echo "========================================================="
}
generate_final_output
# --- End Final Output ---

exit 0 # Explicitly exit with success code
