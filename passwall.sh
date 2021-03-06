clear

red='\e[91m'
green='\e[92m'
yellow='\e[93m'
none='\e[0m'



# 按任意键继续
any_key_to_continue() {
	echo -e "\n$red请按任意键继续或 Ctrl + C 退出${none}\n"
	local saved=""
	saved="$(stty -g)"
	stty -echo
	stty cbreak
	dd if=/dev/tty bs=1 count=1 2>/dev/null
	stty -raw
	stty echo
	stty $saved
}
error() {

	echo -e "\n$red 输入错误！$none\n"
	any_key_to_continue

}

# 判断命令是否存在
command_exists() {
	command -v "$@" >/dev/null 2>&1
}

# 判断输入内容是否为数字
is_number() {
	expr "$1" + 1 >/dev/null 2>&1
}

first_character() {
	if [ -n "$1" ]; then
		echo "$1" | cut -c1
	fi
}

#检查是否具有 root 权限
check_root() {
	local user=""
	
	user="$(id -un 2>/dev/null || true)"
	if [ "$user" != "root" ]; then
		echo  "${red}\n权限错误, 请使用 root 用户运行此脚本!${none}\n"
	
		exit 1
	fi
	
	  echo  "$green当前用户是root 用户权限"
	
}

get_os_info() {
	lsb_dist=""
	dist_version=""
	if command_exists lsb_release; then
		lsb_dist="$(lsb_release -si)"
	fi
	if [ -z "$lsb_dist" ] && [ -r /etc/lsb-release ]; then
		lsb_dist="$(. /etc/lsb-release && echo "$DISTRIB_ID")"
	fi
	if [ -z "$lsb_dist" ] && [ -r /etc/debian_version ]; then
		lsb_dist='debian'
	fi
	if [ -z "$lsb_dist" ] && [ -r /etc/fedora-release ]; then
		lsb_dist='fedora'
	fi
	if [ -z "$lsb_dist" ] && [ -r /etc/oracle-release ]; then
		lsb_dist='oracleserver'
	fi
	if [ -z "$lsb_dist" ] && [ -r /etc/centos-release ]; then
		lsb_dist='centos'
	fi
	if [ -z "$lsb_dist" ] && [ -r /etc/redhat-release ]; then
		lsb_dist='redhat'
	fi
	if [ -z "$lsb_dist" ] && [ -r /etc/photon-release ]; then
		lsb_dist='photon'
	fi
	if [ -z "$lsb_dist" ] && [ -r /etc/os-release ]; then
		lsb_dist="$(. /etc/os-release && echo "$ID")"
	fi

	lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"

	if [ "${lsb_dist}" = "redhatenterpriseserver" ]; then
		lsb_dist='redhat'
	fi

	case "$lsb_dist" in
		ubuntu)
			if command_exists lsb_release; then
				dist_version="$(lsb_release --codename | cut -f2)"
			fi
			if [ -z "$dist_version" ] && [ -r /etc/lsb-release ]; then
				dist_version="$(. /etc/lsb-release && echo "$DISTRIB_CODENAME")"
			fi
			;;

		debian|raspbian)
			dist_version="$(cat /etc/debian_version | sed 's/\/.*//' | sed 's/\..*//')"
			case "$dist_version" in
				9)
					dist_version="stretch"
					;;
				8)
					dist_version="jessie"
					;;
				7)
					dist_version="wheezy"
					;;
			esac
			;;

		oracleserver)
			lsb_dist="oraclelinux"
			dist_version="$(rpm -q --whatprovides redhat-release --queryformat "%{VERSION}\n" | sed 's/\/.*//' | sed 's/\..*//' | sed 's/Server*//')"
			;;

		fedora|centos|redhat)
			dist_version="$(rpm -q --whatprovides ${lsb_dist}-release --queryformat "%{VERSION}\n" | sed 's/\/.*//' | sed 's/\..*//' | sed 's/Server*//' | sort | tail -1)"
			;;

		"vmware photon")
			lsb_dist="photon"
			dist_version="$(. /etc/os-release && echo "$VERSION_ID")"
			;;

		*)
			if command_exists lsb_release; then
				dist_version="$(lsb_release --codename | cut -f2)"
			fi
			if [ -z "$dist_version" ] && [ -r /etc/os-release ]; then
				dist_version="$(. /etc/os-release && echo "$VERSION_ID")"
			fi
			;;
	esac

	if [ -z "$lsb_dist" ] || [ -z "$dist_version" ]; then
        echo "$red不能获取系统信息"
		exit 1
	fi
	#echo "$lsb_dist"，"$dist_version"
	 
}
# 获取服务器架构和 passwall 服务端文件后缀名
get_arch() {
	architecture="$(uname -m)"
	case "$architecture" in
		amd64|x86_64)
			spruce_type='linux-amd64'
			file_suffix='linux_amd64'
			;;
		i386|i486|i586|i686|x86)
			spruce_type='linux-386'
			file_suffix='linux_386'
			;;
		*)
			
		echo "$red当前脚本仅支持 32 位 和 64 位系统,你的系统为: $architecture"
		
			exit 1
			;;
	esac
	#echo "$architecture"
}

# 获取服务器的IP地址
get_server_ip() {
	local server_ip=""
	local interface_info=""
    if command_exists ip; then
		interface_info="$(ip addr)"
	elif command_exists ifconfig; then
		interface_info="$(ifconfig)"
	fi

	server_ip=$(echo "$interface_info" | \
		grep -oE "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" | \
		grep -vE "^192\.168|^172\.1[6-9]\.|^172\.2[0-9]\.|^172\.3[0-2]\.|^10\.|^127\.|^255\.|^0\." | \
		head -n 1)

	# 自动获取失败时，通过网站提供的 API 获取外网地址
	if [ -z "$server_ip" ]; then
		 server_ip="$(wget -qO- --no-check-certificate https://ipv4.icanhazip.com)"
	fi

	echo "$server_ip"
}
	is_port() {
		local port="$1"
		is_number "$port" && \
			[ $port -ge 1 ] && [ $port -le 65535 ]
	}

	port_using() {
		local port="$1"

		if command_exists netstat; then
			( netstat -ntul | grep -qE "[0-9:*]:${port}\s" )
		elif command_exists ss; then
			( ss -ntul | grep -qE "[0-9:*]:${port}\s" )
		else
			return 0
		fi

		return $?
	}


# 禁用 selinux
disable_selinux() {
	local selinux_config='/etc/selinux/config'
	if [ -s "$selinux_config" ]; then
		if grep -q "SELINUX=enforcing" "$selinux_config"; then
			sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' "$selinux_config"
			setenforce 0
		fi
	fi
}

# 检测系统




check_sys() {
[[ $(id -u) != 0 ]] && echo -e " \n请使用 ${red}root ${none}用户运行 ${yellow}~(^_^) ${none}\n" && exit 1



if [[ -f /usr/bin/apt-get ]] || [[ -f /usr/bin/yum ]]; then
	if [[ -f /usr/bin/yum ]]; then
		cmd="yum"
	fi
	if [[ -f /usr/bin/apt-get ]]; then
		cmd="apt-get"
	fi
else
	echo -e " \n这个 ${red}脚本${none} 不支持你的系统。 ${yellow}(-_-) ${none}\n" && exit 1
fi
get_os_info
get_arch
}
 v2ray_go(){
 
  if   [[ -f /etc/v2ray ]]; then
               echo -e "\n$green 已经存在V2ray安装，是否卸载...$none\n"		 
		       read -p "(请输入Y/N 卸载): " yn
				 if [ -n "$yn" ]; then
					  #停用并卸载服务（systemd）：
                      systemctl stop v2ray
                      systemctl disable v2ray

                      #停用并卸载服务（sysv）：
                      #service v2ray stop
                      #update-rc.d -f v2ray remove
					  rm -rf /etc/v2ray/*  #(配置文件)
                      rm -rf /usr/bin/v2ray/*  #(程序)
                      rm -rf /var/log/v2ray/*  #(日志)
                      rm -rf /lib/systemd/system/v2ray.service  #(systemd 启动项)
                      rm -rf /etc/init.d/v2ray  #(sysv 启动项)
					  
	             fi
 fi 

 if ! [[ -f /etc/v2ray ]]; then
    date -R
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
	apt-get install curl
    bash <(curl -L -s https://install.direct/go.sh)
 fi 

while true
	do	echo -e "\n$green v2ray已经安装和配置，是否用网站的json文件来替换默认json？...$none\n"
		read -p "(请输入 [s/c/n]): " sc
		if [ -n "$sc" ]; then
			case "$(first_character "$sc")" in
				s|S)
                  mv /etc/v2ray/config.json  /etc/v2ray/config.json.bk
                  if ! wget --no-check-certificate --no-cache -O "/etc/v2ray/config.json" https://raw.githubusercontent.com/judawu/passwall/master/v2ray_server.json; then
                     mv /etc/v2ray/config.json  /etc/v2ray/config.json.bk
		             echo -e "$red 下载config.json 失败$none" 
				   else
				      echo -e "\n$green 系统自动产生uuid并写入json...$none\n"		 
                      
					  sed -in-place -e 's/@@@@-uuid-@@@@/'$(cat /proc/sys/kernel/random/uuid)'/g' /etc/v2ray/config.json
					  
					  read -p "(请输入SS的密码): " v2ray_SSpwd
		              if [ -n "$v2ray_SSpwd" ]; then
					  sed -in-place -e 's/@@@PASSWORD@@@/'$v2ray_SSpwd'/g' /etc/v2ray/config.json
					  res=`echo -n aes-128-gcm:${v2ray_SSpwd}@$(wget -qO- --no-check-certificate https://ipv4.icanhazip.com):10005 | base64 -w 0`
                      link="ss://${res}"
					  echo " ss链接： ${link}"
					  apt install -y qrencode
                      qrencode -o - -t utf8 ${link}
	                  fi
	              fi
				    ;;
				c|C)
				  echo net.ipv4.ip_forward=1 >> /etc/sysctl.conf && sysctl -p
                  mv /etc/v2ray/config.json  /etc/v2ray/config.json.bk
                  if ! wget --no-check-certificate --no-cache -O "/etc/v2ray/config.json" https://raw.githubusercontent.com/judawu/passwall/master/v2ray_client.json; then
                     mv /etc/v2ray/config.json  /etc/v2ray/config.json.bk
		             echo -e "$red 下载config.json 失败$none" 
				   else
				      
				      echo -e "\n$green 请输入你的Domain名和uuid...$none\n"		 
		              read -p "(请输入Domian): " server_domain
					  if [ -n "$server_domain" ]; then
					  sed -in-place -e 's/@@@@-server-@@@@/'$server_domain'/g' /etc/v2ray/config.json
	                  fi
					  read -p "(请输入UUID): "   v2ray_uuid
		              if [ -n "$v2ray_uuid" ]; then
					  sed -in-place -e 's/@@@@-uuid-@@@@/'$v2ray_uuid'/g' /etc/v2ray/config.json
	                  fi
					  read -p "(请输入SS的密码): " v2ray_SSpwd
		              if [ -n "$v2ray_SSpwd" ]; then
					  sed -in-place -e 's/@@@@@-Passwd-@@@@@/'$v2ray_SSpwd'/g' /etc/v2ray/config.json
					  iptable_go
					  tproxyrule_go
					  res=`echo -n aes-128-gcm:${v2ray_SSpwd}@$(wget -qO- --no-check-certificate https://ipv4.icanhazip.com):10005 | base64 -w 0`
                      link="ss://${res}"
					  echo " ss链接： ${link}"
					  apt install -y qrencode
                      qrencode -o - -t utf8 ${link}
	                  fi
  
				 fi
				    ;;		
				*)					
					break
					;;
			esac
		fi
	break
done



while true
	do  echo -e "\n$green 是否安装证书ACME...$none\n"		  
		read -p "(请输入 [y/n]): " yn
		if [ -n "$yn" ]; then
			case "$(first_character "$yn")" in
				y|Y)
					acme_go
					;;				
				*)					
					break
					;;
			esac
		fi
	break
done

while true
	do  echo -e "\n$green 是否安装Ngnix（如果已经安装Caddy或Ngnix），如果是客户端，请忽略...$none\n"		 
		read -p "(请输入 [y/n]): " yn
		if [ -n "$yn" ]; then
			case "$(first_character "$yn")" in
				y|Y)
					ngnix_go
					;;				
				*)					
					break
					;;
			esac
		fi
	break
done


while true
	do  echo -e "\n$green 配置结束了，重启V2ray吧, 可以用service v2ray restart 来启动服务，配置文件在/etc/v2ray/config.json...$none\n"		 
		read -p "(请输入 [y/n]): " yn
		if [ -n "$yn" ]; then
			case "$(first_character "$yn")" in
				y|Y)
					service v2ray restart 
					;;				
				*)					
					break
					;;
			esac
		fi
	break
done

 }
 
  updatev2ray_go(){
  sudo bash <(curl -L -s https://install.direct/go.sh)
  }
  
  updatev2rayconfig_go(){
   if   ![[ -f /etc/v2ray ]]; then
               echo -e "\n$green V2ray没有安装...$none\n"	
			   v2ray_go
   fi
  while true
	do	echo -e "\n$green v2ray已经安装和配置，是否用网站的json_full文件来替换默认json？...$none\n"
		read -p "(请输入 [s/c/n]): " sc
		if [ -n "$sc" ]; then
			case "$(first_character "$sc")" in
				s|S)
                  mv /etc/v2ray/config.json  /etc/v2ray/config.json.bk
                  if ! wget --no-check-certificate --no-cache -O "/etc/v2ray/config.json" https://raw.githubusercontent.com/judawu/passwall/master/v2ray_server_full.json; then
                     mv /etc/v2ray/config.json  /etc/v2ray/config.json.bk
		             echo -e "$red 下载config.json 失败$none" 
				   else
				      echo -e "\n$green 系统自动产生uuid并写入json...$none\n"		 
                      
					  sed -in-place -e 's/@@@@-uuid-@@@@/'$(cat /proc/sys/kernel/random/uuid)'/g' /etc/v2ray/config.json
					  read -p "(请输入user): " v2ray_usr,
					  read -p "(请输入Password): " v2ray_pwd,
		              if [ -n "$v2ray_Usr" ] && [ -n "$v2ray_pwd" ]; then
					  sed -in-place -e 's/@@@@@-User-@@@@@/'$v2ray_pwd'/g' /etc/v2ray/config.json
					  sed -in-place -e 's/@@@@@-Passwd-@@@@@/'$v2ray_usr'/g' /etc/v2ray/config.json
					  res=`echo -n aes-128-gcm:${v2ray_SSpwd}@$(wget -qO- --no-check-certificate https://ipv4.icanhazip.com):10005 | base64 -w 0`
                      link="ss://${res}"
					  echo " ss链接： ${link}"
					  apt install -y qrencode
                      qrencode -o - -t utf8 ${link}
	                  fi
					  echo -e "\n$green v2ray已经更新配置$none\n"
	              fi
				    ;;
				c|C)
				  
                  mv /etc/v2ray/config.json  /etc/v2ray/config.json.bk
                  if ! wget --no-check-certificate --no-cache -O "/etc/v2ray/config.json" https://raw.githubusercontent.com/judawu/passwall/master/v2ray_client_full.json; then
                     mv /etc/v2ray/config.json  /etc/v2ray/config.json.bk
		             echo -e "$red 下载config.json 失败$none" 
				   else
				      
				      echo -e "\n$green 请输入你的Domain名和uuid...$none\n"		 
		              read -p "(请输入Domian): " server_domain
					  if [ -n "$server_domain" ]; then
					  sed -in-place -e 's/@@@@-server-@@@@/'$server_domain'/g' /etc/v2ray/config.json
	                  fi
					  read -p "(请输入UUID): "   v2ray_uuid
		              if [ -n "$v2ray_uuid" ]; then
					  sed -in-place -e 's/@@@@-uuid-@@@@/'$v2ray_uuid'/g' /etc/v2ray/config.json
	                  fi
					  read -p "(请输入User): " v2ray_Usr
		              if [ -n "$v2ray_Usr" ]; then
					  sed -in-place -e 's/@@@@@-User-@@@@@/'$v2ray_SSpwd'/g' /etc/v2ray/config.json
					  fi
					  read -p "(请输入密码): " v2ray_pwd
					  
		              if [ -n "$v2ray_pwd" ]; then
					  sed -in-place -e 's/@@@@@-Passwd-@@@@@/'$v2ray_SSpwd'/g' /etc/v2ray/config.json
					  fi
				     echo "\n$green选择通讯协议"
               	     echo " 1. VMESS+TLS+WS+Nginx"
	                 echo " 2. Socks+TLS"
				     echo " 3. Http+TLS"
				     echo " 4. Vmess+Http伪装"
				     echo " 5. VLESS+H2+TLS"
				     echo " 6. VLESS+TCP+TLS"
                     echo " 7. shadowsocks"
	                 echo
	                 read -p "请选择[1-10]:" v2ray_protocol
	          
                     sed -in-place -e 's/@@@@-A-@@@@/'$v2ray_protocol'/g' /etc/v2ray/config.json
	        		  
					  
                     echo -e "\n$green v2ray已经更新配置，将配置Nginx$none\n"
				      if [ -n "$server_domain" ]; then
			         mv /etc/nginx/sites-available/default   /etc/nginx/sites-available/default.bk 
                     if ! wget --no-check-certificate --no-cache -O "/etc/nginx/sites-available/default" https://raw.githubusercontent.com/judawu/passwall/master/nginx_default_more; then
                     mv /etc/nginx/sites-available/default.bk  /etc/nginx/sites-available/default
				     echo -e "$red 下载Nginx default 失败$none" 
		             else
				     echo -e "\n$green 系统将domain server 写入 /etc/nginx/sites-available/default...$none\n"		 
                     sed -in-place -e 's/@@@@-server-@@@@/'$server_domain'/g' /etc/nginx/sites-available/default
			         fi
	    fi
		          fi
				 ;;
		   *)					
					break
					;;
			esac
	    fi
	break
done
  
  
  }
acme_go(){
 
 if  [[ -f /usr/bin/socat ]]; then
   echo -e "\n$green 已安装依赖socat/netcat...$none\n"   
 else
    if [[ -f /usr/bin/yum ]]; then
		sudo yum -y install socat
		#sudo yum -y install netcat
	fi
    if [[ -f /usr/bin/apt-get ]]; then
		sudo apt-get -y install socat
		#sudo apt-get -y install netcat
    fi
 fi
while true 
  do  
        echo -e "\n$green 请输入你的Domain名，此Domain用于配置TLS，可能不会配置成功...$none\n"		 
		read -p "(请输入): " server_domain
		if [ -n "$server_domain" ]; then
			break
		else
		    continue
		fi
  break
done


while true
	do  
	    echo -e "\n$green请选择是更新证书还是安装证书...$none\n"
        echo " 1. 安装证书"
	    echo " 2. 更新证书"
	    echo
        read -p "请选择[1-2]:" chose
	    case $chose in
	      1)
             curl  https://get.acme.sh | sh
		     sudo ~/.acme.sh/acme.sh --issue -d $server_domain --standalone -k ec-256
			 sudo ~/.acme.sh/acme.sh --installcert -d $server_domain --fullchainpath /etc/v2ray/v2ray.crt --keypath /etc/v2ray/v2ray.key --ecc
		     break
		     ;;
	      2)
		     sudo ~/.acme.sh/acme.sh --renew -d $server_domain  --force --ecc
		     break
		     ;;	
	      *)
		     break
		     ;;
	   esac
done

}


ssr_go() {
 echo -e "\n$green 不好意思，SSR我还没有写部署步骤，可以开启V2ray的SS进行配置，路径为/etc/v2ray/config.json...$none\n"
    
}
trojan_go() {
 echo -e "\n$green 不好意思，TROJAN只有安装...$none\n"
 sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/trojan-gfw/trojan-quickstart/master/trojan-quickstart.sh)"
# systemctl  start/stop/status trojan.service
# 配置/usr/local/etc/trojan/config.json， /usr/local/bin/trojan，我默认开启了客户端开启config.json的端口10010， 然后在v2ray客户端里面通过outbounds socks调用trojan 来实现分流
echo -e "\n$green 配置/usr/local/etc/trojan/config.json...$none\n"
echo -e "\n$green 在v2ray客户端里面通过outbounds socks调用trojan 来实现分流...$none\n"
}

wireguard_go() {
 echo -e "\n$green 不好意思，安装wireguard，并配置V2ray客户端将流量转发给wireguard...$none\n"
 sudo apt install wireguard
 
#echo "deb http://deb.debian.org/debian buster-backports main" >/etc/apt/sources.list.d/backports.list
#apt-get update
cd /etc/wireguard/
umask 077
#wg genkey > private
wg genkey | tee sprivatekey | wg pubkey > spublickey
wg genkey | tee cprivatekey | wg pubkey > cpublickey


while true
	do  echo -e "\n$green ，配置文件在/etc/wireguard/wg0.conf...$none\n"		 
		read -p "(请输入Server/Client [s/c]): " sc
		if [ -n "$sc" ]; then
			case "$(first_character "$sc")" in
				s|S)
# 井号开头的是注释说明，用该命令执行后会自动过滤注释文字。
# 下面加粗的这一大段都是一个代码！请把下面几行全部复制，然后粘贴到 SSH软件中执行，不要一行一行执行！
 
echo "[Interface]
# 服务器的私匙，对应客户端配置中的公匙（自动读取上面刚刚生成的密匙内容）
PrivateKey = $(cat sprivatekey)
# 本机的内网IP地址，一般默认即可，除非和你服务器或客户端设备本地网段冲突
Address = 192.168.121.1/24
# 运行 WireGuard 时要执行的 iptables 防火墙规则，用于打开NAT转发之类的。因为我们是v2ray转发，这里不配置
# 如果你的服务器主网卡名称不是 eth0 ，那么请修改下面防火墙规则中最后的 eth0 为你的主网卡名称。
#PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
# 停止 WireGuard 时要执行的 iptables 防火墙规则，用于关闭NAT转发之类的。因为我们是v2ray转发，这里不配置
# 如果你的服务器主网卡名称不是 eth0 ，那么请修改下面防火墙规则中最后的 eth0 为你的主网卡名称。
#PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
# 服务端监听端口，可以自行修改
ListenPort = 10020 
#设置服务器的监听端口，注意v2ray 需要通过socks来转发到这里
# 服务端请求域名解析 DNS
   DNS = 8.8.8.8
# 保持默认
   MTU = 1420
[Peer]
# 代表客户端配置，每增加一段 [Peer] 就是增加一个客户端账号
# 该客户端账号的公匙，对应客户端配置中的私匙（自动读取上面刚刚生成的密匙内容）
PublicKey = $(cat cpublickey)
# 该客户端账号的内网IP地址
AllowedIPs = 192.168.121.2/24 
Endpoint = 192.168.121.2:10021
"|sed '/^#/d;/^\s*$/d' > wg0.conf
 	
					;;	

				c|C)
echo "[Interface]
# 客户端的私匙，对应服务器配置中的客户端公匙（自动读取上面刚刚生成的密匙内容）
PrivateKey = $(cat cprivatekey)
# 客户端的内网IP地址
Address = 192.168.121.2/24
ListenPort = 10021 设置客户端的监听端口，注意v2ray 需要通过socks来转发到这里
# 解析域名用的DNS
DNS = 8.8.8.8
# 保持默认
MTU = 1420
[Peer]
# 服务器的公匙，对应服务器的私匙（自动读取上面刚刚生成的密匙内容）
PublicKey = $(cat spublickey)
# 服务器地址和端口，下面的 X.X.X.X 记得更换为你的服务器公网IP，端口请填写服务端配置时的监听端口
Endpoint = 192.168.121.1:10020
# 因为是客户端，这里要注意只接受通过本机的端口10021转发过来的数据吧
#AllowedIPs = 0.0.0.0/0, ::0/0
AllowedIPs = 192.168.121.1/24
# 保持连接，如果客户端或服务端是 NAT 网络(比如国内大多数家庭宽带没有公网IP，都是NAT)，那么就需要添加这个参数定时链接服务端(单位：秒)，如果你的服务器和你本地都不是 NAT 网络，那么建议不使用该参数（设置为0，或客户端配置文件中删除这行）
PersistentKeepalive = 25"|sed '/^#/d;/^\s*$/d' > client.conf					
					;;	
				*)					
					break
					;;
			esac
		fi
	break
done
#sudo wg-quick up /etc/wireguard/wg0.conf
# ip link add wg0 type wireguard
# wg setconf wg0 /dev/fd/63
# ip -4 address add 192.168.121.2/24 dev wg0
# ip link set mtu 1420 up dev wg0
# resolvconf -a wg0 -m 0 -x
# ip link delete dev wg0

#ip link add dev wg0 type wireguard
#ip address add  192.168.121.102/24 dev wg0
#wg set wg0 private-key ./private
#ip addr
#wg-quick up wg0
# 执行命令后，输出示例如下（仅供参考）
 
 ip link add wg0 type wireguard
 wg setconf wg0 /etc/wireguard/wg0.conf
ip address add 192.168.121.2/24 dev wg0

 ip link set mtu 1420 dev wg0
 ip link set wg0 up
 
 lsmod | grep wireguard
#首先，检查下 ip 转发是否已开启：
sysctl net.ipv4.ip_forward
#如果等于 1 说明已经开启，否则可以使用：
#sysctl net.ipv4.ip_forward=1
#来临时开启，如果想永久生效，需要编辑 /etc/sysctl.conf 文件，查找到 net.ipv4.ip_forward 这一行，把最前端的 # #号（注释）去掉，如果其值不为 1 的，改成 1。如果找不到，就把 net.ipv4.ip_forward=1 加在文件最下面。
#然后使用命令 sysctl -p 来使其生效。
#接下来检查下 iptables 里 filter 表的 FORWARD 链的 policy 是否为 ACCEPT：
iptables -t filter -L FORWARD
#如果 policy 为 DROP，需要允许 wg0 接口才行：
iptables -t filter -A FORWARD -i wg0 -j ACCEPT
iptables -t filter -A FORWARD -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT
#然后看下 nat 表的 POSTROUTING 链里是否已经做了出口的 NAT 了（这里假设服务器上连接外网的接口是 eth0）：
iptables -t nat -L POSTROUTING -v
#如果还没有，使用以下命令加上：
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
#PS：如果出口不是 eth0 接口的，把 eth0 换成正真的出口接口

#在服务器设置好后，还要在本地加上路由，把流量转发到 wg0 接口上。

#本地路由
#ip route add <endpoint>/32 via <出口接口的网关IP> dev <出口接口>
#ip route add default via 192.168.128.1 dev wg0 src 192.168.128.254
#配置好后，可以在本地 ping 下 8.8.8.8，如果 ping 的通，并且 tracepath 8.8.8.8 的路由里有 192.168.128.1，说明已经通了
 
# 如果此处没有报错：RTNETLINK answers: Operation not supported，且输入内容差不多，那么说明启动成功了！


}

ngnix_go() {

if  [[ -f /etc/nginx/sites-available ]]; then
    echo -e "\n$green nginx已经安装和配置过了"
else
  if [[ -f /usr/bin/yum ]]; then
		sudo yum -y install nginx
		
  fi
  if [[ -f /usr/bin/apt-get ]]; then
		sudo apt-get -y install nginx
  fi
fi
while true
	do	
	    echo -e "\n$green nginx已经安装和配置，是否用网站的配置文件来替换默认配置？...$none\n"
		read -p "(请输入域名 [server_domain]): " server_domain
		if [ -n "$server_domain" ]; then
			mv /etc/nginx/sites-available/default   /etc/nginx/sites-available/default.bk 
            if ! wget --no-check-certificate --no-cache -O "/etc/nginx/sites-available/default" https://raw.githubusercontent.com/judawu/passwall/master/nginx_default; then
                mv /etc/nginx/sites-available/default.bk  /etc/nginx/sites-available/default
				echo -e "$red 下载Nginx default 失败$none" 
		    else
				echo -e "\n$green 系统将domain server 写入 /etc/nginx/sites-available/default...$none\n"		 
                sed -in-place -e 's/@@@@-server-@@@@/'$server_domain'/g' /etc/nginx/sites-available/default
			fi
	    fi
 			
	break
done

while true
	do  echo -e "\n$green 配置结束了，重启nginx吧, 可以用service nginx restart 来启动服务，建议先不要启动，修改配置文件在/etc/nginx/sites-available/default...$none\n"		 
		read -p "(请输入 [y/n]): " yn
		if [ -n "$yn" ]; then
			case "$(first_character "$yn")" in
				y|Y)
					service nginx restart 
					;;				
				*)					
					break
					;;
			esac
		fi
	break
done
}
caddy_go() {
   echo -e "\n$green 不好意思，Caddy我还没有写部署步骤...$none\n"
}
appache_go() {
  echo -e "\n$green 不好意思，appache我还没有写部署步骤...$none\n"

#查看apache2安装包信息，appache2放在/etc/apache2/，用conf-available查看可用conf，用config-enabled这一对命令来启用conf
#apt-cache show apache2
#探测一下
#namp 127.0.0.1
#安装apache2
#sudo apt-get intall apache2
#namp 127.0.0.1
#cd /etc/apache2
#启用appache2模块ssl
#sudo a2enmod ssl
#关闭appache2模块ssl
#sudo a2dismod ssl

#配置appache建立网站，先查看网站哪些启动了#
#ll site-available
#ll site-enabled
#启用appache2网站
#sudo a2ensite 000-default
#配置网站信息
#sudo nano  site-available/mysite。conf

#sudo mkdir -p /var/www/mysite
#sudo chown user:password +R  /var/www/mysite/
#cd  /var/www/mysite
#nano index.html

#sudo a2ensite mysite
#重启appache2
#sudo service appche2 restart

}
website_go() {
      echo -e "\n$green 网站部署没用弄，搞了简单的网页放在/var/www/html下面做域名伪装吧，并部署探测工具dig...$none\n"
	  mv /var/www/html/index.nginx-debian.html   /var/www/html/index.nginx-debian.html.bk
                  if ! wget --no-check-certificate --no-cache -O "/var/www/html/index.html" https://raw.githubusercontent.com/judawu/passwall/master/index.html; then
                     mv index.nginx-debian.html.bk  index.nginx-debian.html
		             echo -e "$red 下载index.html失败,你自己做个伪装吧 $none" 
	              fi
if ! [[ -f /usr/bin/dig ]]; then
  if [[ -f /usr/bin/yum ]]; then
		sudo yum -y install dnsutils -y
		
  fi
  if [[ -f /usr/bin/apt-get ]]; then
		sudo apt-get -y install dnsutils -y
  fi
fi	  
   #dig www.google.com @127.0.0.1 -p 53
}
bbr_go() {
  echo -e "\n$green 只针对Debian开启系统自带的BBR,/etc/sysctl.conf...$none\n"
if [[ -f /etc/debian_version ]]; then

cat >>/etc/sysctl.conf<<EOF
      net.core.default_qdisc=fq
      net.ipv4.tcp_congestion_control=bbr
EOF
#echo 'net.core.default_qdisc=fq'>>/etc/sysctl.conf
#echo 'net.ipv4.tcp_congestion_control=bbr'>>/etc/sysctl.conf
sysctl -p
fi
}

iptable_go() {
# 设置wireguard策略路由
# wg set wg0 fwmark 51820
# ip -4 route add 0.0.0.0/0 dev wg0 table 51820
# ip -4 rule add not fwmark 51820 table 51820
#resolvconf -a wg0  < /etc/wireguard/wgdns.conf



#iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
#iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
#iptables -A INPUT -p udp -m udp --dport 51820 -m conntrack --ctstate NEW -j ACCEPT
#iptables -A INPUT -s 10.200.200.0/24 -p tcp -m tcp --dport 53 -m conntrack --ctstate NEW -j ACCEPT
#iptables -A INPUT -s 10.200.200.0/24 -p udp -m udp --dport 53 -m conntrack --ctstate NEW -j ACCEPT
#iptables -A FORWARD -i wg0 -o wg0 -m conntrack --ctstate NEW -j ACCEPT
#iptables -t nat -A POSTROUTING -s 10.200.200.0/24 -o ens3 -j MASQUERADE



ip rule add fwmark 1 table 100
ip route add local 0.0.0.0/0 dev lo table 100

# 代理局域网设备
iptables -t mangle -N V2RAY
iptables -t mangle -A V2RAY -d 127.0.0.1/32 -j RETURN
iptables -t mangle -A V2RAY -d 224.0.0.0/4 -j RETURN
iptables -t mangle -A V2RAY -d 255.255.255.255/32 -j RETURN
iptables -t mangle -A V2RAY -d 192.168.0.0/16 -p tcp -j RETURN # 直连局域网，避免 V2Ray 无法启动时无法连网关的 SSH，如果你配置的是其他网段（如 10.x.x.x 等），则修改成自己的
iptables -t mangle -A V2RAY -d 192.168.0.0/16 -p udp ! --dport 53 -j RETURN # 直连局域网，53 端口除外（因为要使用 V2Ray 的 
iptables -t mangle -A V2RAY -p udp -j TPROXY --on-port 12345 --tproxy-mark 1 # 给 UDP 打标记 1，转发至 12345 端口
iptables -t mangle -A V2RAY -p tcp -j TPROXY --on-port 12345 --tproxy-mark 1 # 给 TCP 打标记 1，转发至 12345 端口
iptables -t mangle -A PREROUTING -j V2RAY # 应用规则

# 代理网关本机
iptables -t mangle -N V2RAY_MASK
iptables -t mangle -A V2RAY_MASK -d 224.0.0.0/4 -j RETURN
iptables -t mangle -A V2RAY_MASK -d 255.255.255.255/32 -j RETURN
iptables -t mangle -A V2RAY_MASK -d 192.168.0.0/16 -p tcp -j RETURN # 直连局域网
iptables -t mangle -A V2RAY_MASK -d 192.168.0.0/16 -p udp ! --dport 53 -j RETURN # 直连局域网，53 端口除外（因为要使用 V2Ray 的 DNS）
iptables -t mangle -A V2RAY_MASK -j RETURN -m mark --mark 0xff    # 直连 SO_MARK 为 0xff 的流量(0xff 是 16 进制数，数值上等同与上面V2Ray 配置的 255)，此规则目的是避免代理本机(网关)流量出现回环问题
iptables -t mangle -A V2RAY_MASK -p udp -j MARK --set-mark 1   # 给 UDP 打标记,重路由
iptables -t mangle -A V2RAY_MASK -p tcp -j MARK --set-mark 1   # 给 TCP 打标记，重路由
iptables -t mangle -A OUTPUT -j V2RAY_MASK # 应用规则

#将 iptables 规则保存到 /etc/iptables/rules.v4
mkdir -p /etc/iptables && iptables-save > /etc/iptables/rules.v4

}

tproxyrule_go() 
{
#在 /etc/systemd/system/ 目录下创建一个名为 tproxyrule.service
cat >>/etc/systemd/system/tproxyrule.service <<EOF
[Unit]
Description=Tproxy rule
After=network.target
Wants=network.target

[Service]

Type=oneshot
#注意分号前后要有空格
ExecStart=/sbin/ip rule add fwmark 1 table 100 ; /sbin/ip route add local 0.0.0.0/0 dev lo table 100 ; /sbin/iptables-restore /etc/iptables/rules.v4

[Install]
WantedBy=multi-user.target
EOF
#行下面的命令使 tproxyrule.service 可以开机自动运行
systemctl enable tproxyrule
}
udpspd2raw_go() {

wget https://raw.githubusercontent.com/judawu/passwall/master/udpspd2raw.sh && chmod +x ./udpspd2raw.sh && bash ./udpspd2raw.sh
}

kcprun_go() {

    echo -e "\n$green 不好意思，kcprun我还没有写部署步骤...$none\n"
}




check_sys
echo -e "\n$green 你的系统架构是$architecture，软件系统是$lsb_dist，$dist_version...$none\n"
echo -e "\n$green当前服务器IP是...$none\n"
get_server_ip	

while :; do
	echo
	echo -e "\n$green........... V2ray/SSR/Trojan快速部署........$none\n"
	echo
	echo " 1. 安装和部署V2ray"
	echo " 2. 安装和部署SSR"
	echo " 3. 安装和部署Trojan"
	echo " 4. 安装和部署Ngnix"
	echo " 5. 安装和部署Caddy"
	echo " 6. 安装和部署acme TLS证书"
	echo " 7. 安装和部署appache"
	echo " 8. 安装和部署bbr"
	echo " 9. 安装和部署伪装网站,探测工具等"
	echo " 10. 安装和部署udpspeed，upd2raw"
	echo " 11. 安装和部署kcprun"
	echo " 12. 更新V2ray"
	echo " 13. 更新V2ray配置文件为Full"
	echo " 14. 安装wireguard"
	echo
	read -p "请选择[1-10]:" choose
	case $choose in
	1)
        v2ray_go
		break
		;;
	2)
		ssr_go
		break
		;;
	3)
		trojan_go
		break
		;;
	4)
		ngnix_go
		break
		;;	
	5)
		caddy_go
		9break
		;;
	6)
		acme_go
		break
		;;
	7)
		appache_go
		break
		;;
	8)
		bbr_go
		break
		;;	
	9)
		website_go
		break
		;;
	10)
		udpspd2raw_go
		break
		;;			
	11)
		kcprun_go
		break
		;;
	12)
		UpdateV2ray_go
		break
		;;
	13)
		UpdateV2rayConfig_go
		break
		;;
	14)
		wireguard_go
		break
		;;
	*)
		any_key_to_continue
		;;
	esac
	
done


