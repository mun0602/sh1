#!/bin/bash

# Hàm kiểm tra kết nối internet
check_internet_connection() {
    echo "Kiểm tra kết nối internet..."
    if ping -c 1 github.com &> /dev/null; then
        echo "Kết nối internet đến GitHub.com thành công."
        return 0
    else
        echo "Không thể kết nối đến GitHub.com. Vui lòng kiểm tra kết nối internet của bạn."
        return 1
    fi
}

# Hàm kiểm tra cấu hình Git
check_git_config() {
    echo "Kiểm tra cấu hình Git..."
    local has_username=$(git config --global user.name)
    local has_email=$(git config --global user.email)
    
    if [ -z "$has_username" ] || [ -z "$has_email" ]; then
        echo "Cảnh báo: Cấu hình Git chưa đầy đủ."
        
        if [ -z "$has_username" ]; then
            read -p "Nhập tên người dùng Git: " git_username
            git config --global user.name "$git_username"
        fi
        
        if [ -z "$has_email" ]; then
            read -p "Nhập email Git: " git_email
            git config --global user.email "$git_email"
        fi
        
        echo "Đã cập nhật cấu hình Git."
    else
        echo "Cấu hình Git đã đầy đủ."
    fi
    return 0
}

# Hàm kiểm tra xác thực GitHub
check_github_auth() {
    echo "Kiểm tra xác thực GitHub..."
    
    # Thử kết nối đến GitHub API
    local auth_status=$(curl -s -o /dev/null -w "%{http_code}" https://api.github.com/user -H "Authorization: token $GITHUB_TOKEN" 2>/dev/null)
    
    if [ "$auth_status" = "200" ]; then
        echo "Xác thực GitHub thành công qua token."
        return 0
    else
        echo "Không có token GitHub hoặc token không hợp lệ."
        echo "Sẽ sử dụng xác thực thông thường khi đẩy lên GitHub."
        return 0  # Không coi đây là lỗi
    fi
}

# Hàm kiểm tra kết nối GitHub
check_github_connection() {
    echo "Kiểm tra kết nối GitHub..."
    
    # Kiểm tra internet trước
    if ! check_internet_connection; then
        echo "Không có kết nối internet đến GitHub.com."
        return 1
    fi
    
    # Kiểm tra cấu hình Git
    check_git_config
    
    # Kiểm tra xác thực GitHub
    check_github_auth
    
    # Kiểm tra kết nối đến repository cụ thể
    if git ls-remote "$1" &> /dev/null; then
        echo "Kết nối đến repository GitHub thành công."
        return 0
    else
        echo "Không thể kết nối đến repository GitHub. Vui lòng kiểm tra URL và quyền truy cập."
        
        # Đề xuất giải pháp
        echo "Một số giải pháp có thể thử:"
        echo "1. Kiểm tra lại URL repository"
        echo "2. Đảm bảo bạn có quyền truy cập repository này"
        echo "3. Kiểm tra xác thực SSH hoặc token GitHub"
        
        return 1
    fi
}

# Hàm đẩy lên GitHub với xử lý lỗi
push_to_github() {
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo "Đang đẩy lên GitHub (lần thử $attempt/$max_attempts)..."
        if git push -u origin main; then
            echo "Đẩy lên GitHub thành công!"
            return 0
        else
            echo "Lỗi khi đẩy lên GitHub."
            if [ $attempt -lt $max_attempts ]; then
                echo "Thử lại sau 5 giây..."
                sleep 5
            fi
            attempt=$((attempt + 1))
        fi
    done
    
    echo "Đã thử $max_attempts lần nhưng không thành công."
    return 1
}

# Hàm thêm remote repository với xử lý lỗi
add_remote() {
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if git remote add origin "$1"; then
            echo "Đã thêm remote repository thành công."
            return 0
        else
            echo "Lỗi khi thêm remote repository."
            # Kiểm tra nếu remote đã tồn tại
            if git remote | grep -q "^origin$"; then
                echo "Remote 'origin' đã tồn tại. Đang xóa và thêm lại..."
                git remote remove origin
            fi
            
            if [ $attempt -lt $max_attempts ]; then
                echo "Thử lại sau 3 giây..."
                sleep 3
            fi
            attempt=$((attempt + 1))
        fi
    done
    
    echo "Không thể thêm remote repository sau $max_attempts lần thử."
    return 1
}

# Nhập tên file .sh cần tạo
while true; do
    echo "Nhập tên file .sh cần tạo (không cần nhập đuôi .sh):"
    read file_name
    
    # Kiểm tra tên file hợp lệ
    if [[ ! $file_name =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "Tên file không hợp lệ. Chỉ sử dụng chữ cái, số, gạch ngang và gạch dưới."
        continue
    fi
    
    folder_name="${file_name}-folder"
    script_file="${file_name}.sh"
    
    # Kiểm tra nếu file hoặc thư mục đã tồn tại
    if [ -d "$folder_name" ] || [ -f "$folder_name/$script_file" ]; then
        echo "Thư mục hoặc file đã tồn tại. Vui lòng chọn tên khác."
    else
        break
    fi
done

# Tạo thư mục và file
mkdir -p "$folder_name"
cd "$folder_name" || { echo "Không thể chuyển đến thư mục $folder_name"; exit 1; }
touch "$script_file"

# Mở file trong nano để sửa
echo "Đã tạo file $script_file. Mở nano để chỉnh sửa..."
nano "$script_file"

# Kiểm tra nếu user đã lưu file
max_check=3
check_count=0
while [ ! -s "$script_file" ] && [ $check_count -lt $max_check ]; do
    check_count=$((check_count + 1))
    echo "File $script_file rỗng (kiểm tra $check_count/$max_check)."
    
    if [ $check_count -ge $max_check ]; then
        echo "File vẫn rỗng sau $max_check lần kiểm tra. Tiếp tục?"
        read -p "Tiếp tục (y) hoặc hủy (n): " continue_choice
        if [[ "$continue_choice" != "y" && "$continue_choice" != "Y" ]]; then
            echo "Hủy thao tác."
            exit 1
        fi
        break
    fi
    
    read -p "Bạn có muốn mở lại editor không? (y/n): " open_again
    if [[ "$open_again" == "y" || "$open_again" == "Y" ]]; then
        nano "$script_file"
    else
        break
    fi
done

# Đặt quyền thực thi cho file
chmod +x "$script_file"
echo "Đã đặt quyền thực thi cho $script_file."

# Khởi tạo Git
git init

# Thêm file vào Git
git add "$script_file"
git commit -m "Thêm script $script_file"

# Thêm remote repository
max_repo_attempts=3
repo_attempt=1

while [ $repo_attempt -le $max_repo_attempts ]; do
    read -p "Nhập URL repository GitHub của bạn: " repo_url
    
    if check_github_connection "$repo_url"; then
        if add_remote "$repo_url"; then
            break
        fi
    fi
    
    if [ $repo_attempt -lt $max_repo_attempts ]; then
        echo "Thử lại với URL repository khác..."
    else
        echo "Đã thử $max_repo_attempts lần nhưng không thành công."
        read -p "Bạn có muốn tiếp tục thử không? (y/n): " continue_choice
        if [[ "$continue_choice" == "y" || "$continue_choice" == "Y" ]]; then
            repo_attempt=0
        else
            echo "Hủy thao tác."
            exit 1
        fi
    fi
    
    repo_attempt=$((repo_attempt + 1))
done

# Cấu hình nhánh
git branch -M main

# Thêm chức năng chuẩn đoán và khắc phục sự cố
diagnose_push_issues() {
    echo "=== Chuẩn đoán sự cố đẩy lên GitHub ==="
    echo "1. Kiểm tra trạng thái Git hiện tại..."
    git status
    
    echo "2. Kiểm tra remote repository..."
    git remote -v
    
    echo "3. Kiểm tra kết nối mạng đến GitHub..."
    ping -c 3 github.com
    
    echo "4. Kiểm tra xác thực..."
    if [ -n "$GITHUB_TOKEN" ]; then
        echo "Token GitHub đã được thiết lập."
    else
        echo "Không tìm thấy token GitHub."
    fi
    
    echo "5. Thử lại với --verbose để xem thông tin chi tiết..."
    git push -u origin main --verbose
    
    return $?
}

# Push lên repository với xử lý lỗi
echo "=== Đẩy lên GitHub ==="
if push_to_github; then
    # Thông báo hoàn tất
    echo "==============================================="
    echo "Đã đẩy script $script_file lên GitHub repository."
    echo "URL: $repo_url"
    echo "==============================================="
else
    echo "Không thể đẩy lên GitHub bằng cách thông thường."
    
    # Hỏi người dùng có muốn chuẩn đoán sự cố
    read -p "Bạn có muốn chạy chức năng chuẩn đoán sự cố không? (y/n): " run_diagnosis
    if [[ "$run_diagnosis" == "y" || "$run_diagnosis" == "Y" ]]; then
        if diagnose_push_issues; then
            echo "Đã đẩy lên GitHub thành công sau khi chuẩn đoán."
            exit 0
        fi
    fi
    
    # Đề xuất các giải pháp thay thế
    echo "Không thể đẩy lên GitHub. Dưới đây là một số giải pháp:"
    echo "1. Kiểm tra xác thực GitHub của bạn."
    echo "2. Đảm bảo bạn có quyền đẩy lên repository này."
    echo "3. Kiểm tra tường lửa hoặc proxy có thể chặn kết nối."
    echo "4. Tạo Personal Access Token mới và cấu hình Git để sử dụng."
    echo ""
    echo "Bạn có thể thử đẩy thủ công sau này với lệnh:"
    echo "  cd $(pwd)"
    echo "  git push -u origin main"
    echo ""
    echo "Mã lỗi Git cuối cùng: $?"
    
    exit 1
fi
