-- passwall-sentinel - Main Lua Orchestrator
package.path = package.path .. ";/usr/share/?.lua;/usr/share/pwsentinel/?.lua"

local uci = require("uci").cursor()
local node_bench = require("pwsentinel.node_bench")
local dns_bench = require("pwsentinel.dns_bench")
local apply_mod = require("pwsentinel.apply")

local action = arg[1] or "check"
local opt = arg[2]

local STATE_DIR = "/var/run/pwsentinel"
local BENCHMARK_JSON = STATE_DIR .. "/latest_benchmark.json"

local function ensure_state_dir()
    os.execute(string.format("mkdir -p %s", STATE_DIR))
end

-- Lightweight JSON serializer in pure Lua
local function to_json(val)
    local t = type(val)
    if t == "table" then
        local is_array = (#val > 0) or (next(val) == nil and tostring(val):find("table"))
        -- Check if table has string keys
        for k, _ in pairs(val) do
            if type(k) == "string" then is_array = false; break end
        end
        local parts = {}
        if is_array then
            for _, v in ipairs(val) do
                table.insert(parts, to_json(v))
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            for k, v in pairs(val) do
                table.insert(parts, string.format("%q:%s", tostring(k), to_json(v)))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    elseif t == "number" then
        return tostring(val)
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "string" then
        return string.format("%q", val)
    else
        return "null"
    end
end

if action == "check" then
    ensure_state_dir()
    local auto_apply = uci:get("pwsentinel", "main", "auto_apply") or "0"
    local max_candidates = tonumber(uci:get("pwsentinel", "main", "max_nodes_to_test")) or 5
    local mark = tonumber(uci:get("pwsentinel", "main", "bypass_mark")) or 255
    local iface = uci:get("pwsentinel", "main", "direct_interface") or "wan"

    print("================================================================================")
    print("          PASSWALL-SENTINEL: FULL ISOLATED BENCHMARK & AUDIT                    ")
    print("================================================================================")
    print("All tests run strictly via DIRECT WAN traffic. Zero impact on active session.\n")

    print("--- [1/2] BENCHMARKING PASSWALL 2 NODES ---")
    local node_res, err = node_bench.run({ mark = mark, max_candidates = max_candidates })
    if not node_res then
        print("Node benchmark error: " .. tostring(err))
        os.exit(1)
    end

    print("\n--- [2/2] BENCHMARKING 50 DIRECT DNS PROVIDERS ---")
    local dns_res = dns_bench.run({ mark = mark, iface = iface })

    print("\n================================================================================")
    print("                           BENCHMARK SUMMARY                                    ")
    print("================================================================================")
    if node_res.best_node then
        print(string.format("🏆 Best Node: %s (ID: %s)", node_res.best_node.remarks, node_res.best_node.id))
        print(string.format("   Ping: %.1fms | TTFB: %.1fms | Protocol Score: %.1f",
            node_res.best_node.tcp_rtt, node_res.best_node.ttfb or 0, node_res.best_node.score or 0))
    else
        print("❌ No healthy nodes found.")
    end

    if dns_res.best_doh then
        print(string.format("🛡️  Best Remote DoH: %s (%.1fms)", dns_res.best_doh.name, dns_res.best_doh.doh_time or 0))
    end
    if dns_res.best_tcp then
        print(string.format("🚀 Best Direct TCP: %s (%.1fms)", dns_res.best_tcp.name, dns_res.best_tcp.tcp_time or 0))
    end
    if dns_res.best_udp then
        print(string.format("⚡ Best Direct UDP: %s (%.1fms)", dns_res.best_udp.name, dns_res.best_udp.udp_time or 0))
    end
    if dns_res.best_domestic then
        print(string.format("🇮🇷 Best Iranian DNS: %s (%.1fms)", dns_res.best_domestic.name, dns_res.best_domestic.udp_time or 0))
    end
    print("================================================================================")

    -- Save comprehensive results in JSON for the LuCI Web UI
    local full_report = {
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        best_node = node_res.best_node,
        best_doh = dns_res.best_doh,
        best_tcp = dns_res.best_tcp,
        best_udp = dns_res.best_udp,
        best_domestic = dns_res.best_domestic,
        best_direct = dns_res.best_direct,
        nodes = node_res.candidates or {},
        total_nodes = node_res.total_nodes or 0,
        reachable_nodes = node_res.reachable_nodes or 0,
        dns = dns_res.results or {}
    }

    local f = io.open(BENCHMARK_JSON, "w")
    if f then
        f:write(to_json(full_report))
        f:close()
    end

    -- Save latest recommendation in UCI state
    if node_res.best_node then
        uci:set("pwsentinel", "main", "best_node_id", node_res.best_node.id)
        uci:set("pwsentinel", "main", "best_node_name", node_res.best_node.remarks)
    end
    if dns_res.best_doh then
        uci:set("pwsentinel", "main", "best_doh_url", dns_res.best_doh.doh)
        uci:set("pwsentinel", "main", "best_doh_ip", dns_res.best_doh.ip)
    end
    if dns_res.best_direct then
        uci:set("pwsentinel", "main", "best_direct_dns", dns_res.best_direct.ip)
    end
    uci:set("pwsentinel", "main", "last_run_time", os.date("%Y-%m-%d %H:%M:%S"))
    uci:commit("pwsentinel")

    -- Check auto-apply
    local force_auto = (opt == "--auto")
    if force_auto or auto_apply == "1" then
        print("\n[Auto-Apply Active] Applying recommendations to PassWall 2...")
        if node_res.best_node then
            local doh_url = dns_res.best_doh and dns_res.best_doh.doh
            local doh_ip = dns_res.best_doh and dns_res.best_doh.ip
            local direct_ip = dns_res.best_direct and dns_res.best_direct.ip
            apply_mod.apply(node_res.best_node.id, doh_url, doh_ip, direct_ip)
        end
    else
        print("\n[Manual Mode] Recommendations saved. To apply, run: pwsentinel apply")
    end

elseif action == "status" then
    local current_node = uci:get("passwall2", "rulenode", "default_node") or "None"
    local current_node_name = "Unknown"
    if current_node ~= "None" then
        current_node_name = uci:get("passwall2", current_node, "remarks") or current_node
    end
    local current_doh = uci:get("passwall2", "@global[0]", "remote_dns_doh") or "None"

    local best_node = uci:get("pwsentinel", "main", "best_node_name") or "None"
    local best_node_id = uci:get("pwsentinel", "main", "best_node_id") or "None"
    local best_doh = uci:get("pwsentinel", "main", "best_doh_url") or "None"
    local last_run = uci:get("pwsentinel", "main", "last_run_time") or "Never"
    local auto_apply = uci:get("pwsentinel", "main", "auto_apply") or "0"

    print("--- PASSWALL-SENTINEL STATUS ---")
    print(string.format("Active PassWall 2 Node: %s (%s)", current_node_name, current_node))
    print(string.format("Active Remote DoH DNS:  %s", current_doh))
    print(string.format("Auto-Apply Mode:        %s", auto_apply == "1" and "ENABLED (Automatic)" or "DISABLED (Manual Approval)"))
    print(string.format("Last Benchmark Time:    %s", last_run))
    print("---------------------------------")
    print(string.format("Latest Proposed Node:   %s (%s)", best_node, best_node_id))
    print(string.format("Latest Proposed DoH:    %s", best_doh))

elseif action == "apply" then
    local node_id = uci:get("pwsentinel", "main", "best_node_id")
    local doh_url = uci:get("pwsentinel", "main", "best_doh_url")
    local doh_ip = uci:get("pwsentinel", "main", "best_doh_ip")
    local direct_ip = uci:get("pwsentinel", "main", "best_direct_dns")

    if not node_id or node_id == "" then
        print("Error: No recommended node found. Run 'pwsentinel check' first.")
        os.exit(1)
    end

    local ok, msg = apply_mod.apply(node_id, doh_url, doh_ip, direct_ip)
    if not ok then os.exit(1) end

elseif action == "test-nodes" then
    node_bench.run()

elseif action == "test-dns" then
    dns_bench.run()
end
