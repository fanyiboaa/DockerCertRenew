#!/bin/bash
# author: liyiyi
# email: fanyiboaa@gmail.com
# version: 1.0

# 证书有效期小于多少天进行续期
days_before_expiry=10
# 证书管理员邮箱
admin_email=your_email@example.com
# certbot数据目录，如下
# /root/conf/nginx/certificates:/etc/letsencrypt
# 数据目录为 /root/conf/nginx/certificates
certificate_dir="/root/conf/nginx/certificates"
# 停止nginx命令
nginx_stop_cmd="docker stop nginx"
# 启动nginx命令
nginx_start_cmd="docker start nginx"

# 正则表达式用于验证域名
_domain_regex="^([0-9a-zA-Z-]{1,}\.)+([a-zA-Z]{2,})$"

# 获取证书有效期
get_expiration_date() {
    local cert_file="$1"
    local expiration_data
    expiration_data=$(openssl x509 -enddate -noout -in "${cert_file}" 2>&1)
    if [ $? -ne 0 ]; then
        _error "检查证书有效期失败: ${expiration_data}"
        return 1
    fi
    echo "$(echo ${expiration_data} | awk -F'=' '{print $2}')"
}

# 计算证书还多久到期
calculate_days_left() {
    local expiration_date="$1"
    local expiration_timestamp=$(date -d "${expiration_date}" +%s)
    local current_timestamp=$(date +%s)
    echo $((($expiration_timestamp - $current_timestamp) / (60 * 60 * 24)))
}

# 打印普通日志
_log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') $*"
}

# 打印错误日志
_error() {
    # todo...
    echo "$(date +'%Y-%m-%d %H:%M:%S') [error] $*"
}

_log "------------------------------------"
_log "证书有效期检查开始"

for filename in "${certificate_dir}/live/"*; do
    domain=$(basename "${filename}")
    # 判断是否为域名
    if [[ $domain =~ $_domain_regex ]]; then
        _log "------------------------------------"
        _log "发现证书：${domain}"
        # 拼接证书路径
        cert_file="${filename}/fullchain.pem"

        # 获取证书到期时间
        expiration_date=$(get_expiration_date "${cert_file}")
        if [ $? -ne 0 ]; then
            continue
        fi

        _log "证书过期时间: ${expiration_date}"
        # 获取证书过期时间戳
        expiration_timestamp=$(date -d "${expiration_date}" +%s)
        # 获取当前时间戳
        current_timestamp=$(date +%s)
        # 计算剩余天数
        left_time=$(calculate_days_left "${expiration_date}")

        if [ $left_time -le $days_before_expiry ]; then
            # 小于剩余天数，进行续期
            _log "剩余时间还剩${left_time}天，已经小于${days_before_expiry}天，开始续期"

            # 关闭nginx
            nginx_stop_cmd_output=$(eval "$nginx_stop_cmd" 2>&1)
            if [ $? -ne 0 ]; then
                _error 关闭nginx出错
                continue
            fi

            # 使用certbot续签
            certbot_cmd="docker run --rm -p 80:80 \
            -v /root/conf/nginx/certificates:/etc/letsencrypt \
            certbot/certbot:nightly certonly \
            --standalone -q -n --agree-tos --no-eff-email --force-renewa \
            -m ${admin_email} -d ${domain}"

            certbot_output=$(eval "$certbot_cmd" 2>&1)
            if [ $? -ne 0 ]; then
                _error "使用certbot续签出错: ${certbot_output}"
                continue
            fi

            # 启动nginx
            nginx_start_cmd_output=$(eval "$nginx_start_cmd" 2>&1)
            if [ $? -ne 0 ]; then
                _error "启动nginx出错: ${nginx_start_cmd_output}"
                continue
            fi

            _log "续签成功"

        else
            # 未满足续签条件
            _log "距离证书过期还有 ${left_time} 天"
        fi

    fi
done

_log "证书有效期检查结束"
_log "------------------------------------"
