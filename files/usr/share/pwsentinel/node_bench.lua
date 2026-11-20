local nixio = require("nixio")
local uci = require("uci").cursor()

local M = {}

local function test_tcp_direct(host, port, mark)
    local s = nixio.socket("inet", "stream")
    if not s then return nil end
    s:setopt("socket", "rcvtimeo", 2)
    s:setopt("socket", "sndtimeo", 2)
    if mark then pcall(function() s:setopt("socket", "mark", mark) end) end

    local t0, u0 = nixio.gettimeofday()
    local ok = s:connect(host, tonumber(port) or 443)
    local t1, u1 = nixio.gettimeofday()
    s:close()
    if ok then
        return ((t1 - t0) * 1000) + ((u1 - u0) / 1000)
    end
    return nil
end

local function deep_test_node(node_id)
    -- Uses PassWall2 native ephemeral test mechanism on unused local port
    local cmd = string.format("/usr/share/passwall2/test.sh url_test_node %s 2>/dev/null", node_id)
    local f = io.popen(cmd)
    local out = f:read("*a") or ""
    f:close()
    out = out:gsub("%s+", "")
    local code, pre = out:match("(%d+):([%d%.]+)")
    if code == "200" or code == "204" then
        return tonumber(pre) * 1000, "OK"
    elseif code and code ~= "000" then
        return nil, "HTTP_" .. code
    else
        return nil, "FAIL"
    end
end

-- Hardware penalty scoring for low-power ARMv7 CPUs
local function calculate_protocol_penalty(node)
    local penalty = 0
    local proto = (node.protocol or ""):lower()
    local trans = (node.transport or ""):lower()

    if trans:find("grpc") then
        penalty = penalty + 150 -- gRPC multiplexing overhead
    elseif trans:find("xhttp") or trans:find("splithttp") then
        penalty = penalty + 120
    elseif trans:find("quic") or trans:find("h3") or proto:find("hysteria") then
        penalty = penalty + 200 -- High userspace UDP packet rate
    end

    if proto:find("vmess") then
        penalty = penalty + 100 -- Extra encryption layer
    end

    return penalty
end

function M.run(opts)
    opts = opts or {}
    local mark = opts.mark or 255
    local max_candidates = opts.max_candidates or 5
    local nodes = {}

    -- 1. Read all valid proxy nodes from PassWall 2 UCI
    uci:foreach("passwall2", "nodes", function(s)
        if s.address and s.port and s.remarks and
           not s.remarks:match("rulenode") and
           not s.remarks:match("Example") and
           not s.remarks:match("Front") and
           not s.remarks:match("Game") and
           not s.remarks:match("1TB") then
            table.insert(nodes, {
                id = s[".name"],
                remarks = s.remarks,
                protocol = s.protocol or "vless",
                transport = s.transport or "raw",
                address = s.address,
                port = s.port,
                type = s.type or "Xray"
            })
        end
    end)

    if #nodes == 0 then
        return nil, "No valid proxy nodes found in /etc/config/passwall2"
    end

    if not opts.quiet then
        print(string.format("Loaded %d nodes from PassWall 2.", #nodes))
        print("Phase 1: Rapid direct TCP reachability test...")
    end

    -- 2. Phase 1: Test TCP ping directly to node server
    local active_nodes = {}
    for _, n in ipairs(nodes) do
        local rtt = test_tcp_direct(n.address, n.port, mark)
        if rtt then
            n.tcp_rtt = rtt
            table.insert(active_nodes, n)
        end
    end

    -- Sort active nodes by TCP RTT
    table.sort(active_nodes, function(a, b) return a.tcp_rtt < b.tcp_rtt end)

    -- 3. Phase 2: Deep test candidates until we reach target working nodes
    local target_working = math.min(max_candidates, #active_nodes)
    local max_attempts = math.min(target_working * 3, #active_nodes) -- guard against infinite loop if many fail
    local candidates = {}
    local tested_count = 0

    if not opts.quiet then
        print(string.format("Phase 1 completed: %d/%d nodes reachable.", #active_nodes, #nodes))
        print(string.format("Phase 2: Deep censorship bypass test (seeking top %d working candidates)...", target_working))
        print(string.format("%-38s | %-12s | %-12s | %-10s", "Node Name", "TCP Ping", "TTFB (Real)", "Score"))
        print(string.rep("-", 78))
    end

    for _, n in ipairs(active_nodes) do
        if #candidates >= target_working then break end
        tested_count = tested_count + 1
        if tested_count > max_attempts then break end

        local ttfb, status = deep_test_node(n.id)
        n.ttfb = ttfb
        n.status = status

        if status == "OK" and ttfb then
            local penalty = calculate_protocol_penalty(n)
            n.score = ttfb + penalty
            table.insert(candidates, n)
            if not opts.quiet then
                print(string.format("%-38s | %-10.1fms | %-10.1fms | %-8.1f", n.remarks:sub(1, 38), n.tcp_rtt, ttfb, n.score))
            end
        else
            if not opts.quiet then
                print(string.format("%-38s | %-10.1fms | %-12s | N/A", n.remarks:sub(1, 38), n.tcp_rtt, status or "FAIL"))
            end
        end
    end

    -- Pick the winner with the lowest composite score
    table.sort(candidates, function(a, b) return a.score < b.score end)
    local best_node = candidates[1]

    return {
        best_node = best_node,
        candidates = candidates,
        total_nodes = #nodes,
        reachable_nodes = #active_nodes
    }
end

return M
