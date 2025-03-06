#!/bin/bash
# Script tự động cài đặt Shadowsocks trên Ubuntu
# Sử dụng: chmod +x install_shadowsocks.sh && sudo ./install_shadowsocks.sh

# Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then
  echo "Vui lòng chạy script với quyền sudo!"
  exit 1
fi

# Cập nhật hệ thống
echo "Đang cập nhật hệ thống..."
apt-get update -y
apt-get upgrade -y

# Cài đặt các gói cần thiết
echo "Đang cài đặt các gói cần thiết..."
apt-get install -y python3 python3-pip python3-setuptools git libsodium-dev qrencode curl jq

# Hỏi thông tin cấu hình
read -p "Nhập port server (mặc định: 8388): " server_port
server_port=${server_port:-8388}

read -p "Nhập mật khẩu (mặc định: tạo ngẫu nhiên): " password
if [ -z "$password" ]; then
  password=$(tr -dc 'A-Za-z0-9!@#$%^&*()' </dev/urandom | head -c 16)
  echo "Đã tạo mật khẩu ngẫu nhiên: $password"
fi

read -p "Nhập phương thức mã hóa (mặc định: aes-256-gcm): " method
method=${method:-aes-256-gcm}

# Lấy địa chỉ IP public
server_ip=$(curl -s https://api.ipify.org)
if [ -z "$server_ip" ]; then
  server_ip=$(curl -s http://ifconfig.me)
fi

if [ -z "$server_ip" ]; then
  read -p "Không thể tự động lấy IP. Vui lòng nhập IP của server: " server_ip
fi

# Cài đặt Shadowsocks
echo "Đang cài đặt Shadowsocks..."
pip3 install https://github.com/shadowsocks/shadowsocks/archive/master.zip

# Tạo thư mục cấu hình
mkdir -p /etc/shadowsocks

# Tạo file cấu hình
echo "Đang tạo file cấu hình..."
cat > /etc/shadowsocks/config.json << EOF
{
    "server": "0.0.0.0",
    "server_port": $server_port,
    "password": "$password",
    "method": "$method",
    "timeout": 300,
    "fast_open": true
}
EOF

# Tạo service để chạy Shadowsocks như một dịch vụ
echo "Tạo service systemd cho Shadowsocks..."
cat > /etc/systemd/system/shadowsocks.service << EOF
[Unit]
Description=Shadowsocks Server
After=network.target

[Service]
ExecStart=/usr/local/bin/ssserver -c /etc/shadowsocks/config.json
Restart=on-abort

[Install]
WantedBy=multi-user.target
EOF

# Reload daemon, enable và start service
systemctl daemon-reload
systemctl enable shadowsocks
systemctl start shadowsocks

# Cài đặt SSR nếu được yêu cầu
read -p "Bạn có muốn cài đặt ShadowsocksR không? (y/n, mặc định: n): " install_ssr
install_ssr=${install_ssr:-n}

if [[ "$install_ssr" == "y" || "$install_ssr" == "Y" ]]; then
  echo "Đang cài đặt ShadowsocksR..."
  
  # Tải và cài đặt ShadowsocksR
  cd /usr/local/
  git clone https://github.com/shadowsocksrr/shadowsocksr.git
  cd shadowsocksr
  bash initcfg.sh
  
  # Tạo cấu hình SSR
  cat > /usr/local/shadowsocksr/user-config.json << EOF
{
    "server": "0.0.0.0",
    "server_ipv6": "::",
    "server_port": $server_port,
    "local_address": "127.0.0.1",
    "local_port": 1080,
    "password": "$password",
    "method": "$method",
    "protocol": "origin",
    "protocol_param": "",
    "obfs": "plain",
    "obfs_param": "",
    "speed_limit_per_con": 0,
    "speed_limit_per_user": 0,
    "additional_ports": {},
    "timeout": 300,
    "udp_timeout": 60,
    "dns_ipv6": false,
    "connect_verbose_info": 0,
    "redirect": "",
    "fast_open": true
}
EOF

  # Tạo service SSR
  cat > /etc/systemd/system/ssr.service << EOF
[Unit]
Description=ShadowsocksR Server
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/shadowsocksr/shadowsocks/server.py -c /usr/local/shadowsocksr/user-config.json
Restart=on-abort

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable ssr
  systemctl start ssr
  
  # Tạo link SSR
  protocol="origin"
  obfs="plain"
  ssr_password=$(echo -n "$password" | base64 | tr -d '\n')
  ssr_link="ssr://$server_ip:$server_port:$protocol:$method:$obfs:$ssr_password/?remarks=SSRServer"
  
  # Hiển thị thông tin SSR
  echo "===================================="
  echo "Thông tin ShadowsocksR của bạn:"
  echo "===================================="
  echo "Server IP: $server_ip"
  echo "Server Port: $server_port"
  echo "Password: $password"
  echo "Encryption Method: $method"
  echo "Protocol: $protocol"
  echo "Obfs: $obfs"
  echo "===================================="
  echo "SSR Link: $ssr_link"
  echo "===================================="
  echo "SSR QR Code:"
  echo -n "$ssr_link" | qrencode -t UTF8
  echo "===================================="
fi

# Hiển thị thông tin Shadowsocks
base64_str=$(echo -n "$method:$password@$server_ip:$server_port" | base64 | tr -d '\n')
ss_link="ss://$base64_str"

echo "===================================="
echo "Cài đặt hoàn tất! Shadowsocks đã được cài đặt và đang chạy."
echo "===================================="
echo "Thông tin kết nối Shadowsocks:"
echo "Server IP: $server_ip"
echo "Server Port: $server_port"
echo "Password: $password"
echo "Encryption Method: $method"
echo "===================================="
echo "Shadowsocks Link: $ss_link"
echo "===================================="
echo "Shadowsocks QR Code:"
echo -n "$ss_link" | qrencode -t UTF8
echo "===================================="

echo "Trạng thái dịch vụ Shadowsocks:"
systemctl status shadowsocks --no-pager

echo "Để kiểm tra cấu hình, chạy: nano /etc/shadowsocks/config.json"
echo "Để khởi động lại dịch vụ sau khi thay đổi cấu hình, chạy: systemctl restart shadowsocks"

if [[ "$install_ssr" == "y" || "$install_ssr" == "Y" ]]; then
  echo "Trạng thái dịch vụ ShadowsocksR:"
  systemctl status ssr --no-pager
  echo "Để kiểm tra cấu hình SSR, chạy: nano /usr/local/shadowsocksr/user-config.json"
  echo "Để khởi động lại dịch vụ SSR, chạy: systemctl restart ssr"
fi
