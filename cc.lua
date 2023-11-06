local ip_block_time = 120  -- 封禁IP时间（秒）
local ip_time_out = 30     -- 指定IP访问频率时间段（秒）
local ip_max_count = 300   -- 指定IP访问频率计数最大值（秒）
local BUSINESS = ngx.var.business -- 可加可不加
-- 定义白名单IP地址列表
local whitelist_ips = {
    -- 添加其他白名单IP地址
}

-- 获取透传的IP地址（X-Forwarded-For头部字段），如果不存在则使用 ngx.var.remote_addr
local client_ip = ngx.req.get_headers()["X-Forwarded-For-tx"] or ngx.var.remote_addr

-- 连接Redis
local redis = require "resty.redis"
local conn = redis:new()
conn:set_timeout(2000)   -- 超时时间2秒

-- 如果连接失败，返回错误响应
local ok, err = conn:connect("127.0.0.1", 6379)
if not ok then
    ngx.status = 500
    ngx.say('{"error": "unable to connect Redis"}')
    ngx.exit(ngx.status)
end

-- 打开单独的日志文件
local log_file = io.open("/usr/local/openresty/nginx/logs/count.log", "a")

-- 检查IP是否在白名单中，如果在白名单中，则不进行频率限制
local is_whitelisted = false
for _, ip in ipairs(whitelist_ips) do
    if client_ip == ip then
        is_whitelisted = true
        break
    end
end

if is_whitelisted then
    ngx.log(ngx.INFO, "Normal user access: " .. client_ip)
else
    -- 查询ip是否被禁止访问，如果存在则返回403错误代码
    local is_block, err = conn:get(BUSINESS.."-BLOCK-"..client_ip)
    if is_block == '1' then
        log_file:write("X-Forwarded-For-tx:" ..ngx.req.get_headers()["X-Forwarded-For-tx"])
        log_file:write("-ngx.var.remote_addr:" ..ngx.var.remote_addr)
        log_file:write("黑名单中 IP: " .. client_ip .. "\n")
        ngx.exit(403)
    else
        ngx.log(ngx.INFO, "Normal IP access: " .. client_ip)
    end

    -- 查询redis中保存的ip的计数器
    local ip_count = conn:get(BUSINESS.."-COUNT-"..client_ip)

    if ip_count == ngx.null then   -- 如果不存在，则将该IP存入redis，并将计数器设置为1、该KEY的超时时间为ip_time_out
        local res, err = conn:set(BUSINESS.."-COUNT-"..client_ip, 1)
        local res, err = conn:expire(BUSINESS.."-COUNT-"..client_ip, ip_time_out)
    else
        ip_count = ip_count + 1   -- 如果存在则将单位时间内的访问次数加1

        if ip_count >= ip_max_count then   -- 如果超过单位时间限制的访问次数，则添加限制访问标识，限制时间为ip_block_time
            local res, err = conn:set(BUSINESS.."-BLOCK-"..client_ip, 1)
            local res, err = conn:expire(BUSINESS.."-BLOCK-"..client_ip, ip_block_time)
            log_file:write("X-Forwarded-For-tx:" ..ngx.req.get_headers()["X-Forwarded-For-tx"])
            log_file:write("-ngx.var.remote_addr:" ..ngx.var.remote_addr)
            log_file:write("拉黑 IP: " .. client_ip .. "\n")
            ngx.exit(403)
        else
            local res, err = conn:set(BUSINESS.."-COUNT-"..client_ip, ip_count)
            local res, err = conn:expire(BUSINESS.."-COUNT-"..client_ip, ip_time_out)
        end
    end
end

-- 关闭Redis连接
local ok, err = conn:close()

-- 关闭日志文件
log_file:close()
