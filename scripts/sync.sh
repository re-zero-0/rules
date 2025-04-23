#!/bin/bash

BASE_URL="http://127.0.0.1:8080/Clash"
RULE_DIR="./rule/Clash"
PERSONAL_DIR="./personal"

# 检查personal目录是否存在
if [ -d "$PERSONAL_DIR" ]; then
    echo "Found personal directory, will process rules there too."
else
    echo "Personal directory not found, only processing upstream rules."
    mkdir -p "$PERSONAL_DIR"
fi

download_and_check() {
    local output_file=$1
    local expected_md5=$2
    local url=$3
    local output_text_file=$4

    if wget -q --no-proxy -O "$output_file" "$url"; then
        if [ "$(md5sum "$output_file" | awk '{print $1}')" = "$expected_md5" ]; then
            rm -f "$output_file"
        else
            cp "$output_file" "$output_text_file"
        fi
    else
        echo "Error downloading $url" >&2
    fi
}

process_directory() {
    local dir=$1
    
    # 进入目录
    cd "$dir" || exit
    
    # .list to .txt/.yaml
    find . -name "*.list" | while read -r file; do
        # 去掉前缀的 "./" 并生成对应的本地 URL
        RAW_URL="$BASE_URL/${file#./}"

        RAW_URL_BASE64=$(echo -n "$RAW_URL" | openssl base64 -A)

        # 生成输出文件路径. 并保持原有目录结构 (去掉"_OCD"标记)
        OUTPUT_FILE_DOMAIN_YAML="${file%.list}_Domain.yaml"
        OUTPUT_FILE_DOMAIN_TEXT="${file%.list}_Domain.txt"
        OUTPUT_FILE_IP_YAML="${file%.list}_IP.yaml"
        OUTPUT_FILE_IP_TEXT="${file%.list}_IP.txt"

        # 下载转换后的规则文件, 丢弃无用文件, [type=3 代表域名, type=4 代表 IP]
        download_and_check "$OUTPUT_FILE_DOMAIN_YAML" "0c04407cd072968894bd80a426572b13" "http://127.0.0.1:25500/getruleset?type=3&url=$RAW_URL_BASE64" "$OUTPUT_FILE_DOMAIN_TEXT"
        download_and_check "$OUTPUT_FILE_IP_YAML" "3d6eaeec428ed84741b4045f4b85eee3" "http://127.0.0.1:25500/getruleset?type=4&url=$RAW_URL_BASE64" "$OUTPUT_FILE_IP_TEXT"
    done

    # 处理yaml文件 (适用于personal目录中的yaml文件)
    if [[ "$dir" == "$PERSONAL_DIR" ]]; then
        find . -name "*.yaml" | while read -r file; do
            # 对yaml文件进行处理
            file_dir=$(dirname "$file")
            filename=$(basename "$file" .yaml)
            
            # 生成输出文件 (如果需要文本版本可以在这里添加)
            output_file_text="${file%.yaml}.txt"
            cp "$file" "$output_file_text"
            
            # 提取规则内容，去除头部信息
            first_line=$(head -n 1 "$output_file_text")
            if [[ "$first_line" == *"payload"* ]]; then
                sed -i '1d' "$output_file_text"
            fi
            
            # 判断规则类型，根据文件命名进行处理
            if [[ "$filename" == *"Domain"* ]]; then
                param="domain"
            elif [[ "$filename" == *"IP"* ]]; then
                param="ipcidr"
            else
                # 默认当作域名规则处理
                param="domain"
            fi
            
            # 处理规则文件
            sed -i "s/'//g; s/-//g; s/[[:space:]]//g" "$output_file_text"
            
            # 转换为.mrs格式
            output_file="$file_dir/$filename.mrs"
            /usr/bin/mihomo convert-ruleset "$param" text "$output_file_text" "$output_file"
            if [[ $? -eq 0 ]]; then
                echo "文件 $file 转换成功为 $output_file"
            else
                echo "文件 $file 转换失败"
            fi
        done
    fi

    # .txt to .mrs (更新正则表达式以匹配没有"_OCD"的文件)
    find . -name "*_Domain.txt" -o -name "*_IP.txt" | while read -r file; do
        first_line=$(head -n 1 "$file")
        if [[ "$first_line" == *"payload"* ]]; then
            sed -i '1d' "$file"
        fi
        # 删除所有单引号、减号和空格
        sed -i "s/'//g; s/-//g; s/[[:space:]]//g" "$file"

        file_dir=$(dirname "$file")
        filename=$(basename "$file" .txt)

        if [[ "$filename" == *"Domain"* ]]; then
            param="domain"
        elif [[ "$filename" == *"IP"* ]]; then
            param="ipcidr"
        else
            echo "未识别的文件类型: $file"
            continue
        fi

        output_file="$file_dir/$filename.mrs"
        /usr/bin/mihomo convert-ruleset "$param" text "$file" "$output_file"
        if [[ $? -eq 0 ]]; then
            echo "文件 $file 转换成功为 $output_file"
        else
            echo "文件 $file 转换失败"
        fi
    done
    
    # 返回上一级目录
    cd - > /dev/null
}

# 处理上游规则
process_directory "$RULE_DIR"

# 处理个人规则
if [ -d "$PERSONAL_DIR" ]; then
    process_directory "$PERSONAL_DIR"
fi

echo "所有规则处理完成"