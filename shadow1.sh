#!/bin/bash
# Script tự động cài đặt Shadowsocks trên Ubuntu
# Sử dụng: chmod +x install_shadowsocks.sh && sudo ./install_shadowsocks.sh

# Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then
  echo "Vui lòng chạy script với quyền sudo!"
  exit 1
fi

# Cập nhật repository (không upgrade hệ thống)
echo "Đang cập nhật danh sách package..."
apt-get update -y

# Cài đặt các gói cần thiết
echo "Đang cài đặt các gói cần thiết..."
apt-get install -y python3 python3-pip python3-setuptools git libsodium-dev qrencode curl jq

# Tạo port ngẫu nhiên (1024-65535)
server_port=$(shuf -i 10000-65000 -n 1)
echo "Đã tạo port ngẫu nhiên: $server_port"

# Tạo mật khẩu ngẫu nhiên
password=$(tr -dc 'A-Za-z0-9!@#$%^&*()' </dev/urandom | head -c 16)
echo "Đã tạo mật khẩu ngẫu nhiên: $password"

# Phương thức mã hóa mặc định là chacha20
method="chacha20-ietf-poly1305"

# Lấy địa chỉ IP public
server_ip=$(curl -s https://api.ipify.org)
if [ -z "$server_ip" ]; then
  server_ip=$(curl -s http://ifconfig.me)
fi

if [ -z "$server_ip" ]; then
  read -p "Không thể tự động lấy IP. Vui lòng nhập IP của server: " server_ip
fi

# Hỏi tên cho cấu hình SSR
read -p "Nhập tên cho cấu hình SSR (mặc định: MySSR): " ssr_name
ssr_name=${ssr_name:-MySSR}

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

# Cài đặt SSR
echo "Đang cài đặt ShadowsocksR..."

# Tải và cài đặt ShadowsocksR
cd /usr/local/
git clone https://github.com/shadowsocksrr/shadowsocksr.git
cd shadowsocksr
bash initcfg.sh

# Chọn protocol và obfs cho SSR
protocol="origin"
obfs="plain"

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
    "protocol": "$protocol",
    "protocol_param": "",
    "obfs": "$obfs",
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

# Chuẩn bị thông tin cho SSR link
ssr_password=$(echo -n "$password" | base64 | tr -d '\n')
ssr_remarks=$(echo -n "$ssr_name" | base64 | tr -d '\n')
ssr_protocol_param=""
ssr_obfs_param=""

# Tạo link SSR với tên do người dùng nhập
ssr_link="ssr://$server_ip:$server_port:$protocol:$method:$obfs:$ssr_password/?remarks=$ssr_remarks&protoparam=$ssr_protocol_param&obfsparam=$ssr_obfs_param"

# Hiển thị thông tin Shadowsocks
base64_str=$(echo -n "$method:$password@$server_ip:$server_port" | base64 | tr -d '\n')
ss_link="ss://$base64_str#$ssr_name"

# In thông tin
echo "===================================="
echo "Cài đặt hoàn tất! Shadowsocks và ShadowsocksR đã được cài đặt và đang chạy."
echo "===================================="
echo "Thông tin kết nối:"
echo "Server IP: $server_ip"
echo "Server Port: $server_port"
echo "Password: $password"
echo "Encryption Method: $method"
echo "Protocol: $protocol"
echo "Obfs: $obfs"
echo "Remarks: $ssr_name"
echo "===================================="
echo "Shadowsocks Link: $ss_link"
echo "===================================="
echo "Shadowsocks QR Code:"
echo -n "$ss_link" | qrencode -t UTF8
echo "===================================="
echo "SSR Link: $ssr_link"
echo "===================================="
echo "SSR QR Code:"
echo -n "$ssr_link" | qrencode -t UTF8
echo "===================================="

echo "Trạng thái dịch vụ Shadowsocks:"
systemctl status shadowsocks --no-pager

echo "Trạng thái dịch vụ ShadowsocksR:"
systemctl status ssr --no-pager

echo "Lưu ý: Port đã được tạo ngẫu nhiên và có thể bị chặn bởi tường lửa."
echo "Để mở port trên tường lửa UFW, chạy: sudo ufw allow $server_port/tcp && sudo ufw allow $server_port/udp"

# Lưu thông tin vào file
cat > shadowsocks_info.txt << EOF
=== THÔNG TIN KẾT NỐI SHADOWSOCKS ===
Server: $server_ip
Port: $server_port
Password: $password
Method: $method
Protocol: $protocol
Obfs: $obfs
Remarks: $ssr_name

Shadowsocks Link: $ss_link
SSR Link: $ssr_link
EOF

echo "Thông tin kết nối đã được lưu vào file shadowsocks_info.txt"
