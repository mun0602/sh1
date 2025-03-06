#!/bin/bash
# Script tự động cài đặt Shadowsocks qua Sing-Box
# Sử dụng: chmod +x install_shadowsocks_singbox.sh && sudo ./install_shadowsocks_singbox.sh

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
apt-get install -y curl wget jq qrencode unzip

# Tạo port ngẫu nhiên (1024-65535)
server_port=$(shuf -i 10000-65000 -n 1)
echo "Đã tạo port ngẫu nhiên: $server_port"

# Tạo mật khẩu ngẫu nhiên
password=$(tr -dc 'A-Za-z0-9!@#$%^&*()' </dev/urandom | head -c 16)
echo "Đã tạo mật khẩu ngẫu nhiên: $password"

# Phương thức mã hóa mặc định là chacha20
method="chacha20-poly1305"

# Lấy địa chỉ IP public
server_ip=$(curl -s https://api.ipify.org)
if [ -z "$server_ip" ]; then
  server_ip=$(curl -s http://ifconfig.me)
fi

if [ -z "$server_ip" ]; then
  read -p "Không thể tự động lấy IP. Vui lòng nhập IP của server: " server_ip
fi

# Hỏi tên cho cấu hình
read -p "Nhập tên cho cấu hình (mặc định: MyShadowsocks): " config_name
config_name=${config_name:-MyShadowsocks}

# Tạo thư mục cài đặt
mkdir -p /usr/local/bin
mkdir -p /usr/local/etc/sing-box
mkdir -p /var/log/sing-box

# Tải và cài đặt Sing-Box bản mới nhất
echo "Đang tải Sing-Box..."
latest_version=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep "tag_name" | awk -F'"' '{print $4}')
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        ARCH="amd64"
        ;;
    aarch64)
        ARCH="arm64"
        ;;
    armv7l)
        ARCH="armv7"
        ;;
    *)
        echo "Kiến trúc $ARCH không được hỗ trợ."
        exit 1
        ;;
esac

download_url="https://github.com/SagerNet/sing-box/releases/download/${latest_version}/sing-box-${latest_version#v}-linux-${ARCH}.tar.gz"
wget -O /tmp/sing-box.tar.gz $download_url

# Giải nén và cài đặt
tar -xzf /tmp/sing-box.tar.gz -C /tmp
cp /tmp/sing-box-${latest_version#v}-linux-${ARCH}/sing-box /usr/local/bin/
chmod +x /usr/local/bin/sing-box

# Tạo file cấu hình Sing-Box với Shadowsocks
cat > /usr/local/etc/sing-box/config.json << EOF
{
  "log": {
    "level": "info",
    "output": "/var/log/sing-box/sing-box.log",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "::",
      "listen_port": ${server_port},
      "method": "${method}",
      "password": "${password}"
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

# Tạo service systemd
cat > /etc/systemd/system/sing-box.service << EOF
[Unit]
Description=Sing-Box Service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true
ExecStart=/usr/local/bin/sing-box run -c /usr/local/etc/sing-box/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

# Reload daemon, enable và start service
systemctl daemon-reload
systemctl enable sing-box
systemctl start sing-box

# Tạo URI và QR code cho Shadowsocks
ss_base64=$(echo -n "${method}:${password}" | base64 | tr -d '\n')
ss_link="ss://${ss_base64}@${server_ip}:${server_port}#${config_name}"

# Tạo URI và QR code cho ShadowsocksR (tương thích)
# Encode password và remarks để tạo uri SSR
ssr_password=$(echo -n "$password" | base64 | tr -d '\n')
ssr_remarks=$(echo -n "$config_name" | base64 | tr -d '\n')
ssr_protocol="origin"
ssr_obfs="plain"
ssr_link="ssr://${server_ip}:${server_port}:${ssr_protocol}:${method}:${ssr_obfs}:${ssr_password}/?remarks=${ssr_remarks}"

# In thông tin
echo "===================================="
echo "Cài đặt hoàn tất! Shadowsocks (qua Sing-Box) đã được cài đặt và đang chạy."
echo "===================================="
echo "Thông tin kết nối Shadowsocks:"
echo "Server IP: $server_ip"
echo "Server Port: $server_port"
echo "Password: $password"
echo "Method: $method"
echo "===================================="
echo "Shadowsocks Link: $ss_link"
echo "===================================="
echo "Shadowsocks QR Code:"
echo -n "$ss_link" | qrencode -t UTF8
echo "===================================="
echo "SSR Link (tương thích): $ssr_link"
echo "===================================="
echo "SSR QR Code:"
echo -n "$ssr_link" | qrencode -t UTF8
echo "===================================="

echo "Trạng thái dịch vụ Sing-Box:"
systemctl status sing-box --no-pager

# Mở port trên tường lửa nếu UFW được cài đặt
if command -v ufw &> /dev/null; then
    ufw allow $server_port/tcp
    ufw allow $server_port/udp
    echo "Đã mở port $server_port trên tường lửa UFW."
fi

# Lưu thông tin vào file
cat > shadowsocks_info.txt << EOF
=== THÔNG TIN KẾT NỐI SHADOWSOCKS (QUA SING-BOX) ===
Server: $server_ip
Port: $server_port
Password: $password
Method: $method
Remarks: $config_name

Shadowsocks Link: $ss_link
SSR Link (tương thích): $ssr_link
EOF

echo "Thông tin kết nối đã được lưu vào file shadowsocks_info.txt"

# Hướng dẫn khắc phục sự cố
echo ""
echo "HƯỚNG DẪN KHẮC PHỤC SỰ CỐ:"
echo "1. Kiểm tra log: sudo journalctl -u sing-box -f"
echo "2. Kiểm tra cổng đã mở: sudo lsof -i :$server_port"
echo "3. Kiểm tra cấu hình: sudo cat /usr/local/etc/sing-box/config.json"
echo "4. Khởi động lại dịch vụ: sudo systemctl restart sing-box"
