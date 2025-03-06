#!/bin/bash
# Script tự động cài đặt Shadowsocks tối ưu và khắc phục lỗi kết nối
# Sử dụng: chmod +x optimized_ss.sh && sudo ./optimized_ss.sh

# Màu sắc
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Vui lòng chạy script với quyền sudo!${NC}"
  exit 1
fi

# Xóa cài đặt cũ nếu có
echo -e "${YELLOW}Kiểm tra và xóa cài đặt cũ nếu tồn tại...${NC}"
systemctl stop sing-box shadowsocks-libev ss-server 2>/dev/null
systemctl disable sing-box shadowsocks-libev ss-server 2>/dev/null
rm -f /etc/systemd/system/sing-box.service /etc/systemd/system/ss-server.service 2>/dev/null
systemctl daemon-reload

# Cập nhật repository
echo -e "${BLUE}Đang cập nhật danh sách package...${NC}"
apt-get update -y

# Cài đặt các gói cần thiết
echo -e "${BLUE}Đang cài đặt các gói cần thiết...${NC}"
apt-get install -y curl wget jq qrencode unzip iptables shadowsocks-libev

# Tạo port ngẫu nhiên (1024-65535)
server_port=$(shuf -i 10000-60000 -n 1)
echo -e "${GREEN}Đã tạo port ngẫu nhiên: ${server_port}${NC}"

# Tạo mật khẩu ngẫu nhiên
password=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 12)
echo -e "${GREEN}Đã tạo mật khẩu ngẫu nhiên: ${password}${NC}"

# Sử dụng phương thức mã hóa tối ưu và tương thích
# Chọn aes-256-gcm hoặc aes-256-cfb là an toàn nhất cho tính tương thích
method="aes-256-cfb"

# Lấy địa chỉ IP public
echo -e "${BLUE}Đang lấy địa chỉ IP public...${NC}"
server_ip=$(curl -s https://api.ipify.org)
if [ -z "$server_ip" ]; then
  server_ip=$(curl -s http://ifconfig.me)
fi

if [ -z "$server_ip" ]; then
  echo -e "${YELLOW}Không thể tự động lấy IP. Đang thử phương pháp khác...${NC}"
  server_ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "127.0.0.1" | head -n 1)
fi

if [ -z "$server_ip" ]; then
  read -p "Không thể tự động lấy IP. Vui lòng nhập IP của server: " server_ip
fi

echo -e "${GREEN}Địa chỉ IP của server: ${server_ip}${NC}"

# Hỏi tên cho cấu hình
read -p "Nhập tên cho cấu hình (mặc định: MySSServer): " config_name
config_name=${config_name:-MySSServer}

# Cấu hình shadowsocks-libev
echo -e "${BLUE}Đang cấu hình Shadowsocks...${NC}"
cat > /etc/shadowsocks-libev/config.json << EOF
{
    "server":"0.0.0.0",
    "server_port":${server_port},
    "password":"${password}",
    "timeout":300,
    "method":"${method}",
    "fast_open":true,
    "nameserver":"8.8.8.8",
    "mode":"tcp_and_udp"
}
EOF

# Mở port trên tường lửa
echo -e "${BLUE}Đang cấu hình tường lửa...${NC}"
# UFW
if command -v ufw &> /dev/null; then
    ufw allow $server_port/tcp
    ufw allow $server_port/udp
    echo -e "${GREEN}Đã mở port ${server_port} trên UFW.${NC}"
fi

# Iptables
iptables -I INPUT -p tcp --dport $server_port -j ACCEPT
iptables -I INPUT -p udp --dport $server_port -j ACCEPT
echo -e "${GREEN}Đã mở port ${server_port} trên iptables.${NC}"

# Khởi động lại dịch vụ shadowsocks-libev
echo -e "${BLUE}Đang khởi động dịch vụ Shadowsocks...${NC}"
systemctl restart shadowsocks-libev
systemctl enable shadowsocks-libev
sleep 2

# Kiểm tra trạng thái dịch vụ
if systemctl is-active --quiet shadowsocks-libev; then
    echo -e "${GREEN}Dịch vụ Shadowsocks đã được khởi động thành công.${NC}"
else
    echo -e "${RED}Dịch vụ Shadowsocks không khởi động được. Đang thử phương pháp thay thế...${NC}"
    
    # Thử cài đặt và cấu hình lại bằng ss-server trực tiếp
    echo -e "${BLUE}Đang cấu hình ss-server trực tiếp...${NC}"
    cat > /etc/systemd/system/ss-server.service << EOF
[Unit]
Description=Shadowsocks Server
After=network.target

[Service]
ExecStart=/usr/bin/ss-server -c /etc/shadowsocks-libev/config.json -u
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl start ss-server
    systemctl enable ss-server
    sleep 2
    
    if systemctl is-active --quiet ss-server; then
        echo -e "${GREEN}Dịch vụ ss-server đã được khởi động thành công.${NC}"
    else
        echo -e "${RED}Không thể khởi động dịch vụ Shadowsocks. Đang cài đặt phương pháp cuối cùng...${NC}"
        
        # Thử cài đặt Python Shadowsocks
        apt-get install -y python3-pip
        pip3 install https://github.com/shadowsocks/shadowsocks/archive/master.zip
        
        # Tạo cấu hình Python Shadowsocks
        cat > /etc/shadowsocks.json << EOF
{
    "server":"0.0.0.0",
    "server_port":${server_port},
    "password":"${password}",
    "timeout":300,
    "method":"${method}",
    "fast_open":false
}
EOF

        # Tạo service
        cat > /etc/systemd/system/shadowsocks-python.service << EOF
[Unit]
Description=Shadowsocks Python Server
After=network.target

[Service]
ExecStart=/usr/local/bin/ssserver -c /etc/shadowsocks.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

        systemctl daemon-reload
        systemctl start shadowsocks-python
        systemctl enable shadowsocks-python
        sleep 2
        
        if systemctl is-active --quiet shadowsocks-python; then
            echo -e "${GREEN}Dịch vụ Shadowsocks Python đã được khởi động thành công.${NC}"
        else
            echo -e "${RED}Tất cả các phương pháp đều thất bại. Vui lòng kiểm tra logs để biết thêm chi tiết.${NC}"
        fi
    fi
fi

# Tạo URI và QR code cho Shadowsocks
ss_base64=$(echo -n "${method}:${password}" | base64 -w 0)
ss_link="ss://${ss_base64}@${server_ip}:${server_port}#${config_name}"

# In thông tin
echo -e "${GREEN}===================================${NC}"
echo -e "${GREEN}Cài đặt hoàn tất! Shadowsocks đã được cài đặt và đang chạy.${NC}"
echo -e "${GREEN}===================================${NC}"
echo -e "${YELLOW}Thông tin kết nối Shadowsocks:${NC}"
echo -e "Server IP: ${server_ip}"
echo -e "Server Port: ${server_port}"
echo -e "Password: ${password}"
echo -e "Method: ${method}"
echo -e "${GREEN}===================================${NC}"
echo -e "${YELLOW}Shadowsocks Link:${NC} ${ss_link}"
echo -e "${GREEN}===================================${NC}"
echo -e "${YELLOW}Shadowsocks QR Code:${NC}"
echo -n "${ss_link}" | qrencode -t UTF8
echo -e "${GREEN}===================================${NC}"

# Kiểm tra kết nối
echo -e "${BLUE}Đang kiểm tra kết nối...${NC}"
if ss -tuln | grep -q ":$server_port "; then
    echo -e "${GREEN}Cổng ${server_port} đang mở và lắng nghe kết nối.${NC}"
else
    echo -e "${RED}Cổng ${server_port} không mở. Vui lòng kiểm tra cấu hình tường lửa.${NC}"
fi

# Lưu thông tin vào file
cat > shadowsocks_info.txt << EOF
=== THÔNG TIN KẾT NỐI SHADOWSOCKS ===
Server: ${server_ip}
Port: ${server_port}
Password: ${password}
Method: ${method}
Remarks: ${config_name}

Shadowsocks Link: ${ss_link}
EOF

echo -e "${GREEN}Thông tin kết nối đã được lưu vào file shadowsocks_info.txt${NC}"

# Hướng dẫn khắc phục sự cố
echo -e "${YELLOW}"
echo "HƯỚNG DẪN KHẮC PHỤC SỰ CỐ:"
echo "1. Kiểm tra log: sudo journalctl -u shadowsocks-libev -f"
echo "2. Kiểm tra cổng đã mở: sudo lsof -i :$server_port"
echo "3. Kiểm tra tường lửa: sudo iptables -L | grep $server_port"
echo "4. Khởi động lại dịch vụ: sudo systemctl restart shadowsocks-libev"
echo "5. Nếu vẫn không kết nối được, thử đổi port: sudo nano /etc/shadowsocks-libev/config.json"
echo -e "${NC}"

# Hướng dẫn thêm
echo -e "${BLUE}Lưu ý quan trọng:${NC}"
echo "1. Một số ISP có thể chặn các kết nối Shadowsocks. Nếu vẫn không kết nối được, hãy thử chạy trên port phổ biến như 443, 80, 8080."
echo "2. Nếu ứng dụng khách báo lỗi 'Không thể kết nối', hãy kiểm tra xem phương thức mã hóa có được hỗ trợ hay không."
echo "3. Đảm bảo rằng bạn nhập đúng địa chỉ IP và port."
echo "4. Một số ứng dụng Shadowsocks yêu cầu bạn nhập thông tin thủ công thay vì quét mã QR."

# Kiểm tra xem có thể kết nối từ bên ngoài không
echo -e "${YELLOW}Thử kết nối từ server đến localhost:${NC}"
curl --socks5 127.0.0.1:$server_port -s http://ifconfig.me > /dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Kết nối SOCKS5 đến localhost:$server_port thành công.${NC}"
else
    echo -e "${RED}Không thể kết nối SOCKS5 đến localhost:$server_port.${NC}"
fi
