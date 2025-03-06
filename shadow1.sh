#!/bin/bash
# Script tối ưu hóa và giám sát Shadowsocks
# Sử dụng: chmod +x ss_optimize.sh && sudo ./ss_optimize.sh

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

# Lấy thông tin port từ cấu hình Shadowsocks hiện tại
PORT_FOUND=false

# Kiểm tra các file cấu hình phổ biến
CONFIG_FILES=(
  "/etc/shadowsocks-libev/config.json"
  "/etc/shadowsocks.json"
  "/usr/local/etc/shadowsocks.json"
)

for config_file in "${CONFIG_FILES[@]}"; do
  if [ -f "$config_file" ]; then
    echo -e "${BLUE}Đã tìm thấy file cấu hình: $config_file${NC}"
    server_port=$(grep -o '"server_port":[^,]*' "$config_file" | grep -o '[0-9]*')
    
    if [ -n "$server_port" ]; then
      echo -e "${GREEN}Đã tìm thấy port: $server_port${NC}"
      PORT_FOUND=true
      break
    fi
  fi
done

if [ "$PORT_FOUND" = false ]; then
  echo -e "${YELLOW}Không tìm thấy port Shadowsocks. Đang yêu cầu nhập thủ công...${NC}"
  read -p "Nhập port Shadowsocks: " server_port
  
  if [ -z "$server_port" ]; then
    echo -e "${RED}Không có port được nhập. Không thể tiếp tục.${NC}"
    exit 1
  fi
fi

echo -e "${BLUE}=== Bắt đầu tối ưu hóa Shadowsocks ===${NC}"

# 1. Bật BBR congestion control
echo -e "${BLUE}Đang bật BBR congestion control...${NC}"

# Kiểm tra phiên bản kernel
kernel_version=$(uname -r | cut -d. -f1)
if [ "$kernel_version" -lt 4 ]; then
  echo -e "${YELLOW}Phiên bản kernel của bạn ($kernel_version) có thể không hỗ trợ BBR. BBR yêu cầu kernel 4.9+${NC}"
  
  read -p "Bạn có muốn cập nhật kernel? (y/n, mặc định: n): " update_kernel
  update_kernel=${update_kernel:-n}
  
  if [[ "$update_kernel" == "y" || "$update_kernel" == "Y" ]]; then
    echo -e "${BLUE}Đang cập nhật kernel...${NC}"
    apt-get install -y linux-generic-hwe-$(lsb_release -rs)
    echo -e "${GREEN}Kernel đã được cập nhật. Vui lòng khởi động lại hệ thống và chạy lại script này.${NC}"
    exit 0
  else
    echo -e "${YELLOW}Bỏ qua cập nhật kernel. BBR có thể không hoạt động.${NC}"
  fi
fi

# Bật BBR
cat >> /etc/sysctl.conf << EOF
# BBR congestion control
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

# Áp dụng cấu hình sysctl
sysctl -p

# Kiểm tra xem BBR đã được bật chưa
if sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
  echo -e "${GREEN}BBR đã được bật thành công!${NC}"
else
  echo -e "${RED}Không thể bật BBR. Vui lòng kiểm tra phiên bản kernel của bạn.${NC}"
fi

# 2. Tối ưu hóa các tham số kernel cho độ trễ thấp và thông lượng cao
echo -e "${BLUE}Đang tối ưu hóa các tham số kernel...${NC}"

cat >> /etc/sysctl.conf << EOF
# Tối ưu hóa TCP/IP
fs.file-max = 51200
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 4096
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mem = 25600 51200 102400
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1
EOF

# Áp dụng cấu hình sysctl
sysctl -p

echo -e "${GREEN}Đã tối ưu hóa tham số kernel thành công!${NC}"

# 3. Cài đặt và cấu hình giám sát với Monit
echo -e "${BLUE}Đang cài đặt và cấu hình Monit để giám sát Shadowsocks...${NC}"

# Cài đặt Monit
apt-get update
apt-get install -y monit

# Xác định tên dịch vụ Shadowsocks
if systemctl list-units --full -all | grep -q "shadowsocks-libev"; then
  service_name="shadowsocks-libev"
elif systemctl list-units --full -all | grep -q "ss-server"; then
  service_name="ss-server"
elif systemctl list-units --full -all | grep -q "shadowsocks-python"; then
  service_name="shadowsocks-python"
else
  echo -e "${YELLOW}Không thể tự động xác định tên dịch vụ Shadowsocks.${NC}"
  read -p "Nhập tên dịch vụ Shadowsocks (vd: shadowsocks-libev): " service_name
  
  if [ -z "$service_name" ]; then
    echo -e "${RED}Tên dịch vụ không được nhập. Sử dụng giá trị mặc định 'shadowsocks-libev'.${NC}"
    service_name="shadowsocks-libev"
  fi
fi

echo -e "${GREEN}Đã xác định tên dịch vụ Shadowsocks: $service_name${NC}"

# Tạo file cấu hình Monit cho Shadowsocks
cat > /etc/monit/conf.d/shadowsocks << EOF
check process $service_name with pidfile /var/run/$service_name.pid
  start program = "/usr/bin/systemctl start $service_name"
  stop program = "/usr/bin/systemctl stop $service_name"
  if failed port $server_port for 3 cycles then restart
  if 5 restarts within 5 cycles then timeout
EOF

# Nếu file PID không tồn tại, thử cách khác
if [ ! -f "/var/run/$service_name.pid" ]; then
  echo -e "${YELLOW}File PID không tồn tại, sử dụng phương pháp thay thế...${NC}"
  cat > /etc/monit/conf.d/shadowsocks << EOF
check process $service_name matching "ss-server|ss-local|ss-redir|ss-tunnel"
  start program = "/usr/bin/systemctl start $service_name"
  stop program = "/usr/bin/systemctl stop $service_name"
  if failed port $server_port for 3 cycles then restart
  if 5 restarts within 5 cycles then timeout
EOF
fi

# Cho phép truy cập Monit từ localhost
sed -i 's/use address localhost/use address localhost/g' /etc/monit/monitrc
sed -i 's/allow localhost/allow localhost/g' /etc/monit/monitrc

# Khởi động lại Monit
systemctl restart monit
systemctl enable monit

echo -e "${GREEN}Đã cấu hình Monit để giám sát Shadowsocks thành công!${NC}"
echo -e "${GREEN}Monit sẽ tự động khởi động lại dịch vụ nếu nó không phản hồi.${NC}"

# 4. Tạo script để kiểm tra và khởi động lại dịch vụ (hữu ích cho cronjob)
cat > /usr/local/bin/check_shadowsocks.sh << EOF
#!/bin/bash
# Script kiểm tra và khởi động lại Shadowsocks nếu cần

# Kiểm tra xem dịch vụ có đang chạy không
if ! systemctl is-active --quiet $service_name; then
  systemctl restart $service_name
  echo "[\$(date)] Đã khởi động lại $service_name" >> /var/log/shadowsocks_monitor.log
fi

# Kiểm tra xem port có đang lắng nghe không
if ! ss -tuln | grep -q ":$server_port "; then
  systemctl restart $service_name
  echo "[\$(date)] Đã khởi động lại $service_name vì port $server_port không hoạt động" >> /var/log/shadowsocks_monitor.log
fi
EOF

chmod +x /usr/local/bin/check_shadowsocks.sh

# Thêm cronjob để chạy script kiểm tra mỗi 5 phút
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/check_shadowsocks.sh") | crontab -

echo -e "${GREEN}Đã tạo script kiểm tra và cronjob để giám sát Shadowsocks mỗi 5 phút!${NC}"

# Hiển thị trạng thái cuối cùng
echo -e "${BLUE}=== Tối ưu hóa và giám sát hoàn tất ===${NC}"
echo -e "${GREEN}BBR congestion control: $(sysctl net.ipv4.tcp_congestion_control | grep -q bbr && echo "Bật" || echo "Tắt")${NC}"
echo -e "${GREEN}Tối ưu hóa kernel: Đã áp dụng${NC}"
echo -e "${GREEN}Giám sát Monit: Đã cấu hình${NC}"
echo -e "${GREEN}Cronjob kiểm tra: Mỗi 5 phút${NC}"

echo -e "${YELLOW}Để kiểm tra trạng thái Monit:${NC} sudo monit status"
echo -e "${YELLOW}Để xem log giám sát:${NC} cat /var/log/shadowsocks_monitor.log"
echo -e "${YELLOW}Để kiểm tra BBR:${NC} sysctl net.ipv4.tcp_congestion_control"

echo -e "${GREEN}Tối ưu hóa hoàn tất! Shadowsocks của bạn giờ đây sẽ:${NC}"
echo -e "  ${GREEN}- Có hiệu suất tốt hơn với BBR${NC}"
echo -e "  ${GREEN}- Tự động khởi động lại nếu gặp sự cố${NC}"
echo -e "  ${GREEN}- Được giám sát thường xuyên${NC}"
