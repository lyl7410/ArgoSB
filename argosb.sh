#!/bin/bash
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "甬哥Github项目   ：github.com/yonggekkk"
echo "甬哥Blogger博客  ：ygkkk.blogspot.com"
echo "甬哥YouTube频道  ：www.youtube.com/@ygkkk"
echo "ArgoSB真一键无交互脚本"
echo "当前版本：25.4.28 测试beta5版 (Gist Upload via Env Var)" # Modified version name
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
export LANG=en_US.UTF-8

# --- Color Codes (Optional but nice) ---
red(){ echo -e "\033[0;31m$1\033[0m"; }
yellow(){ echo -e "\033[0;33m$1\033[0m"; }
green(){ echo -e "\033[0;32m$1\033[0m"; }
# --- End Color Codes ---

[[ $EUID -ne 0 ]] && red "请以root模式运行脚本" && exit # Use red color

# --- OS Detection ---
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
red "脚本不支持当前的系统，请选择使用Ubuntu,Debian,Centos系统。" && exit
fi
op=$(cat /etc/redhat-release 2>/dev/null || cat /etc/os-release 2>/dev/null | grep -i pretty_name | cut -d \" -f2)
if [[ $(echo "$op" | grep -i -E "arch|manjaro") ]]; then # Added manjaro to exclusion
red "脚本不支持当前的 $op 系统，请选择使用Ubuntu,Debian,Centos系统。" && exit
fi
# --- End OS Detection ---

# --- System Info ---
[[ -z $(systemd-detect-virt 2>/dev/null) ]] && virt_type=$(virt-what 2>/dev/null) || virt_type=$(systemd-detect-virt 2>/dev/null)
case $(uname -m) in
aarch64) cpu=arm64;;
x86_64) cpu=amd64;;
*) red "目前脚本不支持 $(uname -m) 架构" && exit;;
esac
hostname=$(hostname)
# --- End System Info ---

# --- Input Env Vars ---
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
  # Kill processes using PID files
  [[ -f /etc/s-box-ag/sbargopid.log ]] && kill -15 $(cat /etc/s-box-ag/sbargopid.log 2>/dev/null) >/dev/null 2>&1
  [[ -f /etc/s-box-ag/sbpid.log ]] && kill -15 $(cat /etc/s-box-ag/sbpid.log 2>/dev/null) >/dev/null 2>&1
  sleep 1
  # Force kill if still running (optional, but can help ensure cleanup)
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
      systemctl daemon-reload >/dev/null 2>&1
  fi

  # Remove crontab entries
  if command -v crontab &> /dev/null; then
      crontab -l > /tmp/crontab.tmp 2>/dev/null
      sed -i '/sbargopid/d' /tmp/crontab.tmp
      sed -i '/sbpid/d' /tmp/crontab.tmp
      crontab /tmp/crontab.tmp >/dev/null 2>&1
      rm -f /tmp/crontab.tmp
  fi

  # Remove files
  rm -rf /etc/s-box-ag /usr/bin/agsb
  green "卸载完成"
}

up(){
  yellow "开始更新 ArgoSB 脚本..."
  if ! command -v curl &> /dev/null; then
     red "curl 未安装，无法更新。请先手动安装 curl。"
     exit 1
  fi
  if curl -L -o /usr/bin/agsb -# --retry 2 --insecure https://raw.githubusercontent.com/yonggekkk/argosb/main/argosb.sh; then
      chmod +x /usr/bin/agsb
      green "更新完成，请重新运行脚本: agsb"
  else
      red "下载更新失败，请检查网络或稍后重试。"
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
      # Try to get temporary domain more reliably
      argodomain=$(grep -o -E 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' /etc/s-box-ag/argo.log 2>/dev/null | head -n 1 | sed 's|https://||')
      if [ -z "$argodomain" ]; then
          yellow "无法获取当前 Argo 临时域名。日志可能已被清理。"
          yellow "您可以尝试重启服务或重新安装 (agsb del && agsb)"
      else
          echo "当前 Argo 最新临时域名：$argodomain"
          echo "--- 节点信息 ---"
          cat /etc/s-box-ag/list.txt
          echo "------------------"
      fi
  else
      echo "当前 Argo 固定域名：$argoname"
      echo "当前 Argo 固定域名 token：$(cat /etc/s-box-ag/sbargotoken.log 2>/dev/null)"
      echo "--- 节点信息 ---"
      cat /etc/s-box-ag/list.txt
      echo "------------------"
  fi
  exit 0
elif ! $singbox_running && ! $cloudflared_running; then
  echo "VPS 系统：$op ($release)"
  echo "CPU 架构：$cpu"
  echo "虚拟化：$virt_type"
  yellow "ArgoSB 脚本未安装或未运行，开始安装..." && sleep 2
  echo
else
  red "ArgoSB 脚本状态异常 (sing-box 和 cloudflared 运行状态不一致)。"
  yellow "sing-box 运行状态: $singbox_running"
  yellow "cloudflared 运行状态: $cloudflared_running"
  red "可能与其他脚本冲突，或进程异常退出。"
  red "建议先卸载脚本 (agsb del) 再重新安装。"
  exit 1
fi
# --- End Check Existing Installation Status ---

# --- Install Dependencies ---
yellow "正在安装依赖包 (curl, wget, tar, gzip, cron, jq, coreutils)..."
install_cmd=""
update_cmd=""
pkg_list="curl wget tar gzip jq coreutils" # coreutils for 'setsid' and 'hostname'

# Add cron based on release
if [[ x"${release}" == x"alpine" ]]; then
  update_cmd="apk update -y"
  install_cmd="apk add --no-cache dcron tzdata openssl git grep $pkg_list"
  # Ensure cron service is running and enabled on Alpine
  if ! rc-service dcron status >/dev/null 2>&1; then
      rc-service dcron start
      rc-update add dcron default
  fi
elif command -v apt &> /dev/null; then
  update_cmd="apt update -y"
  install_cmd="apt install -y cron tzdata $pkg_list"
  # Ensure cron service is running and enabled on Debian/Ubuntu
  if ! systemctl is-active --quiet cron; then
       systemctl start cron
       systemctl enable cron
  fi
elif command -v yum &> /dev/null; then
  update_cmd="yum update -y" # Consider removing '-y' if interaction is desired on failure
  install_cmd="yum install -y cronie tzdata $pkg_list"
  # Ensure cron service is running and enabled on CentOS/RHEL
  if ! systemctl is-active --quiet crond; then
       systemctl start crond
       systemctl enable crond
  fi
else
  red "不支持的包管理器。请为您的系统手动安装：$pkg_list 和 cron 服务。"
  exit 1
fi

if $update_cmd && $install_cmd; then
  green "依赖包安装完成。"
else
  red "依赖包安装失败，请检查错误信息。"
  exit 1
fi
# --- End Install Dependencies ---

# --- WARP Check / Network Setup ---
warpcheck(){
  wgcfv6=$(curl -s6m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
  wgcfv4=$(curl -s4m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
}
v4orv6(){
  # Add IPv6 DNS if IPv4 is not available
  if ! curl -s4m5 icanhazip.com -k > /dev/null; then
      yellow "检测到 IPv4 可能不可用，尝试添加 IPv6 DNS..."
      # Prepend DNS servers to avoid overwriting existing ones completely
      echo -e "nameserver 2a00:1098:2b::1\nnameserver 2a00:1098:2c::1\nnameserver 2a01:4f8:c2c:123f::1" | cat - /etc/resolv.conf > /tmp/resolv.conf.new && mv /tmp/resolv.conf.new /etc/resolv.conf
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
      systemctl enable warp-go >/dev/null 2>&1 # Enable before starting
      systemctl restart warp-go >/dev/null 2>&1
  fi
fi
# --- End WARP Check / Network Setup ---

# --- Create Directory ---
mkdir -p /etc/s-box-ag
# --- End Create Directory ---

# --- Download Sing-box ---
yellow "正在获取最新的 sing-box 版本信息..."
sbcore_url="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
sbcore=$(curl -Ls $sbcore_url | jq -r '.tag_name' | sed 's/v//')

if [[ -z "$sbcore" || "$sbcore" == "null" ]]; then
  red "无法从 GitHub API 获取最新的 sing-box 版本号。"
  yellow "尝试使用 jsDelivr 获取版本信息..."
  sbcore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"[0-9.]+"' | head -n 1 | tr -d '"')
  if [[ -z "$sbcore" ]]; then
      red "也无法从 jsDelivr 获取版本号。请检查网络或稍后再试。"
      exit 1
  fi
fi

sbname="sing-box-${sbcore}-linux-${cpu}"
sbtargz="${sbname}.tar.gz"
sb_download_url="https://github.com/SagerNet/sing-box/releases/download/v${sbcore}/${sbtargz}"

echo "下载 sing-box v${sbcore} (${cpu}) 内核..."
if curl -L -o "/etc/s-box-ag/sing-box.tar.gz" -# --retry 3 --retry-delay 2 "$sb_download_url"; then
  green "下载成功。"
  yellow "解压 sing-box..."
  # Extract directly to /etc/s-box-ag and strip the top-level directory
  if tar xzf /etc/s-box-ag/sing-box.tar.gz -C /etc/s-box-ag --strip-components=1 "${sbname}/sing-box"; then
      rm -f "/etc/s-box-ag/sing-box.tar.gz" # Remove archive only on successful extraction
      chmod +x /etc/s-box-ag/sing-box
      green "sing-box 内核准备就绪。"
      if ! /etc/s-box-ag/sing-box version &> /dev/null; then
         red "sing-box 可执行文件校验失败！"
         rm -f /etc/s-box-ag/sing-box # Clean up corrupted binary
         exit 1
      fi
  else
      red "解压 sing-box 失败。"
      rm -f /etc/s-box-ag/sing-box.tar.gz # Clean up archive
      exit 1
  fi
else
  red "下载 sing-box 失败。请检查网络、GitHub Release 或 CPU 架构 ($cpu)。"
  rm -f /etc/s-box-ag/sing-box.tar.gz # Clean up partial download
  exit 1
fi
# --- End Download Sing-box ---

# --- Generate UUID and Port ---
if [ -z "$port_vm_ws" ]; then
  port_vm_ws=$(shuf -i 10000-65535 -n 1)
fi
if [ -z "$UUID" ]; then
  if [[ -x "/etc/s-box-ag/sing-box" ]]; then
      UUID=$(/etc/s-box-ag/sing-box generate uuid)
  else
      red "无法执行 sing-box 生成 UUID。请确保 sing-box 已正确下载和解压。"
      exit 1
  fi
fi
echo
echo "当前 vmess 主协议端口：$port_vm_ws"
echo "当前 uuid 密码：$UUID"
echo
sleep 1
# --- End Generate UUID and Port ---

# --- Create Sing-box Config ---
cat > /etc/s-box-ag/sb.json <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vmess",
      "tag": "vmess-in",
      "listen": "::", // Listen on both IPv4 and IPv6 if available
      "listen_port": ${port_vm_ws},
      "users": [
        {
          "uuid": "${UUID}",
          "alterId": 0
        }
      ],
      "transport": {
        "type": "ws",
        "path": "/${UUID}-vm", // Ensure leading slash
        "max_early_data": 2048,
        "early_data_header_name": "Sec-WebSocket-Protocol"
      }
      // TLS is handled by Argo Tunnel, so no TLS section here
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
    // Add other outbounds like freedom or block if needed
  ]
}
EOF
# Validate JSON syntax (optional but helpful)
if command -v jq &> /dev/null; then
    if ! jq '.' /etc/s-box-ag/sb.json > /dev/null; then
        red "生成的 sing-box 配置文件 (sb.json) 无效！"
        exit 1
    fi
fi
# --- End Create Sing-box Config ---

# --- Start Sing-box Process and Setup Cron ---
yellow "启动 sing-box 进程..."
# Kill existing process just in case before starting new one
pkill -9 -f "/etc/s-box-ag/sing-box run" >/dev/null 2>&1
# Start using nohup and setsid
nohup setsid /etc/s-box-ag/sing-box run -c /etc/s-box-ag/sb.json > /etc/s-box-ag/singbox.log 2>&1 &
echo "$!" > /etc/s-box-ag/sbpid.log
sleep 2 # Give it time to start

# Verify process started
if ! _check_pid "/etc/s-box-ag/sbpid.log"; then
    red "启动 sing-box 进程失败！"
    red "查看日志: cat /etc/s-box-ag/singbox.log"
    del # Clean up
    exit 1
else
    green "sing-box 进程启动成功 (PID: $(cat /etc/s-box-ag/sbpid.log))."
fi

yellow "添加 sing-box 到 crontab 实现开机自启..."
if command -v crontab &> /dev/null; then
    # Remove existing entry first
    (crontab -l 2>/dev/null | grep -v 'sbpid\.log') | crontab -
    # Add new entry
    (crontab -l 2>/dev/null; echo "@reboot /usr/bin/nohup /usr/bin/setsid /etc/s-box-ag/sing-box run -c /etc/s-box-ag/sb.json > /etc/s-box-ag/singbox.log 2>&1 & echo \$! > /etc/s-box-ag/sbpid.log") | crontab -
    green "sing-box Crontab 设置完成。"
else
    yellow "未找到 crontab 命令，无法设置开机自启。请手动配置。"
fi
# --- End Start Sing-box Process ---

# --- Download Cloudflared ---
yellow "正在获取最新的 cloudflared 版本信息..."
cfd_url="https://api.github.com/repos/cloudflare/cloudflared/releases/latest"
argocore=$(curl -Ls $cfd_url | jq -r '.tag_name')

if [[ -z "$argocore" || "$argocore" == "null" ]]; then
  red "无法从 GitHub API 获取最新的 cloudflared 版本号。"
  yellow "尝试使用 jsDelivr 获取版本信息..."
  argocore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/cloudflare/cloudflared | grep -Eo '"[0-9.]+"' | head -n 1 | tr -d '"')
  if [[ -z "$argocore" ]]; then
      red "也无法从 jsDelivr 获取版本号。请检查网络或稍后再试。"
      del # Clean up
      exit 1
  fi
fi

cfd_download_url="https://github.com/cloudflare/cloudflared/releases/download/${argocore}/cloudflared-linux-${cpu}"
echo "下载 cloudflared ${argocore} (${cpu}) 内核..."

if curl -L -o /etc/s-box-ag/cloudflared -# --retry 3 --retry-delay 2 "$cfd_download_url"; then
  chmod +x /etc/s-box-ag/cloudflared
  green "cloudflared 下载成功。"
  if ! /etc/s-box-ag/cloudflared --version &> /dev/null; then
      red "cloudflared 可执行文件校验失败！"
      rm -f /etc/s-box-ag/cloudflared # Clean up bad binary
      del # Clean up
      exit 1
  fi
else
  red "下载 cloudflared 失败。"
  rm -f /etc/s-box-ag/cloudflared # Clean up partial download
  del # Clean up
  exit 1
fi
# --- End Download Cloudflared ---

# --- Start Cloudflared Process and Setup Cron ---
# Kill existing process first
pkill -9 -f "/etc/s-box-ag/cloudflared tunnel" >/dev/null 2>&1

if [[ -n "${ARGO_DOMAIN}" && -n "${ARGO_AUTH}" ]]; then
  name='固定'
  yellow "使用提供的 token 启动 Argo 固定域名隧道..."
  nohup setsid /etc/s-box-ag/cloudflared tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token ${ARGO_AUTH} > /etc/s-box-ag/argo.log 2>&1 &
  echo "$!" > /etc/s-box-ag/sbargopid.log
  echo "${ARGO_DOMAIN}" > /etc/s-box-ag/sbargoym.log
  echo "${ARGO_AUTH}" > /etc/s-box-ag/sbargotoken.log
else
  name='临时'
  yellow "启动 Argo 临时域名隧道..."
  target_port=$(jq -r '.inbounds[0].listen_port' /etc/s-box-ag/sb.json)
  nohup setsid /etc/s-box-ag/cloudflared tunnel --url http://localhost:${target_port} --edge-ip-version auto --no-autoupdate --protocol http2 > /etc/s-box-ag/argo.log 2>&1 &
  echo "$!" > /etc/s-box-ag/sbargopid.log
fi

echo "等待 Argo $name 隧道建立... (最多等待 20 秒)"
success=false
argodomain=""
for i in {1..10}; do
  sleep 2
  # Check if process is still running
  if ! _check_pid "/etc/s-box-ag/sbargopid.log"; then
      red "cloudflared 进程在启动期间意外终止！"
      red "查看日志: cat /etc/s-box-ag/argo.log"
      success=false
      break # Exit loop early
  fi
  # Check for success based on type
  if [[ -n "${ARGO_DOMAIN}" && -n "${ARGO_AUTH}" ]]; then
      if grep -q "Connection .* registered" /etc/s-box-ag/argo.log; then
          argodomain=$(cat /etc/s-box-ag/sbargoym.log 2>/dev/null)
          success=true
          break
      fi
  else
      argodomain=$(grep -o -E 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' /etc/s-box-ag/argo.log | head -n 1 | sed 's|https://||')
      if [[ -n "$argodomain" ]]; then
          success=true
          break
      fi
  fi
  yellow "  ...还在等待 ($i/10)"
done

if $success && [[ -n "$argodomain" ]]; then
  green "Argo $name 隧道申请成功！域名: $argodomain"
else
  red "Argo $name 隧道申请失败。"
  red "查看日志: cat /etc/s-box-ag/argo.log"
  del # Clean up failed setup
  exit 1
fi

yellow "添加 Argo 隧道到 crontab 实现开机自启..."
if command -v crontab &> /dev/null; then
    # Remove existing entry first
    (crontab -l 2>/dev/null | grep -v 'sbargopid\.log') | crontab -
    # Add new entry
    if [[ -n "${ARGO_DOMAIN}" && -n "${ARGO_AUTH}" ]]; then
        (crontab -l 2>/dev/null; echo "@reboot /usr/bin/nohup /usr/bin/setsid /etc/s-box-ag/cloudflared tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token \$(cat /etc/s-box-ag/sbargotoken.log 2>/dev/null) > /etc/s-box-ag/argo.log 2>&1 & echo \$! > /etc/s-box-ag/sbargopid.log") | crontab -
    else
        target_port=$(jq -r '.inbounds[0].listen_port' /etc/s-box-ag/sb.json) # Get port again
        (crontab -l 2>/dev/null; echo "@reboot /usr/bin/nohup /usr/bin/setsid /etc/s-box-ag/cloudflared tunnel --url http://localhost:${target_port} --edge-ip-version auto --no-autoupdate --protocol http2 > /etc/s-box-ag/argo.log 2>&1 & echo \$! > /etc/s-box-ag/sbargopid.log") | crontab -
    fi
    green "Argo Crontab 设置完成。"
else
    yellow "未找到 crontab 命令，无法为 Argo 设置开机自启。请手动配置。"
fi
# --- End Start Cloudflared Process ---

# --- Update agsb Command ---
yellow "创建/更新 agsb 快捷命令..."
if curl -L -o /usr/bin/agsb -# --retry 2 --insecure https://raw.githubusercontent.com/yonggekkk/argosb/main/argosb.sh; then
   chmod +x /usr/bin/agsb
   green "agsb 命令设置完成。"
else
   yellow "无法下载最新脚本以创建 agsb 命令，但安装仍会继续。"
   yellow "您可以稍后手动运行: agsb up"
fi
# --- End Update agsb Command ---

# --- Generate VMess Links ---
yellow "生成 VMess 节点链接..."
> /etc/s-box-ag/jh.txt # Clear existing file

vmess_path="/${UUID}-vm?ed=2048"
common_config() {
  local ps_suffix=$1 add=$2 port=$3 tls_val=$4 sni_val=$5
  local config_json
  config_json=$(jq -nc --arg v "2" --arg ps "vmess-ws${tls_val:+-tls}-argo-${hostname}-${port}-${ps_suffix}" \
                       --arg add "$add" --arg port "$port" --arg id "$UUID" --arg aid "0" \
                       --arg scy "auto" --arg net "ws" --arg type "none" \
                       --arg host "$argodomain" --arg path "$vmess_path" \
                       --arg tls "$tls_val" --arg sni "$sni_val" \
                       --arg alpn "" --arg fp "" \
                       '{v:$v, ps:$ps, add:$add, port:$port, id:$id, aid:$aid, scy:$scy, net:$net, type:$type, host:$host, path:$path, tls:$tls, sni:$sni, alpn:$alpn, fp:$fp}')
  echo "vmess://$(echo "$config_json" | base64 -w 0)" >> /etc/s-box-ag/jh.txt
}

# TLS links (Cloudflare Ports supporting TLS)
common_config "v4" "104.16.0.0" "443" "tls" "$argodomain"
common_config "v4" "104.17.0.0" "8443" "tls" "$argodomain"
common_config "v4" "104.18.0.0" "2053" "tls" "$argodomain"
common_config "v4" "104.19.0.0" "2083" "tls" "$argodomain"
common_config "v4" "104.20.0.0" "2087" "tls" "$argodomain"
common_config "v6" "[2606:4700::]" "2096" "tls" "$argodomain" # IPv6

# Non-TLS links (Cloudflare Ports not supporting TLS)
common_config "v4" "104.21.0.0" "80" "" ""
common_config "v4" "104.22.0.0" "8080" "" ""
common_config "v4" "104.24.0.0" "8880" "" ""
common_config "v4" "104.25.0.0" "2052" "" ""
common_config "v4" "104.26.0.0" "2082" "" ""
common_config "v4" "104.27.0.0" "2086" "" ""
common_config "v6" "[2400:cb00:2049::]" "2095" "" "" # IPv6

green "VMess 节点链接生成完成。"

# Prepare output variables
baseurl=$(base64 -w 0 < /etc/s-box-ag/jh.txt)
line1=$(sed -n '1p' /etc/s-box-ag/jh.txt)
line6=$(sed -n '6p' /etc/s-box-ag/jh.txt) # TLS IPv6
line7=$(sed -n '7p' /etc/s-box-ag/jh.txt) # Non-TLS IPv4
line13=$(sed -n '13p' /etc/s-box-ag/jh.txt) # Non-TLS IPv6
# --- End Generate VMess Links ---


# <<<-------------------- GIST UPLOAD SECTION (via Env Vars) -------------------->>>
# Read Gist ID and GitHub Token from environment variables
# These MUST be set before running the script, e.g.:
# export GIST_ID="your_gist_id"
# export GITHUB_TOKEN="your_github_pat"
# Then run the script, potentially using sudo -E if needed:
# sudo -E bash your_script.sh  OR  sudo -E bash <(wget -qO- ...)

GIST_ID_FROM_ENV="${GIST_ID:-}"           # Read GIST_ID or default to empty
GITHUB_TOKEN_FROM_ENV="${GITHUB_TOKEN:-}" # Read GITHUB_TOKEN or default to empty
GIST_FILENAME="aggregated_nodes.txt"      # Filename within the Gist

# Initialize response_code to indicate skipped state initially
response_code="skipped" # Possible values: skipped, 200 (success), other HTTP codes (failure)

# Check if both variables were successfully read from the environment and are not empty
if [[ -n "$GIST_ID_FROM_ENV" && -n "$GITHUB_TOKEN_FROM_ENV" ]]; then
    yellow "GIST_ID and GITHUB_TOKEN found in environment. Preparing Gist upload..."

    # Construct the JSON payload for the Gist API
    # Using printf for safer variable expansion within JSON
    json_payload=$(printf '{"description": "ArgoSB Aggregated Nodes - %s (%s)","files": {"%s": {"content": "%s"}}}' "$(date '+%Y-%m-%d %H:%M:%S %Z')" "$hostname" "$GIST_FILENAME" "$baseurl")

    # Make the API call to update the Gist
    echo "正在上传到 Gist ID: $GIST_ID_FROM_ENV ..."
    upload_response_code=$(curl -s -o /dev/null -w "%{http_code}" \
         -X PATCH \
         -H "Authorization: token $GITHUB_TOKEN_FROM_ENV" \
         -H "Accept: application/vnd.github.v3+json" \
         -d "$json_payload" \
         "https://api.github.com/gists/$GIST_ID_FROM_ENV")

    # Update response_code based on the curl command result
    response_code=$upload_response_code

    if [[ "$response_code" -eq 200 ]]; then
        green "成功上传聚合节点到 Gist！"
        echo "Gist URL: https://gist.github.com/$GIST_ID_FROM_ENV"
    else
        red "上传到 Gist 失败！HTTP Status Code: $response_code"
        yellow "请检查 Gist ID、GitHub Token (需要 'gist' 权限) 或网络连接。"
    fi
else
    yellow "GIST_ID 或 GITHUB_TOKEN 环境变量未设置或为空。跳过 Gist 上传。"
    # response_code remains "skipped"
fi
# <<<------------------ END GIST UPLOAD SECTION ------------------>>>


# --- Prepare and Display Final Output ---
green "ArgoSB 脚本安装完毕" && sleep 1

# Create the final output file
cat > /etc/s-box-ag/list.txt <<EOF
---------------------------------------------------------
甬哥Github项目: github.com/yonggekkk
甬哥YouTube频道: www.youtube.com/@ygkkk
---------------------------------------------------------
ArgoSB 节点配置信息 (主机名: ${hostname})
Argo 域名: ${argodomain} $([[ -n "${ARGO_DOMAIN}" && -n "${ARGO_AUTH}" ]] && echo "(固定)" || echo "(临时)")
Sing-box vmess 端口: ${port_vm_ws}
Sing-box UUID: ${UUID}
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

$baseurl

---------------------------------------------------------
Gist Upload Status: $( if [[ "$response_code" == "skipped" ]]; then echo "Skipped (Set GIST_ID and GITHUB_TOKEN env vars to enable)"; elif [[ "$response_code" -eq 200 ]]; then echo "Success (https://gist.github.com/$GIST_ID_FROM_ENV)"; else echo "Failed (HTTP $response_code)"; fi )
---------------------------------------------------------
相关快捷方式:
  agsb      显示当前域名及节点信息 (如果脚本正在运行)
  agsb up   升级 ArgoSB 脚本 (下载最新版并替换 /usr/bin/agsb)
  agsb del  卸载 ArgoSB 脚本 (停止进程, 清理文件和 Cron)
---------------------------------------------------------
EOF

# Display the final output from the file
echo "========================================================="
green "ArgoSB 脚本安装/配置完成！节点信息如下："
echo "========================================================="
cat /etc/s-box-ag/list.txt
echo "========================================================="
# --- End Final Output ---

exit 0 # Explicitly exit with success code
