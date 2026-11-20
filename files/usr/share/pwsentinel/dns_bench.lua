local nixio = require("nixio")
local dns_list = require("pwsentinel.dns_list")

local M = {}

-- Standard DNS query packet for example.com A record
local q_packet = string.char(
    0xaa, 0xbb, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x07, 0x65, 0x78, 0x61, 0x6d, 0x70, 0x6c, 0x65, 0x03, 0x63, 0x6f, 0x6d, 0x00,
    0x00, 0x01, 0x00, 0x01
)

local function test_udp_direct(ip, mark)
    local s = nixio.socket("inet", "dgram")
    if not s then return nil, "SOCK_ERR" end
    s:setopt("socket", "rcvtimeo", 2)
    s:setopt("socket", "sndtimeo", 2)
    if mark then pcall(function() s:setopt("socket", "mark", mark) end) end

    local t0, u0 = nixio.gettimeofday()
    local ok = s:sendto(q_packet, ip, 53)
    if not ok then s:close(); return nil, "SEND_FAIL" end
    local res = s:recvfrom(512)
    local t1, u1 = nixio.gettimeofday()
    s:close()
    if not res then return nil, "TIMEOUT" end
    local dt = ((t1 - t0) * 1000) + ((u1 - u0) / 1000)

    -- Poisoning check for Iranian censorship fake IP injection
    local poisoned = false
    if res:find(string.char(188, 114, 98)) or res:find(string.char(10, 10, 34)) then
        poisoned = true
    end

    return dt, poisoned and "POISONED" or "OK"
end

local function test_tcp_direct(ip, mark)
    local s = nixio.socket("inet", "stream")
    if not s then return nil, "SOCK_ERR" end
    s:setopt("socket", "rcvtimeo", 2)
    s:setopt("socket", "sndtimeo", 2)
    if mark then pcall(function() s:setopt("socket", "mark", mark) end) end

    local t0, u0 = nixio.gettimeofday()
    local ok = s:connect(ip, 53)
    local t1, u1 = nixio.gettimeofday()
    s:close()
    if ok then
        local dt = ((t1 - t0) * 1000) + ((u1 - u0) / 1000)
        return dt, "OK"
    else
        return nil, "FAIL"
    end
end

local function test_doh_direct(doh_url, mark, iface)
    if not doh_url then return nil, "N/A" end
    local if_flag = iface and string.format("--interface %s", iface) or ""
    local cmd = string.format("curl -s -w '%%{http_code}:%%{time_total}' -o /dev/null -H 'accept: application/dns-message' --connect-timeout 2 --max-time 3 %s '%s?dns=AAABAAABAAAAAAAAA3d3dwdleGFtcGxlA2NvbQAAAQAB' 2>/dev/null", if_flag, doh_url)
    local f = io.popen(cmd)
    local out = f:read("*a") or ""
    f:close()
    local code, sec = out:match("(%d+):([%d%.]+)")
    if code == "200" then
        return tonumber(sec) * 1000, "OK"
    elseif code then
        return nil, "ERR_" .. code
    else
        return nil, "TIMEOUT"
    end
end

function M.run(opts)
    opts = opts or {}
    local mark = opts.mark or 255
    local iface = opts.iface or "wan"
    local results = {}
    local best_doh = nil
    local best_direct = nil

    if not opts.quiet then
        print(string.format("%-34s | %-16s | %-12s | %-12s", "DNS Provider", "UDP 53 (Direct)", "TCP 53 (Direct)", "DoH 443 (Direct)"))
        print(string.rep("-", 82))
    end

    for _, p in ipairs(dns_list) do
        local u_time, u_status = test_udp_direct(p.ip, mark)
        local t_time, t_status = test_tcp_direct(p.ip, mark)
        local d_time, d_status = test_doh_direct(p.doh, mark, iface)

        local entry = {
            name = p.name,
            ip = p.ip,
            doh = p.doh,
            type = p.type,
            udp_time = u_time,
            udp_status = u_status,
            tcp_time = t_time,
            tcp_status = t_status,
            doh_time = d_time,
            doh_status = d_status
        }
        table.insert(results, entry)

        -- Evaluate best DoH (foreign, working, lowest latency)
        if d_status == "OK" and d_time then
            if not best_doh or d_time < best_doh.doh_time then
                best_doh = entry
            end
        end

        -- Evaluate best direct DNS (domestic preferred, not poisoned, lowest UDP latency)
        if u_status == "OK" and u_time then
            if p.type == "domestic" then
                if not best_direct or u_time < (best_direct.udp_time or 9999) then
                    best_direct = entry
                end
            elseif not best_direct and p.type == "foreign" then
                best_direct = entry
            end
        end

        if not opts.quiet then
            local u_str = u_status == "OK" and string.format("%.1fms", u_time) or u_status
            local t_str = t_status == "OK" and string.format("%.1fms", t_time) or t_status
            local d_str = d_status == "OK" and string.format("%.1fms", d_time) or d_status
            print(string.format("%-34s | %-16s | %-12s | %-12s", p.name, u_str, t_str, d_str))
        end
    end

    return {
        results = results,
        best_doh = best_doh,
        best_direct = best_direct
    }
end

return M
